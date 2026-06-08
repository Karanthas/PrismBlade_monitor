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
        } catch NikonCameraRuntimeError.parameterWriteFailed(let diagnostic) {
            XCTAssertEqual(diagnostic.parameterName, CameraParameter.iso.rawValue)
            XCTAssertEqual(diagnostic.blockReason, .readbackMismatch)
            XCTAssertEqual(diagnostic.attemptedValue?.raw, "800")
            XCTAssertEqual(diagnostic.readbackValue?.display, "400")
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
        } catch NikonCameraRuntimeError.parameterWriteFailed(let diagnostic) {
            XCTAssertEqual(diagnostic.parameterName, CameraParameter.iso.rawValue)
            XCTAssertEqual(diagnostic.blockReason, .descriptorRangeRejected)
            XCTAssertEqual(diagnostic.attemptedValue?.raw, "1600")
            XCTAssertEqual(diagnostic.descriptor?.permittedRange?.maximum.raw, "800")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let writes = await ptp.writeSnapshot()
        XCTAssertEqual(writes.map(\.encodedValue), [Data([0x20, 0x03])])
    }

    func testReadOnlyDescriptorFailsBeforeWriteWithDiagnostic() async throws {
        let ptp = ScriptedRuntimePTP(values: [.iso: 400], readOnlyParameters: [.iso])
        let runtime = makeRuntime(ptp: ptp)
        _ = try await runtime.connect()

        do {
            _ = try await runtime.setValue("800", for: .iso)
            XCTFail("Read-only descriptor should block the write.")
        } catch NikonCameraRuntimeError.parameterWriteFailed(let diagnostic) {
            XCTAssertEqual(diagnostic.blockReason, .readOnlyDescriptor)
            XCTAssertEqual(diagnostic.propertyCode, NikonPTPDeviceProperty.exposureIndex)
            XCTAssertEqual(diagnostic.descriptor?.access, "readOnly")
            XCTAssertEqual(diagnostic.attemptedValue?.raw, "800")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let writes = await ptp.writeSnapshot()
        XCTAssertTrue(writes.isEmpty)
    }

    func testUnsupportedDisplayValueFailsBeforeWriteWithDiagnostic() async throws {
        let ptp = ScriptedRuntimePTP(values: [.iso: 400])
        let runtime = makeRuntime(ptp: ptp)
        _ = try await runtime.connect()

        do {
            _ = try await runtime.setValue("500", for: .iso)
            XCTFail("Unmapped display value should block before write.")
        } catch NikonCameraRuntimeError.parameterWriteFailed(let diagnostic) {
            XCTAssertEqual(diagnostic.blockReason, .unsupportedDisplayValue)
            XCTAssertEqual(diagnostic.attemptedValue?.raw, "500")
            XCTAssertEqual(diagnostic.attemptedValue?.display, "500")
            XCTAssertEqual(diagnostic.descriptor?.permittedValues.map(\.raw).contains("400"), true)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let writes = await ptp.writeSnapshot()
        XCTAssertTrue(writes.isEmpty)
    }

    func testPTPWriteResponseFailureIncludesResponseCodeDiagnostic() async throws {
        let failingIntent = PTPCommandIntent.writeImmediateControl(
            parameter: .iso,
            propertyCode: NikonPTPDeviceProperty.exposureIndex,
            encodedValue: Data([0x20, 0x03])
        )
        let ptp = ScriptedRuntimePTP(values: [.iso: 400], failingIntents: [failingIntent])
        let runtime = makeRuntime(ptp: ptp)
        _ = try await runtime.connect()

        do {
            _ = try await runtime.setValue("800", for: .iso)
            XCTFail("PTP response errors should be surfaced as write diagnostics.")
        } catch NikonCameraRuntimeError.parameterWriteFailed(let diagnostic) {
            XCTAssertEqual(diagnostic.blockReason, .ptpResponseError)
            XCTAssertEqual(diagnostic.responseCode, PTPResponseCode.generalError.rawValue)
            XCTAssertEqual(diagnostic.descriptor?.currentValue?.display, "400")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testSuccessfulWriteRecordsDiagnosticEvidenceWhenLogIsProvided() async throws {
        let diagnosticsLog = AppDiagnosticsLog()
        let ptp = ScriptedRuntimePTP(values: [.iso: 400])
        let runtime = makeRuntime(ptp: ptp, diagnosticsLog: diagnosticsLog)
        _ = try await runtime.connect()

        _ = try await runtime.setValue("800", for: .iso)

        let logText = diagnosticsLog.exportText()
        XCTAssertTrue(logText.contains(#""event":"camera.parameter.write.succeeded""#))
        XCTAssertTrue(logText.contains(#""blockReason":"applied""#))
        XCTAssertTrue(logText.contains(#""attempted.raw":"800""#))
        XCTAssertTrue(logText.contains(#""readback.display":"800""#))
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

    func testLiveViewSessionEvidenceClassifiesOnlyKnownDirectColorValues() async throws {
        let candidate = try XCTUnwrap(NikonPTPDeviceProperty.nLogCandidateCodes.first)
        let ptp = ScriptedRuntimePTP(
            values: [:],
            vendorProperties: [
                candidate.code: VendorPropertyDescriptor(
                    dataType: .unsignedInt16,
                    isWritable: false,
                    currentValue: 9,
                    permittedValues: [0, 9]
                )
            ]
        )
        let classifier = NikonColorEncodingClassifier(directMappings: [
            NikonColorEncodingClassifier.DirectMapping(
                propertyCode: candidate.code,
                rawValue: "9",
                encoding: .nLog,
                displayValue: "N-Log"
            )
        ])
        let runtime = makeRuntime(ptp: ptp, colorClassifier: classifier)
        _ = try await runtime.connect()

        let evidence = try await runtime.liveViewSessionEvidence()

        XCTAssertEqual(evidence.colorEncoding, .nLog)
        XCTAssertEqual(evidence.evidenceFields["colorEncoding"], "nLog")
        XCTAssertEqual(evidence.evidenceFields["colorObservation0.current.display"], "N-Log")
    }

    func testLiveViewSessionEvidenceLeavesUnknownColorValuesInconclusive() async throws {
        let candidate = try XCTUnwrap(NikonPTPDeviceProperty.nLogCandidateCodes.first)
        let ptp = ScriptedRuntimePTP(
            values: [:],
            vendorProperties: [
                candidate.code: VendorPropertyDescriptor(
                    dataType: .unsignedInt16,
                    isWritable: false,
                    currentValue: 77,
                    permittedValues: [77]
                )
            ]
        )
        let runtime = makeRuntime(ptp: ptp)
        _ = try await runtime.connect()

        let evidence = try await runtime.liveViewSessionEvidence()

        XCTAssertNil(evidence.colorEncoding)
        XCTAssertEqual(evidence.evidenceFields["colorEncoding"], "inconclusive")
        XCTAssertEqual(evidence.evidenceFields["colorObservation0.current.raw"], "77")
    }

    func testLiveViewSessionEvidenceReadsLiveViewSizeWithoutSelectingUnknownMapping() async throws {
        let ptp = ScriptedRuntimePTP(
            values: [:],
            vendorProperties: [
                NikonPTPDeviceProperty.liveViewSize: VendorPropertyDescriptor(
                    dataType: .unsignedInt16,
                    isWritable: true,
                    currentValue: 1,
                    permittedValues: [1, 2]
                )
            ]
        )
        let runtime = makeRuntime(ptp: ptp)
        _ = try await runtime.connect()

        let evidence = try await runtime.liveViewSessionEvidence()

        XCTAssertNil(evidence.selectedLiveViewSize)
        XCTAssertEqual(evidence.liveViewSizeEvidence.evidenceFields["liveViewSize.propertyCode"], "0xD1AC")
        XCTAssertEqual(evidence.liveViewSizeEvidence.evidenceFields["liveViewSizeReason"], "No preferred Nikon liveviewsize raw value is configured.")
        let writes = await ptp.writeSnapshot()
        XCTAssertTrue(writes.isEmpty)
    }

    func testLiveViewSessionEvidenceSelectsVerifiedLiveViewSizeAndReadsBack() async throws {
        let diagnosticsLog = AppDiagnosticsLog()
        let ptp = ScriptedRuntimePTP(
            values: [:],
            vendorProperties: [
                NikonPTPDeviceProperty.liveViewSize: VendorPropertyDescriptor(
                    dataType: .unsignedInt16,
                    isWritable: true,
                    currentValue: 1,
                    permittedValues: [1, 2, 3]
                )
            ]
        )
        let runtime = makeRuntime(
            ptp: ptp,
            liveViewSizeSelector: .nikonZ6IIILargestObservedLiveViewSize,
            diagnosticsLog: diagnosticsLog
        )
        _ = try await runtime.connect()

        let evidence = try await runtime.liveViewSessionEvidence()

        XCTAssertEqual(evidence.selectedLiveViewSize?.display, "1024x576")
        XCTAssertEqual(evidence.liveViewSizeEvidence.evidenceFields["liveViewSize.current.raw"], "3")
        XCTAssertEqual(evidence.liveViewSizeEvidence.evidenceFields["selectedLiveViewSize.raw"], "3")
        XCTAssertEqual(evidence.liveViewSizeEvidence.evidenceFields["liveViewSizeSourceIs1920x1080"], "false")
        let writes = await ptp.writeSnapshot()
        XCTAssertEqual(writes, [ScriptedRuntimePTP.Write(propertyCode: NikonPTPDeviceProperty.liveViewSize, encodedValue: Data([0x03, 0x00]))])
        let logText = diagnosticsLog.exportText()
        XCTAssertTrue(logText.contains(#""event":"camera.liveView.evidence""#))
        XCTAssertTrue(logText.contains(#""selectedLiveViewSize.raw":"3""#))
    }

    func testLiveViewSessionEvidenceReportsLiveViewSizeWriteRejectionSeparatelyFromReadFailures() async throws {
        let failingIntent = PTPCommandIntent.selectNikonLiveViewSize(
            propertyCode: NikonPTPDeviceProperty.liveViewSize,
            encodedValue: Data([0x02, 0x00])
        )
        let ptp = ScriptedRuntimePTP(
            values: [:],
            vendorProperties: [
                NikonPTPDeviceProperty.liveViewSize: VendorPropertyDescriptor(
                    dataType: .unsignedInt16,
                    isWritable: true,
                    currentValue: 1,
                    permittedValues: [1, 2]
                )
            ],
            failingIntents: [failingIntent]
        )
        let selector = NikonLiveViewSizeSelector(preferredValue: PropertyValueObservation(raw: "2", display: "640x360"))
        let runtime = makeRuntime(ptp: ptp, liveViewSizeSelector: selector)
        _ = try await runtime.connect()

        let evidence = try await runtime.liveViewSessionEvidence()

        XCTAssertNil(evidence.selectedLiveViewSize)
        XCTAssertEqual(evidence.liveViewSizeEvidence.evidenceFields["liveViewSize.propertyCode"], "0xD1AC")
        XCTAssertEqual(
            evidence.liveViewSizeEvidence.reason,
            "Nikon liveviewsize write of 640x360 raw 2 returned generalError (0x2002)."
        )
    }

    private func makeRuntime(
        ptp: ScriptedRuntimePTP,
        colorClassifier: NikonColorEncodingClassifier = NikonColorEncodingClassifier(),
        liveViewSizeSelector: NikonLiveViewSizeSelector = NikonLiveViewSizeSelector(),
        diagnosticsLog: AppDiagnosticsLog? = nil
    ) -> NikonCameraRuntime {
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
        return NikonCameraRuntime(
            discovery: discovery,
            ptp: ptp,
            colorClassifier: colorClassifier,
            liveViewSizeSelector: liveViewSizeSelector,
            diagnosticsLog: diagnosticsLog
        )
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
    private let readOnlyParameters: Set<CameraParameter>
    private var vendorProperties: [UInt16: VendorPropertyDescriptor]
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
        readOnlyParameters: Set<CameraParameter> = [],
        vendorProperties: [UInt16: VendorPropertyDescriptor] = [:],
        liveViewPayloads: [Data] = [],
        failingIntents: [PTPCommandIntent] = [],
        appliesWrites: Bool = true,
        blockWrites: Bool = false
    ) {
        self.values = values
        self.rangeDescriptors = rangeDescriptors
        self.readOnlyParameters = readOnlyParameters
        self.vendorProperties = vendorProperties
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
            if let vendorProperty = vendorProperties[propertyCode] {
                return result(for: intent, operation: .getDevicePropDesc, payload: descriptorPayload(propertyCode: propertyCode, descriptor: vendorProperty))
            }
            guard let mapping = mappingIfAvailable(propertyCode: propertyCode) else {
                throw PTPClientError.responseError(code: .operationNotSupported, rawCode: PTPResponseCode.operationNotSupported.rawValue)
            }
            return result(for: intent, operation: .getDevicePropDesc, payload: descriptorPayload(mapping: mapping))
        case .readPropertyValue(let propertyCode):
            if let vendorProperty = vendorProperties[propertyCode] {
                readValues += 1
                return result(
                    for: intent,
                    operation: .getDevicePropValue,
                    payload: NikonPropertyDescriptorParser.encodeValue(vendorProperty.currentValue, dataType: vendorProperty.dataType)
                )
            }
            guard let mapping = mappingIfAvailable(propertyCode: propertyCode) else {
                throw PTPClientError.responseError(code: .operationNotSupported, rawCode: PTPResponseCode.operationNotSupported.rawValue)
            }
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
        case .selectNikonLiveViewSize(let propertyCode, let encodedValue):
            writes.append(Write(propertyCode: propertyCode, encodedValue: encodedValue))
            guard var vendorProperty = vendorProperties[propertyCode] else {
                throw PTPClientError.responseError(code: .operationNotSupported, rawCode: PTPResponseCode.operationNotSupported.rawValue)
            }
            if appliesWrites {
                vendorProperty.currentValue = try NikonPropertyDescriptorParser.decodeValue(encodedValue, dataType: vendorProperty.dataType)
                vendorProperties[propertyCode] = vendorProperty
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
        guard let mapping = mappingIfAvailable(propertyCode: propertyCode) else {
            fatalError("Unknown property code \(propertyCode)")
        }
        return mapping
    }

    private func mappingIfAvailable(propertyCode: UInt16) -> NikonCameraPropertyMapping? {
        for parameter in CameraParameter.allCases {
            if let mapping = mapper.mapping(for: parameter), mapping.propertyCode == propertyCode {
                return mapping
            }
        }
        return nil
    }

    private func descriptorPayload(mapping: NikonCameraPropertyMapping) -> Data {
        let rawValues = mapping.rawToDisplay.keys.sorted()
        let defaultValue = defaultRawValue(for: mapping.parameter)
        let currentValue = values[mapping.parameter] ?? defaultValue
        var data = Data()
        data.appendLittleEndian(mapping.propertyCode)
        data.appendLittleEndian(mapping.dataType.rawValue)
        data.append(mapping.isWriteApproved && !readOnlyParameters.contains(mapping.parameter) ? 1 : 0)
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

    private func descriptorPayload(propertyCode: UInt16, descriptor: VendorPropertyDescriptor) -> Data {
        var data = Data()
        data.appendLittleEndian(propertyCode)
        data.appendLittleEndian(descriptor.dataType.rawValue)
        data.append(descriptor.isWritable ? 1 : 0)
        data.append(NikonPropertyDescriptorParser.encodeValue(descriptor.currentValue, dataType: descriptor.dataType))
        data.append(NikonPropertyDescriptorParser.encodeValue(descriptor.currentValue, dataType: descriptor.dataType))
        data.append(2)
        data.appendLittleEndian(UInt16(descriptor.permittedValues.count))
        descriptor.permittedValues.forEach {
            data.append(NikonPropertyDescriptorParser.encodeValue($0, dataType: descriptor.dataType))
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

private struct VendorPropertyDescriptor: Equatable {
    var dataType: PTPDevicePropertyDataType
    var isWritable: Bool
    var currentValue: UInt32
    var permittedValues: [UInt32]
}
