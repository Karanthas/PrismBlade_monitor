import XCTest
@testable import GPhotoProbe

final class PTPAllowlistTests: XCTestCase {
    func testDefaultAllowlistContainsOnlyExpectedReadOnlyOperations() throws {
        let allowlist = PTPAllowlist()

        let deviceInfo = try XCTUnwrap(allowlist.entry(for: .getDeviceInfo))
        XCTAssertEqual(deviceInfo.operationCode, 0x1001)
        XCTAssertEqual(deviceInfo.dataPhasePolicy, .inboundDataExpected)

        let propDesc = try XCTUnwrap(allowlist.entry(for: .getDevicePropDesc))
        XCTAssertEqual(propDesc.operationCode, 0x1014)

        let propValue = try XCTUnwrap(allowlist.entry(for: .getDevicePropValue))
        XCTAssertEqual(propValue.operationCode, 0x1015)

        XCTAssertFalse(allowlist.contains(operationCode: 0x9999))
    }

    func testPacketBuilderOnlyBuildsFromTypedAllowlistCommand() throws {
        var client = PTPProbeClient()
        let packet = try client.makePacket(for: .getDeviceInfo)

        XCTAssertEqual(packet.command, .getDeviceInfo)
        XCTAssertEqual(packet.operationCode, 0x1001)
        XCTAssertEqual(packet.transactionID, 1)
        XCTAssertFalse(packet.encodedCommand.isEmpty)
    }

    func testTransactionIDIncrementsDeterministically() throws {
        var client = PTPProbeClient()

        let first = try client.makePacket(for: .getDeviceInfo)
        let second = try client.makePacket(for: .getDevicePropDesc)

        XCTAssertEqual(first.transactionID, 1)
        XCTAssertEqual(second.transactionID, 2)
    }

    func testMissingPTPCapabilityTriggersCriticalPauseAndNoHardwareSend() async {
        var client = PTPProbeClient()
        let transport = SpyPTPTransport(canAcceptPTPCommands: false)

        let result = await client.send(.getDeviceInfo, transport: transport)

        XCTAssertEqual(result.status, .inconclusive)
        XCTAssertEqual(result.failureLayer, .iOSAPI)
        XCTAssertTrue(result.requiresUserDecision)
        XCTAssertEqual(transport.sendCallCount, 0)
    }

    func testAllowlistedCommandInvokesHardwareTransportOnce() async {
        var client = PTPProbeClient()
        let transport = SpyPTPTransport(canAcceptPTPCommands: true, responseCode: 0x2001)

        let result = await client.send(.getDeviceInfo, transport: transport)

        XCTAssertEqual(result.status, .passed)
        XCTAssertEqual(transport.sendCallCount, 1)
        XCTAssertEqual(transport.lastPacket?.operationCode, 0x1001)
    }

    func testOutboundDataIsRejectedBeforeHardwareSend() async {
        var client = PTPProbeClient()
        let transport = SpyPTPTransport(canAcceptPTPCommands: true, responseCode: 0x2001)

        let result = await client.send(.getDeviceInfo, outData: Data([0x01]), transport: transport)

        XCTAssertEqual(result.status, .failed)
        XCTAssertEqual(result.failureLayer, .safetyGate)
        XCTAssertEqual(transport.sendCallCount, 0)
    }

    func testUnsupportedPTPResponseIsInconclusive() async {
        var client = PTPProbeClient()
        let transport = SpyPTPTransport(canAcceptPTPCommands: true, responseCode: 0x2005)

        let result = await client.send(.getDeviceInfo, transport: transport)

        XCTAssertEqual(result.status, .inconclusive)
        XCTAssertEqual(result.failureLayer, .ptpResponse)
        XCTAssertEqual(result.evidence["responseCode"], "0x2005")
    }

    func testDetailedSendKeepsPayloadForFollowOnParsing() async {
        var client = PTPProbeClient()
        let payload = Data([0xAA, 0xBB])
        let transport = SpyPTPTransport(canAcceptPTPCommands: true, payloadData: payload)

        let outcome = await client.sendDetailed(.getDeviceInfo, transport: transport)

        XCTAssertEqual(outcome.result.status, .passed)
        XCTAssertEqual(outcome.response?.payloadData, payload)
        XCTAssertEqual(outcome.result.evidence["payloadBytes"], "2")
    }

    func testDeviceInfoParserExtractsSupportedPropertiesAndRedactsSerialEvidence() throws {
        let payload = Self.deviceInfoPayload(
            operations: [0x1001, 0x1014, 0x1015],
            events: [0x4002],
            properties: [0x5001, 0x5007, 0xD100]
        )

        let deviceInfo = try PTPDeviceInfoParser.parse(payload)

        XCTAssertEqual(deviceInfo.manufacturer, "Nikon")
        XCTAssertEqual(deviceInfo.model, "Z6_3")
        XCTAssertEqual(deviceInfo.devicePropertiesSupported, [0x5001, 0x5007, 0xD100])
        XCTAssertEqual(deviceInfo.probePropertyCodes(limit: 3), [0x5001, 0x5007, PTPDevicePropertyCatalog.nikonLiveViewSize])
        XCTAssertEqual(deviceInfo.probePropertyCodes(limit: 0), [])
        XCTAssertEqual(PTPDevicePropertyCatalog.name(for: PTPDevicePropertyCatalog.nikonLiveViewSize), "NikonLiveViewImageSize")
        XCTAssertEqual(PTPDevicePropertyCatalog.name(for: 0xD1B0), "NikonExposureDisplayStatus")
        XCTAssertEqual(deviceInfo.evidence["serialNumber"], "REDACTED")
        XCTAssertEqual(deviceInfo.evidence["supportedDeviceProperties"], "0x5001,0x5007,0xD100")
    }

    func testDevicePropDescParserExtractsEnumFormAndDisplayValues() throws {
        let payload = Self.devicePropDescPayload(
            propertyCode: 0x5007,
            dataType: 0x0004,
            access: 0x01,
            factoryDefault: .uint16(280),
            current: .uint16(560),
            form: .enumUInt16([280, 400, 560])
        )

        let desc = try PTPDevicePropDescParser.parse(payload, expectedPropertyCode: 0x5007)
        let evidence = desc.evidence(propertyCode: 0x5007)

        XCTAssertEqual(desc.propertyCode, 0x5007)
        XCTAssertEqual(desc.dataType, 0x0004)
        XCTAssertEqual(evidence["propertyDataTypeName"], "UInt16")
        XCTAssertEqual(evidence["propertyAccess"], "readWrite")
        XCTAssertEqual(evidence["currentDisplay"], "f/5.6")
        XCTAssertEqual(evidence["allowedValuesDisplay"], "f/2.8,f/4,f/5.6")
    }

    func testDevicePropDescParserExtractsRangeForm() throws {
        let payload = Self.devicePropDescPayload(
            propertyCode: 0x5001,
            dataType: 0x0002,
            access: 0x00,
            factoryDefault: .uint8(100),
            current: .uint8(87),
            form: .rangeUInt8(minimum: 0, maximum: 100, step: 1)
        )

        let desc = try PTPDevicePropDescParser.parse(payload, expectedPropertyCode: 0x5001)
        let evidence = desc.evidence(propertyCode: 0x5001)

        XCTAssertEqual(evidence["propertyAccess"], "readOnly")
        XCTAssertEqual(evidence["currentDisplay"], "87%")
        XCTAssertEqual(evidence["formKind"], "range")
        XCTAssertEqual(evidence["rangeMaximumDisplay"], "100%")
    }

    func testDevicePropValueParserUsesDescriptorTypeForDisplay() throws {
        var payload = Data()
        payload.appendLittleEndian(UInt16(560))

        let value = try PTPDevicePropValueParser.parse(payload, dataType: 0x0004, propertyCode: 0x5007)

        XCTAssertEqual(value.raw, "560")
        XCTAssertEqual(value.display, "f/5.6")
    }

    func testDevicePropValueParserDisplaysCommonStandardEnumsAndVendorValues() throws {
        XCTAssertEqual(
            try Self.parseUInt16Property(2, propertyCode: 0x5005).display,
            "Auto"
        )
        XCTAssertEqual(
            try Self.parseUInt16Property(0x8010, propertyCode: 0x500A).display,
            "Vendor(0x8010)"
        )
        XCTAssertEqual(
            try Self.parseUInt16Property(3, propertyCode: 0x500B).display,
            "Multi-spot"
        )
        XCTAssertEqual(
            try Self.parseUInt16Property(3, propertyCode: 0x500E).display,
            "Aperture priority"
        )
        XCTAssertEqual(
            try Self.parseUInt16Property(1, propertyCode: 0x5013).display,
            "Single shot"
        )
    }

    func testDevicePropValueParserDisplaysExposureTimeAndBias() throws {
        var exposureTime = Data()
        exposureTime.appendLittleEndian(UInt32(150_000))
        let exposureTimeValue = try PTPDevicePropValueParser.parse(
            exposureTime,
            dataType: 0x0006,
            propertyCode: 0x500D
        )

        var fractionalExposureTime = Data()
        fractionalExposureTime.appendLittleEndian(UInt32(5_000))
        let fractionalExposureTimeValue = try PTPDevicePropValueParser.parse(
            fractionalExposureTime,
            dataType: 0x0006,
            propertyCode: 0x500D
        )

        var exposureBias = Data()
        exposureBias.appendLittleEndian(Int16(333))
        let exposureBiasValue = try PTPDevicePropValueParser.parse(
            exposureBias,
            dataType: 0x0003,
            propertyCode: 0x5010
        )

        XCTAssertEqual(exposureTimeValue.display, "15 s")
        XCTAssertEqual(fractionalExposureTimeValue.display, "1/2 s")
        XCTAssertEqual(exposureBiasValue.display, "+0.333 EV")
    }

    func testBundledAllowlistMatchesRuntimeDefaults() throws {
        let bundleURL = try XCTUnwrap(Bundle(for: PTPAllowlistTests.self).url(forResource: "PTPReadOnlyAllowlist", withExtension: "json"))
        let data = try Data(contentsOf: bundleURL)
        let bundledEntries = try JSONDecoder().decode([PTPAllowlistEntry].self, from: data)

        XCTAssertEqual(bundledEntries, PTPAllowlist.defaultEntries)
    }

    func testDecodedAllowlistRejectsForgedOpcodeForTypedCommand() throws {
        let forgedJSON = """
        [
          {
            "command": "getDeviceInfo",
            "operationCode": 38911,
            "readOnlyRationale": "forged",
            "dataPhasePolicy": "inboundDataExpected",
            "expectedResponseHandling": "forged",
            "unknownVendorOperationClassification": "inconclusive"
          }
        ]
        """

        XCTAssertThrowsError(try JSONDecoder().decode([PTPAllowlistEntry].self, from: Data(forgedJSON.utf8)))
    }

    static func deviceInfoPayload(
        operations: [UInt16],
        events: [UInt16],
        properties: [UInt16]
    ) -> Data {
        var data = Data()
        data.appendLittleEndian(UInt16(100))
        data.appendLittleEndian(UInt32(0x0000000A))
        data.appendLittleEndian(UInt16(100))
        data.appendPTPString("Nikon extension")
        data.appendLittleEndian(UInt16(0))
        data.appendPTPUInt16Array(operations)
        data.appendPTPUInt16Array(events)
        data.appendPTPUInt16Array(properties)
        data.appendPTPUInt16Array([0x3801])
        data.appendPTPUInt16Array([0x3801, 0x3802])
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

    static func parseUInt16Property(_ rawValue: UInt16, propertyCode: UInt16) throws -> PTPPropertyValue {
        var payload = Data()
        payload.appendLittleEndian(rawValue)
        return try PTPDevicePropValueParser.parse(payload, dataType: 0x0004, propertyCode: propertyCode)
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

private final class SpyPTPTransport: PTPHardwareTransport {
    let canAcceptPTPCommands: Bool
    let responseCode: UInt16
    let payloadData: Data
    private(set) var sendCallCount = 0
    private(set) var lastPacket: PTPCommandPacket?

    init(canAcceptPTPCommands: Bool, responseCode: UInt16 = 0x2001, payloadData: Data = Data([0x00])) {
        self.canAcceptPTPCommands = canAcceptPTPCommands
        self.responseCode = responseCode
        self.payloadData = payloadData
    }

    func sendAllowlistedPTPCommand(_ packet: PTPCommandPacket) async throws -> PTPTransportResponse {
        sendCallCount += 1
        lastPacket = packet
        return PTPTransportResponse(
            responseContainer: Self.responseContainer(code: responseCode, transactionID: packet.transactionID),
            payloadData: payloadData,
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

    mutating func appendPTPUInt16Array(_ values: [UInt16]) {
        appendLittleEndian(UInt32(values.count))
        values.forEach { appendLittleEndian($0) }
    }

    mutating func appendPTPString(_ string: String) {
        let codeUnits = Array(string.utf16) + [0]
        append(UInt8(codeUnits.count))
        codeUnits.forEach { appendLittleEndian($0) }
    }

    mutating func appendPTPValue(_ value: PTPAllowlistTests.TestPTPValue) {
        switch value {
        case .uint8(let rawValue):
            append(rawValue)
        case .uint16(let rawValue):
            appendLittleEndian(rawValue)
        }
    }
}
