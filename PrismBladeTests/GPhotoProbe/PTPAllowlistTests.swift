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
}

private final class SpyPTPTransport: PTPHardwareTransport {
    let canAcceptPTPCommands: Bool
    let responseCode: UInt16
    private(set) var sendCallCount = 0
    private(set) var lastPacket: PTPCommandPacket?

    init(canAcceptPTPCommands: Bool, responseCode: UInt16 = 0x2001) {
        self.canAcceptPTPCommands = canAcceptPTPCommands
        self.responseCode = responseCode
    }

    func sendAllowlistedPTPCommand(_ packet: PTPCommandPacket) async throws -> PTPTransportResponse {
        sendCallCount += 1
        lastPacket = packet
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
