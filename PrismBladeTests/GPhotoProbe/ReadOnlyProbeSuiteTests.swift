import XCTest
@testable import GPhotoProbe

final class ReadOnlyProbeSuiteTests: XCTestCase {
    func testSuiteRunsAllowedProbeSetAndExportsDiagnosticsWhenPTPIsAvailable() async {
        let store = ProbeLogStore()
        let transport = SpyPTPTransport(canAcceptPTPCommands: true, responseCode: 0x2001)
        let eventStatus = SpyEventStatusProbe()
        let videoPath = SpyVideoPathProbe()
        let suite = ReadOnlyProbeSuite(
            discovery: FakeDiscoveryProbe(transport: transport),
            eventStatus: eventStatus,
            videoPath: videoPath
        )
        let results = await suite.runReadOnlySuite(logStore: store)

        XCTAssertEqual(results.map(\.command), ReadOnlyProbeSuite.orderedCommands)
        XCTAssertTrue(results.allSatisfy { $0.command.isFirstPassAllowed })
        XCTAssertEqual(results.last?.command, .exportDiagnostics)
        XCTAssertEqual(results.last?.status, .passed)
        XCTAssertEqual(transport.sendCallCount, 4)
        XCTAssertEqual(eventStatus.callCount, 1)
        XCTAssertEqual(videoPath.callCount, 1)
        XCTAssertNoThrow(try store.jsonl())
    }

    func testSuiteStopsAtCriticalPauseWhenPTPCapabilityIsMissing() async {
        let store = ProbeLogStore()
        let transport = SpyPTPTransport(canAcceptPTPCommands: false)
        let eventStatus = SpyEventStatusProbe()
        let videoPath = SpyVideoPathProbe()
        let suite = ReadOnlyProbeSuite(
            discovery: FakeDiscoveryProbe(transport: transport),
            eventStatus: eventStatus,
            videoPath: videoPath
        )

        let results = await suite.runReadOnlySuite(logStore: store)

        XCTAssertEqual(results.map(\.command), [.discovery, .abilities, .exportDiagnostics])
        XCTAssertTrue(results[1].requiresUserDecision)
        XCTAssertEqual(results[1].evidence["criticalPause"], "true")
        XCTAssertEqual(transport.sendCallCount, 0)
        XCTAssertEqual(eventStatus.callCount, 0)
        XCTAssertEqual(videoPath.callCount, 0)
    }

    func testSuiteDoesNotAttemptPTPWithoutSelectedCamera() async {
        let store = ProbeLogStore()
        let suite = ReadOnlyProbeSuite(discovery: FakeDiscoveryProbe(targetCamera: nil, transport: nil))

        let results = await suite.runReadOnlySuite(logStore: store)

        XCTAssertEqual(results.map(\.command), [.discovery, .exportDiagnostics])
    }

    func testSuiteStopsForUserSelectionBeforePTPWhenDiscoveryRequiresDecision() async {
        let store = ProbeLogStore()
        let transport = SpyPTPTransport(canAcceptPTPCommands: true)
        let suite = ReadOnlyProbeSuite(
            discovery: FakeDiscoveryProbe(requiresUserDecision: true, transport: transport)
        )

        let results = await suite.runReadOnlySuite(logStore: store)

        XCTAssertEqual(results.map(\.command), [.discovery, .exportDiagnostics])
        XCTAssertEqual(transport.sendCallCount, 0)
    }

    func testVideoPathProbeIsPresenceOnlyAndInconclusiveSafe() async {
        let result = await AVFoundationVideoPathProbe().checkPathExistence()

        XCTAssertEqual(result.command, .videoPathExistence)
        XCTAssertNotEqual(result.status, .failed)
    }
}

private struct FakeDiscoveryProbe: CameraDiscoveryProbe {
    var targetCamera: CameraDeviceProbeDescriptor?
    var requiresUserDecision: Bool
    var transport: (any PTPHardwareTransport)?

    init(
        targetCamera: CameraDeviceProbeDescriptor? = CameraDeviceProbeDescriptor(
            id: "camera-1",
            name: "Nikon Z6III",
            manufacturer: "Nikon",
            model: "Z6III",
            serialNumber: "REDACTED",
            connectionRoute: .imageCaptureCore,
            capabilities: [.canAcceptPTPCommands]
        ),
        requiresUserDecision: Bool = false,
        transport: (any PTPHardwareTransport)?
    ) {
        self.targetCamera = targetCamera
        self.requiresUserDecision = requiresUserDecision
        self.transport = transport
    }

    func discover() async -> CameraDiscoveryOutcome {
        CameraDiscoveryOutcome(
            result: ProbeResult(
                command: .discovery,
                status: targetCamera == nil ? .inconclusive : .passed,
                message: targetCamera == nil ? "No camera discovered." : "Camera discovered.",
                failureLayer: targetCamera == nil ? .physical : nil,
                requiresUserDecision: requiresUserDecision
            ),
            targetCamera: targetCamera,
            ptpTransport: transport
        )
    }
}

private final class SpyEventStatusProbe: EventStatusProbe {
    private(set) var callCount = 0

    func observeStatus() async -> ProbeResult {
        callCount += 1
        return ProbeResult(command: .statusObservation, status: .inconclusive, message: "status")
    }
}

private final class SpyVideoPathProbe: VideoPathProbe {
    private(set) var callCount = 0

    func checkPathExistence() async -> ProbeResult {
        callCount += 1
        return ProbeResult(command: .videoPathExistence, status: .inconclusive, message: "video")
    }
}

private final class SpyPTPTransport: PTPHardwareTransport {
    let canAcceptPTPCommands: Bool
    let responseCode: UInt16
    private(set) var sendCallCount = 0

    init(canAcceptPTPCommands: Bool, responseCode: UInt16 = 0x2001) {
        self.canAcceptPTPCommands = canAcceptPTPCommands
        self.responseCode = responseCode
    }

    func sendAllowlistedPTPCommand(_ packet: PTPCommandPacket) async throws -> PTPTransportResponse {
        sendCallCount += 1
        return PTPTransportResponse(
            responseContainer: Self.responseContainer(code: responseCode, transactionID: packet.transactionID),
            payloadData: Data([0x00]),
            durationMilliseconds: 3
        )
    }

    private static func responseContainer(code: UInt16, transactionID: UInt32) -> Data {
        var data = Data()
        data.appendLittleEndian(UInt32(12))
        data.appendLittleEndian(UInt16(3))
        data.appendLittleEndian(code)
        data.appendLittleEndian(transactionID)
        return data
    }
}

private extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        append(Data(bytes: &littleEndian, count: MemoryLayout<T>.size))
    }
}
