import XCTest
@testable import PrismBlade

final class PTPFoundationTests: XCTestCase {
    func testPolicyAllowsOnlyPlannedOperations() throws {
        let policy = PTPOperationPolicy()

        XCTAssertEqual(try policy.validate(.liveViewStart).operation, .startLiveView)
        XCTAssertEqual(try policy.validate(.liveViewFrameFetch).operation, .getLiveViewImage)
        XCTAssertEqual(try policy.validate(.liveViewEnd).operation, .endLiveView)
        XCTAssertEqual(try policy.validate(.readDeviceInfo).operation, .getDeviceInfo)
        XCTAssertEqual(try policy.validate(.readPropertyDescription(0x500F)).parameters, [0x500F])
        XCTAssertEqual(try policy.validate(.readPropertyValue(0x500F)).operation, .getDevicePropValue)

        let write = try policy.validate(.writeImmediateControl(
            parameter: .iso,
            propertyCode: 0x500F,
            encodedValue: Data([0x64, 0x00])
        ))
        XCTAssertEqual(write.operation, .setDevicePropValue)
        XCTAssertEqual(write.dataPhase, .outboundDataRequired)

        let liveViewSizeWrite = try policy.validate(.selectNikonLiveViewSize(
            propertyCode: NikonPTPDeviceProperty.liveViewSize,
            encodedValue: Data([0x02, 0x00])
        ))
        XCTAssertEqual(liveViewSizeWrite.operation, .setDevicePropValue)
        XCTAssertEqual(liveViewSizeWrite.parameters, [UInt32(NikonPTPDeviceProperty.liveViewSize)])
        XCTAssertEqual(liveViewSizeWrite.diagnosticName, "ptp.setDevicePropValue.nikonLiveViewSize")
    }

    func testPolicyRejectsInvalidLiveViewSizeWritesBeforePacketConstruction() async throws {
        let transport = RecordingPTPTransport(responseCode: .ok)
        let client = PTPClient(transport: transport)

        do {
            _ = try await client.send(.selectNikonLiveViewSize(propertyCode: 0xD001, encodedValue: Data([0x02, 0x00])))
            XCTFail("Mismatched liveviewsize property must fail before transport send.")
        } catch PTPOperationPolicyError.mismatchedLiveViewSizeProperty(let expected, let actual) {
            XCTAssertEqual(expected, NikonPTPDeviceProperty.liveViewSize)
            XCTAssertEqual(actual, 0xD001)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        do {
            _ = try await client.send(.selectNikonLiveViewSize(propertyCode: NikonPTPDeviceProperty.liveViewSize, encodedValue: Data()))
            XCTFail("Empty liveviewsize payload must fail before transport send.")
        } catch PTPOperationPolicyError.emptyLiveViewSizePayload {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        do {
            _ = try await client.send(.selectNikonLiveViewSize(propertyCode: NikonPTPDeviceProperty.liveViewSize, encodedValue: Data([0x04])))
            XCTFail("Unapproved liveviewsize raw value must fail before transport send.")
        } catch PTPOperationPolicyError.unsupportedLiveViewSizeRawValue(let rawValue) {
            XCTAssertEqual(rawValue, 4)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let sentPackets = await transport.sentPacketSnapshot()
        XCTAssertEqual(sentPackets.count, 0)
    }

    func testPolicyRejectsMismatchedImmediateWritePropertyBeforePacketConstruction() async throws {
        let transport = RecordingPTPTransport(responseCode: .ok)
        let client = PTPClient(transport: transport)

        do {
            _ = try await client.send(.writeImmediateControl(
                parameter: .iso,
                propertyCode: 0xD001,
                encodedValue: Data([0x64, 0x00])
            ))
            XCTFail("Mismatched write property must fail before transport send.")
        } catch PTPOperationPolicyError.mismatchedWriteProperty(let parameter, let expected, let actual) {
            XCTAssertEqual(parameter, .iso)
            XCTAssertEqual(expected, 0x500F)
            XCTAssertEqual(actual, 0xD001)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let sentPackets = await transport.sentPacketSnapshot()
        XCTAssertEqual(sentPackets.count, 0)
    }

    func testPolicyRejectsForbiddenAndRawOperationsBeforePacketConstruction() async throws {
        let transport = RecordingPTPTransport(responseCode: .ok)
        let client = PTPClient(transport: transport)

        do {
            _ = try await client.send(.forbidden(.capture))
            XCTFail("Forbidden operations must fail before transport send.")
        } catch PTPOperationPolicyError.forbiddenOperation(let operation) {
            XCTAssertEqual(operation, .capture)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        do {
            _ = try await client.send(.raw(operationCode: 0x100E, parameters: [], outboundData: nil))
            XCTFail("Raw operation bypass must fail before transport send.")
        } catch PTPOperationPolicyError.rawOperationBypass(let operationCode) {
            XCTAssertEqual(operationCode, 0x100E)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let sentPackets = await transport.sentPacketSnapshot()
        XCTAssertEqual(sentPackets.count, 0)
    }

    func testPacketEncodingAndResponseParsingAreLittleEndian() async throws {
        let transport = RecordingPTPTransport(responseCode: .ok)
        let client = PTPClient(transport: transport, initialTransactionID: 7)

        _ = try await client.send(.readPropertyDescription(0x500F))
        let encodedCommand = await transport.sentPacketSnapshot().first?.encodedCommand.map { $0 }
        XCTAssertEqual(encodedCommand, [
            16, 0, 0, 0,
            1, 0,
            0x14, 0x10,
            7, 0, 0, 0,
            0x0F, 0x50, 0, 0
        ])

        let parsed = try PTPResponseParser.parse(.ptpResponse(code: 0x2001, transactionID: 7, parameters: [0x500F]))
        XCTAssertEqual(parsed.code, .ok)
        XCTAssertEqual(parsed.transactionID, 7)
        XCTAssertEqual(parsed.parameters, [0x500F])
    }

    func testResponseParserRejectsMismatchedLengthAndUnalignedParameters() throws {
        var mismatchedLength = Data.ptpResponse(code: 0x2001, transactionID: 7)
        mismatchedLength.replaceSubrange(0..<4, with: UInt32(99).littleEndianData)

        XCTAssertThrowsError(try PTPResponseParser.parse(mismatchedLength)) { error in
            XCTAssertEqual(error as? PTPResponseParseError, .mismatchedContainerLength(declared: 99, actual: 12))
        }

        var unalignedParameters = Data.ptpResponse(code: 0x2001, transactionID: 7)
        unalignedParameters.append(0x01)
        unalignedParameters.replaceSubrange(0..<4, with: UInt32(unalignedParameters.count).littleEndianData)

        XCTAssertThrowsError(try PTPResponseParser.parse(unalignedParameters)) { error in
            XCTAssertEqual(error as? PTPResponseParseError, .unalignedParameterBytes(1))
        }
    }

    func testClientSerializesTransactionIDsAndRecordsDiagnostics() async throws {
        let diagnostics = PTPDiagnosticsRecorder()
        let transport = RecordingPTPTransport(responseCode: .ok, payloadData: Data([1, 2, 3]))
        let client = PTPClient(transport: transport, diagnostics: diagnostics, initialTransactionID: 41)

        let result = try await client.send(.readPropertyValue(0x500F))

        XCTAssertEqual(result.transactionID, 41)
        XCTAssertEqual(result.payloadData, Data([1, 2, 3]))
        let sentPackets = await transport.sentPacketSnapshot()
        XCTAssertEqual(sentPackets.map(\.transactionID), [41])

        let fields = await diagnostics.events().map(\.fields)
        XCTAssertEqual(fields.first?["event"], "ptp.send.started")
        XCTAssertEqual(fields.first?["operationCode"], "0x1015")
        XCTAssertEqual(fields.last?["responseCode"], "0x2001")
    }

    func testDiscoveryDiagnosticsRecordAuthorizationAndBrowserSnapshot() async throws {
        let diagnostics = PTPDiagnosticsRecorder()

        await diagnostics.record(.discoveryAuthorization(contents: "authorized", control: "notDetermined"))
        await diagnostics.record(.discoveryBrowserSnapshot(
            cameraCount: 0,
            browserDeviceCount: 2,
            isBrowsing: true,
            contentsAuthorization: "authorized",
            controlAuthorization: "authorized"
        ))

        let fields = await diagnostics.events().map(\.fields)
        XCTAssertEqual(fields.first?["event"], "discovery.authorization")
        XCTAssertEqual(fields.first?["contentsAuthorization"], "authorized")
        XCTAssertEqual(fields.first?["controlAuthorization"], "notDetermined")
        XCTAssertEqual(fields.last?["event"], "discovery.browserSnapshot")
        XCTAssertEqual(fields.last?["cameraCount"], "0")
        XCTAssertEqual(fields.last?["browserDeviceCount"], "2")
        XCTAssertEqual(fields.last?["browserIsBrowsing"], "true")
    }

    func testClientSurfacesNonOKResponse() async throws {
        let transport = RecordingPTPTransport(responseCode: .deviceBusy)
        let client = PTPClient(transport: transport)

        do {
            _ = try await client.send(.readDeviceInfo)
            XCTFail("Device busy should fail.")
        } catch PTPClientError.responseError(let code, let rawCode) {
            XCTAssertEqual(code, .deviceBusy)
            XCTAssertEqual(rawCode, 0x2019)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testClientRejectsMismatchedResponseTransactionID() async throws {
        let transport = RecordingPTPTransport(responseCode: .ok, responseTransactionID: 99)
        let client = PTPClient(transport: transport, initialTransactionID: 12)

        do {
            _ = try await client.send(.readDeviceInfo)
            XCTFail("A mismatched response transaction must fail.")
        } catch PTPClientError.transactionMismatch(let expected, let actual) {
            XCTAssertEqual(expected, 12)
            XCTAssertEqual(actual, 99)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testClientTimesOutHangingTransportAndRecordsDiagnostics() async throws {
        let diagnostics = PTPDiagnosticsRecorder()
        let transport = HangingPTPTransport()
        let client = PTPClient(
            transport: transport,
            diagnostics: diagnostics,
            initialTransactionID: 9,
            sendTimeoutNanoseconds: 20_000_000
        )

        do {
            _ = try await client.send(.readDeviceInfo)
            XCTFail("A hanging PTP transport must time out.")
        } catch PTPClientError.timeout(let operationCode, let transactionID, let durationMilliseconds) {
            XCTAssertEqual(operationCode, NikonPTPOperation.getDeviceInfo.rawValue)
            XCTAssertEqual(transactionID, 9)
            XCTAssertEqual(durationMilliseconds, 20)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        try await Task.sleep(nanoseconds: 40_000_000)
        let sentPackets = await transport.sentPacketSnapshot()
        XCTAssertEqual(sentPackets.map(\.transactionID), [9])
        let cancellationCount = await transport.cancellationCount()
        XCTAssertEqual(cancellationCount, 1)

        let fields = await diagnostics.events().map(\.fields)
        XCTAssertEqual(fields.first?["event"], "ptp.send.started")
        XCTAssertEqual(fields.last?["event"], "ptp.send.timeout")
        XCTAssertEqual(fields.last?["operationCode"], "0x1001")
        XCTAssertEqual(fields.last?["transactionID"], "9")
    }

    func testTimedOutNonCancellableTransportBlocksSecondSendUntilCallbackResolves() async throws {
        let transport = ControlledPTPTransport()
        let client = PTPClient(transport: transport, initialTransactionID: 30, sendTimeoutNanoseconds: 20_000_000)

        do {
            _ = try await client.send(.readDeviceInfo)
            XCTFail("A pending controlled transport must time out.")
        } catch PTPClientError.timeout(let operationCode, let transactionID, _) {
            XCTAssertEqual(operationCode, NikonPTPOperation.getDeviceInfo.rawValue)
            XCTAssertEqual(transactionID, 30)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        do {
            _ = try await client.send(.readPropertyValue(0x500F))
            XCTFail("The client must not send again while the timed-out hardware request is unresolved.")
        } catch PTPClientError.timedOutOperationStillInFlight(let operationCode, let transactionID) {
            XCTAssertEqual(operationCode, NikonPTPOperation.getDeviceInfo.rawValue)
            XCTAssertEqual(transactionID, 30)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        var sentPackets = await transport.sentPacketSnapshot()
        XCTAssertEqual(sentPackets.map(\.transactionID), [30])

        await transport.completeOldestResponse()
        try await waitUntil {
            await transport.pendingResponseCount() == 0
        }

        try await waitUntil(timeoutNanoseconds: 1_000_000_000) {
            do {
                _ = try await client.send(.readPropertyValue(0x500F))
                return true
            } catch PTPClientError.timedOutOperationStillInFlight {
                return false
            } catch {
                XCTFail("Unexpected error after timed-out callback resolved: \(error)")
                return false
            }
        }
        sentPackets = await transport.sentPacketSnapshot()
        XCTAssertEqual(sentPackets.map(\.transactionID), [30, 31])
    }

    func testResetAfterDisconnectAllowsFreshSessionAfterTimedOutRequest() async throws {
        let transport = ControlledPTPTransport()
        let client = PTPClient(transport: transport, initialTransactionID: 50, sendTimeoutNanoseconds: 20_000_000)

        do {
            _ = try await client.send(.readDeviceInfo)
            XCTFail("A pending controlled transport must time out.")
        } catch PTPClientError.timeout(let operationCode, let transactionID, _) {
            XCTAssertEqual(operationCode, NikonPTPOperation.getDeviceInfo.rawValue)
            XCTAssertEqual(transactionID, 50)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        await client.resetSessionAfterDisconnect()
        _ = try await client.send(.readPropertyValue(0x500F))

        let sentPackets = await transport.sentPacketSnapshot()
        XCTAssertEqual(sentPackets.map(\.transactionID), [50, 51])
        let pendingResponseCount = await transport.pendingResponseCount()
        XCTAssertEqual(pendingResponseCount, 1)
    }

    func testCancelledNonCancellableTransportBlocksSecondSendUntilCallbackResolves() async throws {
        let transport = ControlledPTPTransport()
        let client = PTPClient(transport: transport, initialTransactionID: 40, sendTimeoutNanoseconds: 1_000_000_000)

        let firstSend = Task {
            try await client.send(.readDeviceInfo)
        }
        try await waitUntil {
            await transport.pendingResponseCount() == 1
        }

        firstSend.cancel()
        do {
            _ = try await firstSend.value
            XCTFail("Cancelled send must throw.")
        } catch is CancellationError {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        do {
            _ = try await client.send(.readPropertyValue(0x500F))
            XCTFail("The client must not send again while the cancelled hardware request is unresolved.")
        } catch PTPClientError.timedOutOperationStillInFlight(let operationCode, let transactionID) {
            XCTAssertEqual(operationCode, NikonPTPOperation.getDeviceInfo.rawValue)
            XCTAssertEqual(transactionID, 40)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        var sentPackets = await transport.sentPacketSnapshot()
        XCTAssertEqual(sentPackets.map(\.transactionID), [40])

        await transport.completeOldestResponse()
        try await waitUntil(timeoutNanoseconds: 1_000_000_000) {
            do {
                _ = try await client.send(.readPropertyValue(0x500F))
                return true
            } catch PTPClientError.timedOutOperationStillInFlight {
                return false
            } catch {
                XCTFail("Unexpected error after cancelled callback resolved: \(error)")
                return false
            }
        }

        sentPackets = await transport.sentPacketSnapshot()
        XCTAssertEqual(sentPackets.map(\.transactionID), [40, 41])
    }

    func testClientKeepsOnePhysicalSendInFlightAtATime() async throws {
        let transport = ControlledPTPTransport()
        let client = PTPClient(transport: transport, sendTimeoutNanoseconds: 1_000_000_000)

        let firstSend = Task {
            try await client.send(.readDeviceInfo)
        }
        try await waitUntil {
            await transport.pendingResponseCount() == 1
        }

        let secondSend = Task {
            try await client.send(.readPropertyValue(0x500F))
        }
        try await Task.sleep(nanoseconds: 40_000_000)
        var sentPackets = await transport.sentPacketSnapshot()
        XCTAssertEqual(sentPackets.map(\.transactionID), [1])

        await transport.completeOldestResponse()
        _ = try await firstSend.value
        try await waitUntil {
            await transport.sentPacketSnapshot().map(\.transactionID) == [1, 2]
        }

        _ = try await secondSend.value
        sentPackets = await transport.sentPacketSnapshot()
        XCTAssertEqual(sentPackets.map(\.transactionID), [1, 2])
    }

    func testCancelledQueuedSendDoesNotReachPhysicalTransport() async throws {
        let transport = ControlledPTPTransport()
        let client = PTPClient(transport: transport, sendTimeoutNanoseconds: 1_000_000_000)

        let firstSend = Task {
            try await client.send(.readDeviceInfo)
        }
        try await waitUntil {
            await transport.pendingResponseCount() == 1
        }

        let queuedSend = Task {
            try await client.send(.readPropertyValue(0x500F))
        }
        try await Task.sleep(nanoseconds: 40_000_000)
        queuedSend.cancel()

        await transport.completeOldestResponse()
        _ = try await firstSend.value

        do {
            _ = try await queuedSend.value
            XCTFail("Cancelled queued send must throw before packet construction.")
        } catch is CancellationError {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let sentPackets = await transport.sentPacketSnapshot()
        XCTAssertEqual(sentPackets.map(\.transactionID), [1])
    }

    func testDiscoverySelectsAuthorizedNikonPTPCamera() async throws {
        let diagnostics = PTPDiagnosticsRecorder()
        let service = NikonCameraDiscoveryService(
            bridge: StaticNikonCameraDiscoveryBridge(descriptors: [
                NikonCameraDescriptor(
                    name: "NIKON Z 6_3",
                    manufacturer: "Nikon",
                    model: "Z 6_3",
                    serialNumber: "123456789",
                    authorization: .authorized,
                    capabilities: [.canAcceptPTPCommands]
                )
            ]),
            diagnostics: diagnostics
        )

        let descriptor = try await service.discoverSupportedCamera()

        XCTAssertTrue(descriptor.isNikonZ6III)
        let selectedFields = await diagnostics.events().last?.fields
        XCTAssertEqual(selectedFields?["event"], "camera.selected")
        XCTAssertEqual(selectedFields?["serialNumber"], "REDACTED-6789")
    }

    func testDiscoveryAllowsGenericImageCaptureCameraWithPTPCapability() throws {
        let selector = NikonCameraSelector()

        let descriptor = try selector.selectSupportedCamera(from: [
            NikonCameraDescriptor(
                name: "Camera",
                manufacturer: "ImageCapture",
                model: "ImageCapture Camera",
                serialNumber: nil,
                authorization: .authorized,
                capabilities: [.canAcceptPTPCommands]
            )
        ])

        XCTAssertEqual(descriptor.model, "ImageCapture Camera")
        XCTAssertTrue(descriptor.canAcceptPTPCommands)
    }

    func testDiscoveryRejectsNoCameraPermissionAndMissingCapability() async throws {
        let selector = NikonCameraSelector()

        XCTAssertThrowsError(try selector.selectSupportedCamera(from: [])) { error in
            XCTAssertEqual(error as? NikonCameraDiscoveryError, .noCamera)
        }

        XCTAssertThrowsError(try selector.selectSupportedCamera(from: [
            NikonCameraDescriptor(
                name: "NIKON Z 6_3",
                manufacturer: "Nikon",
                model: "Z 6_3",
                serialNumber: nil,
                authorization: .denied,
                capabilities: [.canAcceptPTPCommands]
            )
        ])) { error in
            XCTAssertEqual(error as? NikonCameraDiscoveryError, .authorizationDenied(.denied))
        }

        XCTAssertThrowsError(try selector.selectSupportedCamera(from: [
            NikonCameraDescriptor(
                name: "NIKON Z 6_3",
                manufacturer: "Nikon",
                model: "Z 6_3",
                serialNumber: nil,
                authorization: .authorized,
                capabilities: []
            )
        ])) { error in
            XCTAssertEqual(error as? NikonCameraDiscoveryError, .missingPTPCapability(model: "Z 6_3"))
        }
    }

    func testDiscoveryReportsPermissionDeniedWithoutDiscoveredDescriptors() async throws {
        let diagnostics = PTPDiagnosticsRecorder()
        let service = NikonCameraDiscoveryService(
            bridge: AuthorizationOnlyDiscoveryBridge(authorization: .denied),
            diagnostics: diagnostics
        )

        do {
            _ = try await service.discoverSupportedCamera()
            XCTFail("Denied authorization should not be reported as no camera.")
        } catch NikonCameraDiscoveryError.authorizationDenied(let state) {
            XCTAssertEqual(state, .denied)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let fields = await diagnostics.events().last?.fields
        XCTAssertEqual(fields?["event"], "gate.failed")
        XCTAssertTrue(fields?["reason"]?.contains("denied") ?? false)
    }

    private func waitUntil(
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

private struct AuthorizationOnlyDiscoveryBridge: NikonCameraDiscoveryBridge {
    var authorization: CameraAuthorizationState

    func discoverCameras() async -> [NikonCameraDescriptor] {
        []
    }

    func authorizationState() async -> CameraAuthorizationState? {
        authorization
    }
}

private actor RecordingPTPTransport: PTPCommandTransport {
    private(set) var sentPackets: [PTPCommandPacket] = []
    private let responseCode: PTPResponseCode
    private let payloadData: Data
    private let responseTransactionID: UInt32?

    init(responseCode: PTPResponseCode, payloadData: Data = Data(), responseTransactionID: UInt32? = nil) {
        self.responseCode = responseCode
        self.payloadData = payloadData
        self.responseTransactionID = responseTransactionID
    }

    func send(_ packet: PTPCommandPacket, outboundData: Data?) async throws -> PTPTransportResponse {
        sentPackets.append(packet)
        return PTPTransportResponse(
            responseContainer: .ptpResponse(code: responseCode.rawValue, transactionID: responseTransactionID ?? packet.transactionID),
            payloadData: payloadData,
            durationMilliseconds: 3
        )
    }

    func sentPacketSnapshot() -> [PTPCommandPacket] {
        sentPackets
    }
}

private actor HangingPTPTransport: PTPCommandTransport {
    private(set) var sentPackets: [PTPCommandPacket] = []
    private var cancellations = 0

    func send(_ packet: PTPCommandPacket, outboundData: Data?) async throws -> PTPTransportResponse {
        sentPackets.append(packet)
        do {
            try await Task.sleep(nanoseconds: 60_000_000_000)
        } catch {
            cancellations += 1
            throw error
        }

        throw CancellationError()
    }

    func sentPacketSnapshot() -> [PTPCommandPacket] {
        sentPackets
    }

    func cancellationCount() -> Int {
        cancellations
    }
}

private actor ControlledPTPTransport: PTPCommandTransport {
    private(set) var sentPackets: [PTPCommandPacket] = []
    private var continuations: [CheckedContinuation<PTPTransportResponse, Error>] = []

    func send(_ packet: PTPCommandPacket, outboundData: Data?) async throws -> PTPTransportResponse {
        sentPackets.append(packet)
        if sentPackets.count > 1 {
            return PTPTransportResponse(
                responseContainer: .ptpResponse(code: PTPResponseCode.ok.rawValue, transactionID: packet.transactionID),
                payloadData: Data(),
                durationMilliseconds: 1
            )
        }

        return try await withCheckedThrowingContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func completeOldestResponse() {
        guard !continuations.isEmpty, let packet = sentPackets.first else { return }
        let continuation = continuations.removeFirst()
        continuation.resume(returning: PTPTransportResponse(
            responseContainer: .ptpResponse(code: PTPResponseCode.ok.rawValue, transactionID: packet.transactionID),
            payloadData: Data(),
            durationMilliseconds: 50
        ))
    }

    func sentPacketSnapshot() -> [PTPCommandPacket] {
        sentPackets
    }

    func pendingResponseCount() -> Int {
        continuations.count
    }
}

private extension Data {
    static func ptpResponse(code: UInt16, transactionID: UInt32, parameters: [UInt32] = []) -> Data {
        var data = Data()
        data.appendLittleEndian(UInt32(0))
        data.appendLittleEndian(UInt16(3))
        data.appendLittleEndian(code)
        data.appendLittleEndian(transactionID)
        parameters.forEach { data.appendLittleEndian($0) }
        data.replaceSubrange(0..<4, with: UInt32(data.count).littleEndianData)
        return data
    }
}

private extension UInt32 {
    var littleEndianData: Data {
        var littleEndian = self.littleEndian
        return Data(bytes: &littleEndian, count: MemoryLayout<UInt32>.size)
    }
}
