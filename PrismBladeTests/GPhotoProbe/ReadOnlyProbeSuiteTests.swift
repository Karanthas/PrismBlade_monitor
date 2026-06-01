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

    func testSuiteUsesParsedDeviceInfoToProbeSupportedProperties() async {
        let store = ProbeLogStore()
        let transport = SpyPTPTransport(
            canAcceptPTPCommands: true,
            deviceInfoPayload: Self.deviceInfoPayload(properties: [0x5001, 0x5007]),
            propDescPayloads: [
                0x5001: Self.devicePropDescPayload(
                    propertyCode: 0x5001,
                    dataType: 0x0002,
                    access: 0x00,
                    factoryDefault: .uint8(100),
                    current: .uint8(87),
                    form: .rangeUInt8(minimum: 0, maximum: 100, step: 1)
                ),
                0x5007: Self.devicePropDescPayload(
                    propertyCode: 0x5007,
                    dataType: 0x0004,
                    access: 0x01,
                    factoryDefault: .uint16(280),
                    current: .uint16(560),
                    form: .enumUInt16([280, 400, 560])
                )
            ],
            propValuePayloads: [
                0x5001: Self.propertyValuePayload(.uint8(87)),
                0x5007: Self.propertyValuePayload(.uint16(560))
            ]
        )
        let suite = ReadOnlyProbeSuite(
            discovery: FakeDiscoveryProbe(transport: transport),
            eventStatus: SpyEventStatusProbe(),
            videoPath: SpyVideoPathProbe()
        )

        let results = await suite.runReadOnlySuite(logStore: store)

        let propertyPackets = transport.sentPackets.filter { $0.command == .getDevicePropDesc || $0.command == .getDevicePropValue }
        XCTAssertEqual(propertyPackets.map(\.parameters), [[0x5001], [0x5001], [0x5007], [0x5007]])
        XCTAssertEqual(results.first { $0.command == .abilities }?.evidence["supportedDeviceProperties"], "0x5001,0x5007")
        XCTAssertTrue(results.contains { $0.evidence["devicePropertyName"] == "FNumber" })

        let fNumberDesc = results.first {
            $0.command == .listConfig && $0.evidence["devicePropertyName"] == "FNumber"
        }
        XCTAssertEqual(fNumberDesc?.evidence["currentDisplay"], "f/5.6")
        XCTAssertEqual(fNumberDesc?.evidence["allowedValueCount"], "3")
        XCTAssertEqual(fNumberDesc?.evidence["allowedValuesDisplay"], "f/2.8,f/4,f/5.6")

        let fNumberValue = results.first {
            $0.command == .getConfig && $0.evidence["devicePropertyName"] == "FNumber"
        }
        XCTAssertEqual(fNumberValue?.evidence["valueRaw"], "560")
        XCTAssertEqual(fNumberValue?.evidence["valueDisplay"], "f/5.6")
    }

    func testVideoPathProbeIsPresenceOnlyAndInconclusiveSafe() async {
        let result = await AVFoundationVideoPathProbe().checkPathExistence()

        XCTAssertEqual(result.command, .videoPathExistence)
        XCTAssertNotEqual(result.status, .failed)
    }

    static func deviceInfoPayload(properties: [UInt16]) -> Data {
        var data = Data()
        data.appendLittleEndian(UInt16(100))
        data.appendLittleEndian(UInt32(0x0000000A))
        data.appendLittleEndian(UInt16(100))
        data.appendPTPString("Nikon extension")
        data.appendLittleEndian(UInt16(0))
        data.appendPTPUInt16Array([0x1001, 0x1014, 0x1015])
        data.appendPTPUInt16Array([])
        data.appendPTPUInt16Array(properties)
        data.appendPTPUInt16Array([0x3801])
        data.appendPTPUInt16Array([0x3801])
        data.appendPTPString("Nikon")
        data.appendPTPString("Z6_3")
        data.appendPTPString("1.00")
        data.appendPTPString("SERIAL-1234")
        return data
    }

    static func devicePropDescPayload(
        propertyCode: UInt16,
        dataType: UInt16,
        access: UInt8,
        factoryDefault: TestPTPValue,
        current: TestPTPValue,
        form: TestPTPForm
    ) -> Data {
        var data = Data()
        data.appendLittleEndian(propertyCode)
        data.appendLittleEndian(dataType)
        data.append(access)
        data.appendPTPValue(factoryDefault)
        data.appendPTPValue(current)
        switch form {
        case .none:
            data.append(0x00)
        case .rangeUInt8(let minimum, let maximum, let step):
            data.append(0x01)
            data.appendPTPValue(.uint8(minimum))
            data.appendPTPValue(.uint8(maximum))
            data.appendPTPValue(.uint8(step))
        case .enumUInt16(let values):
            data.append(0x02)
            data.appendLittleEndian(UInt16(values.count))
            values.forEach { data.appendPTPValue(.uint16($0)) }
        }
        return data
    }

    static func propertyValuePayload(_ value: TestPTPValue) -> Data {
        var data = Data()
        data.appendPTPValue(value)
        return data
    }

    enum TestPTPValue {
        case uint8(UInt8)
        case uint16(UInt16)
    }

    enum TestPTPForm {
        case none
        case rangeUInt8(minimum: UInt8, maximum: UInt8, step: UInt8)
        case enumUInt16([UInt16])
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
    let deviceInfoPayload: Data
    let propDescPayloads: [UInt16: Data]
    let propValuePayloads: [UInt16: Data]
    private(set) var sendCallCount = 0
    private(set) var sentPackets: [PTPCommandPacket] = []

    init(
        canAcceptPTPCommands: Bool,
        responseCode: UInt16 = 0x2001,
        deviceInfoPayload: Data = Data([0x00]),
        propDescPayloads: [UInt16: Data] = [:],
        propValuePayloads: [UInt16: Data] = [:]
    ) {
        self.canAcceptPTPCommands = canAcceptPTPCommands
        self.responseCode = responseCode
        self.deviceInfoPayload = deviceInfoPayload
        self.propDescPayloads = propDescPayloads
        self.propValuePayloads = propValuePayloads
    }

    func sendAllowlistedPTPCommand(_ packet: PTPCommandPacket) async throws -> PTPTransportResponse {
        sendCallCount += 1
        sentPackets.append(packet)
        return PTPTransportResponse(
            responseContainer: Self.responseContainer(code: responseCode, transactionID: packet.transactionID),
            payloadData: payload(for: packet),
            durationMilliseconds: 3
        )
    }

    private func payload(for packet: PTPCommandPacket) -> Data {
        let propertyCode = packet.parameters.first.map(UInt16.init(truncatingIfNeeded:))
        switch packet.command {
        case .getDeviceInfo:
            return deviceInfoPayload
        case .getDevicePropDesc:
            return propertyCode.flatMap { propDescPayloads[$0] } ?? Data([0x00])
        case .getDevicePropValue:
            return propertyCode.flatMap { propValuePayloads[$0] } ?? Data([0x00])
        }
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

    mutating func appendPTPUInt16Array(_ values: [UInt16]) {
        appendLittleEndian(UInt32(values.count))
        values.forEach { appendLittleEndian($0) }
    }

    mutating func appendPTPString(_ string: String) {
        let codeUnits = Array(string.utf16) + [0]
        append(UInt8(codeUnits.count))
        codeUnits.forEach { appendLittleEndian($0) }
    }

    mutating func appendPTPValue(_ value: ReadOnlyProbeSuiteTests.TestPTPValue) {
        switch value {
        case .uint8(let rawValue):
            append(rawValue)
        case .uint16(let rawValue):
            appendLittleEndian(rawValue)
        }
    }
}
