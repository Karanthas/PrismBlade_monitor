import XCTest
@testable import PrismBlade

@MainActor
final class MonitorSessionRealCameraTests: XCTestCase {
    func testAppEnvironmentDefaultsToMockCameraUntilRealCameraIsExplicitlyRequested() {
        withRealCameraPreference(false) {
            let session = AppEnvironment.makeMonitorSession(arguments: ["PrismBlade"])

            XCTAssertFalse(session.isRealCameraMode)
            XCTAssertTrue(session.diagnosticLogText().contains(#""mode":"mock""#))
        }
    }

    func testRealCameraPreferenceEnablesRealCameraModeWithoutLaunchArgument() {
        withRealCameraPreference(true) {
            let session = AppEnvironment.makeMonitorSession(arguments: ["PrismBlade"])

            XCTAssertTrue(session.isRealCameraMode)
            XCTAssertTrue(session.diagnosticLogText().contains(#""mode":"realCamera""#))
            XCTAssertTrue(session.diagnosticLogText().contains(#""usesRealCameraPreference":"true""#))
        }
    }

    func testExplicitMockLaunchArgumentOverridesRealCameraPreference() {
        withRealCameraPreference(true) {
            let session = AppEnvironment.makeMonitorSession(arguments: ["PrismBlade", "-PBUseMockCamera"])

            XCTAssertFalse(session.isRealCameraMode)
            XCTAssertTrue(session.diagnosticLogText().contains(#""mode":"mock""#))
        }
    }

    func testRealCameraNoCameraDoesNotStartFrameSource() async throws {
        let frameSource = InspectableFrameSource()
        let transport = InspectableCameraTransport(connectError: NikonCameraDiscoveryError.noCamera)
        let session = makeSession(frameSource: frameSource, transport: transport)

        session.startMonitoring()
        try await waitUntil { session.state.connection == .noCamera }

        XCTAssertEqual(frameSource.startCount, 0)
        let actions = await transport.triggeredActions()
        XCTAssertEqual(actions, [])
    }

    func testRealCameraMissingPTPCapabilityShowsActionableUnsupportedMessage() async throws {
        let frameSource = InspectableFrameSource()
        let transport = InspectableCameraTransport(connectError: NikonCameraDiscoveryError.missingPTPCapability(model: "Nikon Z6III"))
        let session = makeSession(frameSource: frameSource, transport: transport)

        session.startMonitoring()
        try await waitUntil {
            if case .unsupported(let message) = session.state.connection {
                return message.contains("未报告 PTP 命令能力")
            }
            return false
        }

        XCTAssertEqual(frameSource.startCount, 0)
        XCTAssertTrue(session.diagnosticLogText().contains(#""connectionState":"unsupported""#))
        XCTAssertTrue(session.diagnosticLogText().contains("missingPTPCapability"))
    }

    func testRealCameraActionsAreDisabledBeforeTransportSend() async throws {
        let frameSource = InspectableFrameSource()
        let transport = InspectableCameraTransport()
        let session = makeSession(frameSource: frameSource, transport: transport)

        session.startMonitoring()
        try await waitUntil { session.state.connection.isConnected }

        session.triggerCameraAction(.capture)
        session.triggerCameraAction(.toggleRecord)
        session.triggerCameraAction(.focus)
        try await Task.sleep(nanoseconds: 40_000_000)

        let actions = await transport.triggeredActions()
        XCTAssertEqual(actions, [])
    }

    func testRealCameraDoesNotApplyPersistedMockExposureMode() async throws {
        let defaults = UserDefaults.standard
        let key = "PrismBlade.mockExposureMode"
        let previousValue = defaults.string(forKey: key)
        defaults.set(ExposureMode.shutterPriority.rawValue, forKey: key)
        defer {
            if let previousValue {
                defaults.set(previousValue, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }

        var realState = CameraState.mockInitial
        realState.exposureMode.current = ExposureMode.aperturePriority.rawValue
        let session = makeSession(frameSource: InspectableFrameSource(), transport: InspectableCameraTransport(state: realState))

        session.startMonitoring()
        try await waitUntil { session.state.connection.isConnected }

        XCTAssertEqual(session.state.camera.exposureMode.current, ExposureMode.aperturePriority.rawValue)
    }

    func testLiveViewDecodeFailureDoesNotDisconnectControlTransport() async throws {
        let frameSource = FailingFrameSource(connectionLoss: false, reason: "invalid JPEG")
        let transport = InspectableCameraTransport()
        let session = makeSession(frameSource: frameSource, transport: transport)

        session.startMonitoring()
        try await waitUntil { session.lastUserMessage?.contains("实时取景失败") == true }

        XCTAssertEqual(session.state.connection, .connected)
        let disconnectCount = await transport.disconnectCount()
        XCTAssertEqual(disconnectCount, 0)
    }

    func testLiveViewConnectionLossStartsBoundedReconnect() async throws {
        let frameSource = FailingFrameSource(connectionLoss: true, reason: "camera disconnected")
        let transport = InspectableCameraTransport()
        let session = makeSession(frameSource: frameSource, transport: transport)

        session.startMonitoring()
        try await waitUntil { session.state.connection == .reconnecting(attempt: 1) }

        let disconnectCount = await transport.disconnectCount()
        XCTAssertEqual(disconnectCount, 1)
        XCTAssertEqual(frameSource.stopCount, 1)
    }

    func testReconnectRetriesAfterNoCameraAndRestartsLiveView() async throws {
        let frameSource = ReconnectingFrameSource()
        let transport = InspectableCameraTransport(connectResults: [
            .success(()),
            .failure(NikonCameraDiscoveryError.noCamera),
            .success(())
        ])
        let session = makeSession(frameSource: frameSource, transport: transport)

        session.startMonitoring()
        try await waitUntil(timeoutNanoseconds: 3_500_000_000) {
            session.state.connection.isConnected && frameSource.startCount == 2
        }

        let connectCount = await transport.connectCount()
        let disconnectCount = await transport.disconnectCount()
        XCTAssertEqual(connectCount, 3)
        XCTAssertEqual(disconnectCount, 1)
        XCTAssertEqual(frameSource.stopCount, 1)
        XCTAssertEqual(frameSource.status, .running)
    }

    func testManualRealCameraReconnectStartsLiveViewAfterInitialNoCamera() async throws {
        let frameSource = InspectableFrameSource()
        let transport = InspectableCameraTransport(connectResults: [
            .failure(NikonCameraDiscoveryError.noCamera),
            .success(())
        ])
        let session = makeSession(frameSource: frameSource, transport: transport)

        session.startMonitoring()
        try await waitUntil { session.state.connection == .noCamera }

        session.reconnectCamera()
        try await waitUntil { session.state.connection.isConnected && frameSource.startCount == 1 }

        let connectCount = await transport.connectCount()
        XCTAssertEqual(connectCount, 2)
        XCTAssertEqual(frameSource.status, .running)
    }

    func testStopDuringSlowConnectDoesNotResurrectConnectedStateOrStartLiveView() async throws {
        let frameSource = InspectableFrameSource()
        let transport = SlowConnectCameraTransport()
        let session = makeSession(frameSource: frameSource, transport: transport)

        session.startMonitoring()
        try await waitUntilAsync {
            await transport.isConnectPending()
        }

        session.stopMonitoring()
        await transport.completeConnect()
        try await Task.sleep(nanoseconds: 80_000_000)

        XCTAssertFalse(session.state.connection.isConnected)
        XCTAssertEqual(frameSource.startCount, 0)
    }

    func testReconnectAttemptBudgetResetsAfterSuccessfulReconnect() async throws {
        let frameSource = ManuallyFailingFrameSource()
        let transport = InspectableCameraTransport(connectResults: [
            .success(()),
            .failure(NikonCameraDiscoveryError.noCamera),
            .success(()),
            .success(())
        ])
        let session = makeSession(frameSource: frameSource, transport: transport)

        session.startMonitoring()
        try await waitUntil(timeoutNanoseconds: 3_500_000_000) {
            session.state.connection.isConnected && frameSource.startCount == 2
        }

        frameSource.failRunningStream(reason: "camera disconnected again")
        try await waitUntilAsync(timeoutNanoseconds: 2_000_000_000) {
            await transport.connectCount() == 4
        }

        let connectCount = await transport.connectCount()
        XCTAssertEqual(connectCount, 4)
        XCTAssertTrue(session.state.connection.isConnected)
    }

    private func makeSession(frameSource: FrameSource, transport: CameraTransport) -> MonitorSession {
        MonitorSession(
            frameSource: frameSource,
            cameraService: CameraCommandService(transport: transport),
            lutRepository: LUTRepository(),
            cameraMode: .realCamera
        )
    }

    private func withRealCameraPreference(_ isEnabled: Bool, _ run: () -> Void) {
        let defaults = UserDefaults.standard
        let previousValue = defaults.object(forKey: AppEnvironment.realCameraPreferenceKey)
        AppEnvironment.setRealCameraPreferenceEnabled(isEnabled)
        defer {
            if let previousValue {
                defaults.set(previousValue, forKey: AppEnvironment.realCameraPreferenceKey)
            } else {
                defaults.removeObject(forKey: AppEnvironment.realCameraPreferenceKey)
            }
        }
        run()
    }

    private func waitUntil(
        timeoutNanoseconds: UInt64 = 1_000_000_000,
        _ predicate: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(Double(timeoutNanoseconds) / 1_000_000_000)
        while Date() < deadline {
            if predicate() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Timed out waiting for condition.")
    }

    private func waitUntilAsync(
        timeoutNanoseconds: UInt64 = 1_000_000_000,
        _ predicate: @escaping () async -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(Double(timeoutNanoseconds) / 1_000_000_000)
        while Date() < deadline {
            if await predicate() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Timed out waiting for condition.")
    }
}

private final class FailingFrameSource: FrameSource, FrameSourceConnectionLossReporting {
    private(set) var status: FrameSourceStatus = .stopped
    private(set) var format: FrameFormat?
    private(set) var didFailFromConnectionLoss: Bool
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private let reason: String
    private var continuation: AsyncStream<VideoFrame>.Continuation?

    init(connectionLoss: Bool, reason: String) {
        didFailFromConnectionLoss = connectionLoss
        self.reason = reason
    }

    func start() async throws {
        startCount += 1
        status = .failed(reason)
        continuation?.finish()
    }

    func stop() async {
        stopCount += 1
        status = .stopped
    }

    func frames() -> AsyncStream<VideoFrame> {
        AsyncStream { continuation in
            self.continuation = continuation
        }
    }
}

private final class InspectableFrameSource: FrameSource {
    private(set) var status: FrameSourceStatus = .stopped
    private(set) var format: FrameFormat?
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func start() async throws {
        startCount += 1
        status = .running
    }

    func stop() async {
        stopCount += 1
        status = .stopped
    }

    func frames() -> AsyncStream<VideoFrame> {
        AsyncStream { _ in }
    }
}

private final class ReconnectingFrameSource: FrameSource, FrameSourceConnectionLossReporting {
    private(set) var status: FrameSourceStatus = .stopped
    private(set) var format: FrameFormat?
    private(set) var didFailFromConnectionLoss = false
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private var continuations: [AsyncStream<VideoFrame>.Continuation] = []

    func start() async throws {
        startCount += 1
        if startCount == 1 {
            didFailFromConnectionLoss = true
            status = .failed("camera disconnected")
            continuations.last?.finish()
            return
        }

        didFailFromConnectionLoss = false
        status = .running
    }

    func stop() async {
        stopCount += 1
        status = .stopped
    }

    func frames() -> AsyncStream<VideoFrame> {
        AsyncStream { continuation in
            continuations.append(continuation)
        }
    }
}

private final class ManuallyFailingFrameSource: FrameSource, FrameSourceConnectionLossReporting {
    private(set) var status: FrameSourceStatus = .stopped
    private(set) var format: FrameFormat?
    private(set) var didFailFromConnectionLoss = false
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private var continuations: [AsyncStream<VideoFrame>.Continuation] = []

    func start() async throws {
        startCount += 1
        if startCount == 1 {
            didFailFromConnectionLoss = true
            status = .failed("camera disconnected")
            continuations.last?.finish()
            return
        }

        didFailFromConnectionLoss = false
        status = .running
    }

    func stop() async {
        stopCount += 1
        status = .stopped
    }

    func frames() -> AsyncStream<VideoFrame> {
        AsyncStream { continuation in
            continuations.append(continuation)
        }
    }

    func failRunningStream(reason: String) {
        didFailFromConnectionLoss = true
        status = .failed(reason)
        continuations.last?.finish()
    }
}

private actor InspectableCameraTransport: CameraTransport {
    private var state: CameraState
    private var isConnected = false
    private var connectResults: [Result<Void, Error>]
    private var actions: [CameraAction] = []
    private var connects = 0
    private var disconnects = 0

    init(
        state: CameraState = .mockInitial,
        connectError: Error? = nil,
        connectResults: [Result<Void, Error>]? = nil
    ) {
        self.state = state
        if let connectResults {
            self.connectResults = connectResults
        } else if let connectError {
            self.connectResults = [.failure(connectError)]
        } else {
            self.connectResults = []
        }
    }

    func connect() async throws {
        connects += 1
        if !connectResults.isEmpty {
            switch connectResults.removeFirst() {
            case .success:
                isConnected = true
                return
            case .failure(let error):
                isConnected = false
                throw error
            }
        }

        isConnected = true
    }

    func disconnect() async {
        isConnected = false
        disconnects += 1
    }

    func currentState() async throws -> CameraState {
        guard isConnected else { throw CameraTransportError.notConnected }
        return state
    }

    func setValue(_ value: String, for parameter: CameraParameter) async throws -> CameraState {
        guard isConnected else { throw CameraTransportError.notConnected }
        return state
    }

    func trigger(_ action: CameraAction) async throws -> CameraState {
        actions.append(action)
        guard isConnected else { throw CameraTransportError.notConnected }
        return state
    }

    func triggeredActions() -> [CameraAction] {
        actions
    }

    func disconnectCount() -> Int {
        disconnects
    }

    func connectCount() -> Int {
        connects
    }
}

private actor SlowConnectCameraTransport: CameraTransport {
    private var state = CameraState.mockInitial
    private var isConnected = false
    private var connectContinuation: CheckedContinuation<Void, Error>?

    func connect() async throws {
        try await withCheckedThrowingContinuation { continuation in
            connectContinuation = continuation
        }
        isConnected = true
    }

    func disconnect() async {
        isConnected = false
    }

    func currentState() async throws -> CameraState {
        guard isConnected else { throw CameraTransportError.notConnected }
        return state
    }

    func setValue(_ value: String, for parameter: CameraParameter) async throws -> CameraState {
        guard isConnected else { throw CameraTransportError.notConnected }
        return state
    }

    func trigger(_ action: CameraAction) async throws -> CameraState {
        guard isConnected else { throw CameraTransportError.notConnected }
        return state
    }

    func isConnectPending() -> Bool {
        connectContinuation != nil
    }

    func completeConnect() {
        let continuation = connectContinuation
        connectContinuation = nil
        continuation?.resume(returning: ())
    }
}
