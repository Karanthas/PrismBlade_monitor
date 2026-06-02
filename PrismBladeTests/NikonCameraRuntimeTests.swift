import XCTest
@testable import PrismBlade

final class NikonCameraRuntimeTests: XCTestCase {
    func testConnectReadsDescriptorsAndMapsCameraState() async throws {
        let ptp = ScriptedRuntimePTP(values: [.iso: 400, .exposureMode: 1, .shutter: 200, .aperture: 280, .whiteBalance: 4, .focusMode: 2])
        let runtime = makeRuntime(ptp: ptp)

        let state = try await runtime.connect()

        XCTAssertEqual(state.iso.current, "400")
        XCTAssertEqual(state.exposureMode.current, "M")
        XCTAssertEqual(state.shutter.current, "1/50")
        XCTAssertEqual(state.aperture.current, "f/2.8")
        XCTAssertEqual(state.whiteBalance.current, "5600K")
        XCTAssertEqual(state.focusMode.current, "AF-S")
        XCTAssertTrue(state.focusMode.isWritable)
        XCTAssertTrue(state.iso.isWritable)
    }

    func testApprovedWriteUsesSetDevicePropValueAndReadsBackState() async throws {
        let ptp = ScriptedRuntimePTP(values: [.iso: 400])
        let runtime = makeRuntime(ptp: ptp)
        _ = try await runtime.connect()

        let state = try await runtime.setValue("800", for: .iso)

        XCTAssertEqual(state.iso.current, "800")
        let writes = await ptp.writeSnapshot()
        XCTAssertEqual(writes.map(\.propertyCode), [0x500F])
        XCTAssertEqual(writes.map(\.encodedValue), [Data([0x20, 0x03])])
    }

    func testFocusModeWriteUsesApprovedPropertyAndReadback() async throws {
        let ptp = ScriptedRuntimePTP(values: [.focusMode: 2])
        let runtime = makeRuntime(ptp: ptp)
        _ = try await runtime.connect()

        let state = try await runtime.setValue("AF-C", for: .focusMode)

        XCTAssertEqual(state.focusMode.current, "AF-C")
        let writes = await ptp.writeSnapshot()
        XCTAssertEqual(writes.map(\.propertyCode), [0x500A])
        XCTAssertEqual(writes.map(\.encodedValue), [Data([0x03, 0x00])])
    }

    func testWriteReadbackMismatchFailsAfterCameraAcknowledgement() async throws {
        let ptp = ScriptedRuntimePTP(values: [.iso: 400], appliesWrites: false)
        let runtime = makeRuntime(ptp: ptp)
        _ = try await runtime.connect()

        do {
            _ = try await runtime.setValue("800", for: .iso)
            XCTFail("Stale readback should fail even when the write command returns OK.")
        } catch NikonCameraRuntimeError.readbackMismatch(let parameter, let expected, let actual) {
            XCTAssertEqual(parameter, .iso)
            XCTAssertEqual(expected, "800")
            XCTAssertEqual(actual, "400")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let writes = await ptp.writeSnapshot()
        XCTAssertEqual(writes.map(\.propertyCode), [0x500F])
    }

    func testDisconnectDuringWriteInvalidatesReadbackAndResetsPTPSession() async throws {
        let ptp = ScriptedRuntimePTP(values: [.iso: 400], blockWrites: true)
        let runtime = makeRuntime(ptp: ptp)
        _ = try await runtime.connect()

        let writeTask = Task {
            try await runtime.setValue("800", for: .iso)
        }
        try await waitUntil {
            await ptp.pendingWriteCount() == 1
        }

        await runtime.disconnect()
        await ptp.completePendingWrite()

        do {
            _ = try await writeTask.value
            XCTFail("A write interrupted by disconnect must not complete readback as connected.")
        } catch NikonCameraRuntimeError.notConnected {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let resetCount = await ptp.resetCount()
        XCTAssertEqual(resetCount, 1)
        let readValueCount = await ptp.readPropertyValueCount()
        XCTAssertEqual(readValueCount, CameraParameter.allCases.count + 1)
    }

    func testRangeDescriptorAllowsOnlyValuesInsideStepRangeBeforeWrite() async throws {
        let ptp = ScriptedRuntimePTP(
            values: [.iso: 400],
            rangeDescriptors: [.iso: RangeDescriptor(minimum: 100, maximum: 800, step: 100)]
        )
        let runtime = makeRuntime(ptp: ptp)
        _ = try await runtime.connect()

        let state = try await runtime.setValue("800", for: .iso)
        XCTAssertEqual(state.iso.current, "800")

        do {
            _ = try await runtime.setValue("1600", for: .iso)
            XCTFail("Out-of-range descriptor values should fail before write.")
        } catch CameraTransportError.unsupportedValue(let parameter, let value) {
            XCTAssertEqual(parameter, .iso)
            XCTAssertEqual(value, "1600")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let writes = await ptp.writeSnapshot()
        XCTAssertEqual(writes.map(\.encodedValue), [Data([0x20, 0x03])])
    }


    func testFailedConnectLeavesRuntimeDisconnected() async throws {
        let ptp = ScriptedRuntimePTP(values: [:], failingIntents: [.readDeviceInfo])
        let runtime = makeRuntime(ptp: ptp)

        do {
            _ = try await runtime.connect()
            XCTFail("Failed connect should throw.")
        } catch PTPClientError.responseError(let code, _) {
            XCTAssertEqual(code, .generalError)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        do {
            _ = try await runtime.currentState()
            XCTFail("Runtime should not remain connected after a connect failure.")
        } catch NikonCameraRuntimeError.notConnected {
            XCTAssertTrue(true)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testUnsupportedActionsSendNoPTPCommand() async throws {
        let ptp = ScriptedRuntimePTP(values: [:])
        let runtime = makeRuntime(ptp: ptp)
        _ = try await runtime.connect()

        do {
            _ = try await runtime.trigger(.focus)
            XCTFail("Focus action must stay unsupported until validated.")
        } catch NikonCameraRuntimeError.unsupportedAction(let action) {
            XCTAssertEqual(action, .focus)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let writes = await ptp.writeSnapshot()
        XCTAssertTrue(writes.isEmpty)
    }

    func testCameraTransportWrapsRuntimeStateAndWrites() async throws {
        let ptp = ScriptedRuntimePTP(values: [.iso: 400])
        let runtime = makeRuntime(ptp: ptp)
        let transport = NikonPTPCameraTransport(runtime: runtime)

        try await transport.connect()
        let state = try await transport.setValue("800", for: .iso)

        XCTAssertEqual(state.iso.current, "800")
        await transport.disconnect()
        do {
            _ = try await transport.currentState()
            XCTFail("Disconnected runtime should reject state reads.")
        } catch NikonCameraRuntimeError.notConnected {
            XCTAssertTrue(true)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testLiveViewSessionUsesStartFetchEndAndCleansOnce() async throws {
        let payload = Data([0x01, 0x02, 0x03])
        let ptp = ScriptedRuntimePTP(values: [:], liveViewPayloads: [payload])
        let runtime = makeRuntime(ptp: ptp)
        _ = try await runtime.connect()

        try await runtime.startLiveViewSession()
        let fetchedPayload = try await runtime.fetchLiveViewPayload()
        let firstCleanup = try await runtime.endLiveViewSession()
        let secondCleanup = try await runtime.endLiveViewSession()

        XCTAssertEqual(fetchedPayload, payload)
        XCTAssertTrue(firstCleanup)
        XCTAssertFalse(secondCleanup)
        let operations = await ptp.liveViewOperationSnapshot()
        XCTAssertEqual(operations, [.startLiveView, .getLiveViewImage, .endLiveView])
    }

    private func makeRuntime(ptp: ScriptedRuntimePTP) -> NikonCameraRuntime {
        let discovery = NikonCameraDiscoveryService(
            bridge: StaticNikonCameraDiscoveryBridge(descriptors: [
                NikonCameraDescriptor(
                    name: "NIKON Z 6_3",
                    manufacturer: "Nikon",
                    model: "Z 6_3",
                    serialNumber: nil,
                    authorization: .authorized,
                    capabilities: [.canAcceptPTPCommands]
                )
            ])
        )
        return NikonCameraRuntime(discovery: discovery, ptp: ptp)
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

private actor ScriptedRuntimePTP: NikonRuntimePTPSending {
    struct Write: Equatable {
        var propertyCode: UInt16
        var encodedValue: Data
    }

    private var values: [CameraParameter: UInt32]
    private let rangeDescriptors: [CameraParameter: RangeDescriptor]
    private var liveViewPayloads: [Data]
    private var writes: [Write] = []
    private var liveViewOperations: [NikonPTPOperation] = []
    private var pendingWriteContinuations: [CheckedContinuation<PTPClientResult, Error>] = []
    private var readValues = 0
    private var resets = 0
    private let failingIntents: [PTPCommandIntent]
    private let appliesWrites: Bool
    private let blockWrites: Bool
    private let mapper = NikonZ6IIIPropertyMapper()

    init(
        values: [CameraParameter: UInt32],
        rangeDescriptors: [CameraParameter: RangeDescriptor] = [:],
        liveViewPayloads: [Data] = [],
        failingIntents: [PTPCommandIntent] = [],
        appliesWrites: Bool = true,
        blockWrites: Bool = false
    ) {
        self.values = values
        self.rangeDescriptors = rangeDescriptors
        self.liveViewPayloads = liveViewPayloads
        self.failingIntents = failingIntents
        self.appliesWrites = appliesWrites
        self.blockWrites = blockWrites
    }

    func send(_ intent: PTPCommandIntent) async throws -> PTPClientResult {
        if failingIntents.contains(intent) {
            throw PTPClientError.responseError(code: .generalError, rawCode: PTPResponseCode.generalError.rawValue)
        }

        switch intent {
        case .readDeviceInfo:
            return result(for: intent, operation: .getDeviceInfo, payload: Data())
        case .readPropertyDescription(let propertyCode):
            let mapping = mapping(propertyCode: propertyCode)
            return result(for: intent, operation: .getDevicePropDesc, payload: descriptorPayload(mapping: mapping))
        case .readPropertyValue(let propertyCode):
            let mapping = mapping(propertyCode: propertyCode)
            readValues += 1
            let rawValue = values[mapping.parameter] ?? defaultRawValue(for: mapping.parameter)
            return result(
                for: intent,
                operation: .getDevicePropValue,
                payload: NikonPropertyDescriptorParser.encodeValue(rawValue, dataType: mapping.dataType)
            )
        case .writeImmediateControl(let parameter, let propertyCode, let encodedValue):
            writes.append(Write(propertyCode: propertyCode, encodedValue: encodedValue))
            if appliesWrites {
                values[parameter] = try NikonPropertyDescriptorParser.decodeValue(encodedValue, dataType: mapping(propertyCode: propertyCode).dataType)
            }
            if blockWrites {
                return try await withCheckedThrowingContinuation { continuation in
                    pendingWriteContinuations.append(continuation)
                }
            }
            return result(for: intent, operation: .setDevicePropValue, payload: Data())
        case .liveViewStart:
            liveViewOperations.append(.startLiveView)
            return result(for: intent, operation: .startLiveView, payload: Data())
        case .liveViewFrameFetch:
            liveViewOperations.append(.getLiveViewImage)
            return result(
                for: intent,
                operation: .getLiveViewImage,
                payload: liveViewPayloads.isEmpty ? Data() : liveViewPayloads.removeFirst()
            )
        case .liveViewEnd:
            liveViewOperations.append(.endLiveView)
            return result(for: intent, operation: .endLiveView, payload: Data())
        default:
            throw PTPOperationPolicyError.forbiddenOperation(.rawPTPBypass)
        }
    }

    func resetSessionAfterDisconnect() async {
        resets += 1
    }

    func writeSnapshot() -> [Write] {
        writes
    }

    func liveViewOperationSnapshot() -> [NikonPTPOperation] {
        liveViewOperations
    }

    func pendingWriteCount() -> Int {
        pendingWriteContinuations.count
    }

    func completePendingWrite() {
        guard !pendingWriteContinuations.isEmpty else { return }
        let continuation = pendingWriteContinuations.removeFirst()
        continuation.resume(returning: result(for: .writeImmediateControl(
            parameter: .iso,
            propertyCode: 0x500F,
            encodedValue: Data()
        ), operation: .setDevicePropValue, payload: Data()))
    }

    func readPropertyValueCount() -> Int {
        readValues
    }

    func resetCount() -> Int {
        resets
    }

    private func mapping(propertyCode: UInt16) -> NikonCameraPropertyMapping {
        for parameter in CameraParameter.allCases {
            if let mapping = mapper.mapping(for: parameter), mapping.propertyCode == propertyCode {
                return mapping
            }
        }
        fatalError("Unknown property code \(propertyCode)")
    }

    private func descriptorPayload(mapping: NikonCameraPropertyMapping) -> Data {
        let rawValues = mapping.rawToDisplay.keys.sorted()
        let defaultValue = defaultRawValue(for: mapping.parameter)
        let currentValue = values[mapping.parameter] ?? defaultValue
        var data = Data()
        data.appendLittleEndian(mapping.propertyCode)
        data.appendLittleEndian(mapping.dataType.rawValue)
        data.append(mapping.isWriteApproved ? 1 : 0)
        data.append(NikonPropertyDescriptorParser.encodeValue(defaultValue, dataType: mapping.dataType))
        data.append(NikonPropertyDescriptorParser.encodeValue(currentValue, dataType: mapping.dataType))
        if let range = rangeDescriptors[mapping.parameter] {
            data.append(1)
            data.append(NikonPropertyDescriptorParser.encodeValue(range.minimum, dataType: mapping.dataType))
            data.append(NikonPropertyDescriptorParser.encodeValue(range.maximum, dataType: mapping.dataType))
            data.append(NikonPropertyDescriptorParser.encodeValue(range.step, dataType: mapping.dataType))
            return data
        }
        data.append(2)
        data.appendLittleEndian(UInt16(rawValues.count))
        rawValues.forEach {
            data.append(NikonPropertyDescriptorParser.encodeValue($0, dataType: mapping.dataType))
        }
        return data
    }

    private func defaultRawValue(for parameter: CameraParameter) -> UInt32 {
        switch parameter {
        case .exposureMode:
            return 1
        case .iso:
            return 400
        case .shutter:
            return 200
        case .aperture:
            return 280
        case .whiteBalance:
            return 4
        case .focusMode:
            return 2
        }
    }

    private func result(for intent: PTPCommandIntent, operation: NikonPTPOperation, payload: Data) -> PTPClientResult {
        let request = PTPOperationRequest(
            operation: operation,
            parameters: [],
            dataPhase: payload.isEmpty ? .noData : .inboundDataExpected,
            outboundData: nil,
            diagnosticName: "test"
        )
        return PTPClientResult(
            request: request,
            operationCode: operation.rawValue,
            transactionID: 1,
            parameters: [],
            response: PTPParsedResponse(code: .ok, rawCode: PTPResponseCode.ok.rawValue, transactionID: 1, parameters: []),
            payloadData: payload
        )
    }
}

private struct RangeDescriptor: Equatable {
    var minimum: UInt32
    var maximum: UInt32
    var step: UInt32
}
