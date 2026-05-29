import Foundation

enum PTPDataPhasePolicy: String, Codable, Equatable {
    case noOutboundData
    case inboundDataExpected
}

enum ReadOnlyPTPCommand: String, Codable, CaseIterable, Equatable, Identifiable {
    case getDeviceInfo
    case getDevicePropDesc
    case getDevicePropValue

    var id: String { rawValue }

    var operationCode: UInt16 {
        switch self {
        case .getDeviceInfo:
            return 0x1001
        case .getDevicePropDesc:
            return 0x1014
        case .getDevicePropValue:
            return 0x1015
        }
    }
}

struct PTPAllowlistEntry: Codable, Equatable, Identifiable {
    var id: String { command.rawValue }
    var command: ReadOnlyPTPCommand
    var operationCode: UInt16 { command.operationCode }
    var readOnlyRationale: String
    var dataPhasePolicy: PTPDataPhasePolicy
    var expectedResponseHandling: String
    var unknownVendorOperationClassification: ProbeStatus

    init(
        command: ReadOnlyPTPCommand,
        readOnlyRationale: String,
        dataPhasePolicy: PTPDataPhasePolicy,
        expectedResponseHandling: String,
        unknownVendorOperationClassification: ProbeStatus
    ) {
        self.command = command
        self.readOnlyRationale = readOnlyRationale
        self.dataPhasePolicy = dataPhasePolicy
        self.expectedResponseHandling = expectedResponseHandling
        self.unknownVendorOperationClassification = unknownVendorOperationClassification
    }

    enum CodingKeys: String, CodingKey {
        case command
        case operationCode
        case readOnlyRationale
        case dataPhasePolicy
        case expectedResponseHandling
        case unknownVendorOperationClassification
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let command = try container.decode(ReadOnlyPTPCommand.self, forKey: .command)
        let decodedOperationCode = try container.decode(UInt16.self, forKey: .operationCode)
        guard decodedOperationCode == command.operationCode else {
            throw DecodingError.dataCorruptedError(
                forKey: .operationCode,
                in: container,
                debugDescription: "Operation code does not match the typed read-only PTP command."
            )
        }

        self.init(
            command: command,
            readOnlyRationale: try container.decode(String.self, forKey: .readOnlyRationale),
            dataPhasePolicy: try container.decode(PTPDataPhasePolicy.self, forKey: .dataPhasePolicy),
            expectedResponseHandling: try container.decode(String.self, forKey: .expectedResponseHandling),
            unknownVendorOperationClassification: try container.decode(ProbeStatus.self, forKey: .unknownVendorOperationClassification)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(command, forKey: .command)
        try container.encode(operationCode, forKey: .operationCode)
        try container.encode(readOnlyRationale, forKey: .readOnlyRationale)
        try container.encode(dataPhasePolicy, forKey: .dataPhasePolicy)
        try container.encode(expectedResponseHandling, forKey: .expectedResponseHandling)
        try container.encode(unknownVendorOperationClassification, forKey: .unknownVendorOperationClassification)
    }
}

struct PTPAllowlist: Equatable {
    private var entriesByCommand: [ReadOnlyPTPCommand: PTPAllowlistEntry]

    init(entries: [PTPAllowlistEntry] = PTPAllowlist.defaultEntries) {
        entriesByCommand = Dictionary(uniqueKeysWithValues: entries.map { ($0.command, $0) })
    }

    static let artifactPath = "PrismBladeLabs/GPhotoProbe/Resources/PTPReadOnlyAllowlist.json"

    static let defaultEntries: [PTPAllowlistEntry] = [
        PTPAllowlistEntry(
            command: .getDeviceInfo,
            readOnlyRationale: "Standard PTP device information read.",
            dataPhasePolicy: .inboundDataExpected,
            expectedResponseHandling: "Accept OK response with optional data payload; classify unsupported separately.",
            unknownVendorOperationClassification: .inconclusive
        ),
        PTPAllowlistEntry(
            command: .getDevicePropDesc,
            readOnlyRationale: "Standard PTP device property descriptor read.",
            dataPhasePolicy: .inboundDataExpected,
            expectedResponseHandling: "Accept OK response with property descriptor data; unsupported properties are inconclusive.",
            unknownVendorOperationClassification: .inconclusive
        ),
        PTPAllowlistEntry(
            command: .getDevicePropValue,
            readOnlyRationale: "Standard PTP device property value read.",
            dataPhasePolicy: .inboundDataExpected,
            expectedResponseHandling: "Accept OK response with property value data; unsupported properties are inconclusive.",
            unknownVendorOperationClassification: .inconclusive
        )
    ]

    func entry(for command: ReadOnlyPTPCommand) -> PTPAllowlistEntry? {
        entriesByCommand[command]
    }

    func validate(_ command: ReadOnlyPTPCommand) throws -> PTPAllowlistEntry {
        guard let entry = entry(for: command) else {
            throw ProbeSafetyError.unallowlistedPTPOperation(0)
        }
        return entry
    }

    func contains(operationCode: UInt16) -> Bool {
        entriesByCommand.values.contains { $0.operationCode == operationCode }
    }
}

struct PTPCommandPacket: Equatable {
    let command: ReadOnlyPTPCommand
    let operationCode: UInt16
    let transactionID: UInt32
    let parameters: [UInt32]

    fileprivate init(
        command: ReadOnlyPTPCommand,
        operationCode: UInt16,
        transactionID: UInt32,
        parameters: [UInt32]
    ) {
        self.command = command
        self.operationCode = operationCode
        self.transactionID = transactionID
        self.parameters = parameters
    }

    var encodedCommand: Data {
        var bytes = Data()
        bytes.appendLittleEndian(UInt32(0))
        bytes.appendLittleEndian(UInt16(1))
        bytes.appendLittleEndian(operationCode)
        bytes.appendLittleEndian(transactionID)
        parameters.forEach { bytes.appendLittleEndian($0) }
        let length = UInt32(bytes.count)
        bytes.replaceSubrange(0..<4, with: length.littleEndianData)
        return bytes
    }
}

struct PTPTransportResponse: Equatable {
    var responseContainer: Data
    var payloadData: Data
    var durationMilliseconds: Int
}

protocol PTPHardwareTransport {
    var canAcceptPTPCommands: Bool { get }
    func sendAllowlistedPTPCommand(_ packet: PTPCommandPacket) async throws -> PTPTransportResponse
}

enum PTPResponseDisposition: Equatable {
    case ok
    case unsupported
    case other(UInt16)
    case malformed
}

struct PTPResponseParser {
    static func disposition(for responseContainer: Data) -> PTPResponseDisposition {
        guard responseContainer.count >= 12,
              responseContainer.readLittleEndianUInt16(at: 4) == 3,
              let responseCode = responseContainer.readLittleEndianUInt16(at: 6) else {
            return .malformed
        }

        switch responseCode {
        case 0x2001:
            return .ok
        case 0x2005, 0x2006, 0x200A:
            return .unsupported
        default:
            return .other(responseCode)
        }
    }

    static func evidence(for responseContainer: Data) -> [String: String] {
        guard responseContainer.count >= 12,
              let responseCode = responseContainer.readLittleEndianUInt16(at: 6) else {
            return ["responseParse": "malformed"]
        }
        return [
            "responseCode": "0x\(String(responseCode, radix: 16, uppercase: true))",
            "responseContainerBytes": "\(responseContainer.count)"
        ]
    }
}

struct PTPProbeClient {
    private var allowlist: PTPAllowlist
    private var nextTransactionID: UInt32

    init(allowlist: PTPAllowlist = PTPAllowlist(), nextTransactionID: UInt32 = 1) {
        self.allowlist = allowlist
        self.nextTransactionID = nextTransactionID
    }

    mutating func makePacket(
        for command: ReadOnlyPTPCommand,
        parameters: [UInt32] = []
    ) throws -> PTPCommandPacket {
        let entry = try allowlist.validate(command)
        let packet = PTPCommandPacket(
            command: command,
            operationCode: entry.operationCode,
            transactionID: nextTransactionID,
            parameters: parameters
        )
        nextTransactionID += 1
        return packet
    }

    mutating func send(
        _ command: ReadOnlyPTPCommand,
        probeCommand: ProbeCommand = .abilities,
        parameters: [UInt32] = [],
        outData: Data? = nil,
        transport: PTPHardwareTransport
    ) async -> ProbeResult {
        guard transport.canAcceptPTPCommands else {
            return ProbeResult(
                command: probeCommand,
                status: .inconclusive,
                message: "PTP command capability is unavailable; user decision required.",
                failureLayer: .iOSAPI,
                requiresUserDecision: true,
                evidence: ["criticalPause": "true"]
            )
        }

        do {
            if outData != nil {
                throw ProbeSafetyError.outboundPTPDataForbidden(command)
            }
            let packet = try makePacket(for: command, parameters: parameters)
            let response = try await transport.sendAllowlistedPTPCommand(packet)
            var evidence = [
                "operationCode": "0x\(String(packet.operationCode, radix: 16, uppercase: true))",
                "ptpCommand": command.rawValue,
                "transactionID": "\(packet.transactionID)",
                "responseBytes": "\(response.responseContainer.count)",
                "payloadBytes": "\(response.payloadData.count)",
                "durationMilliseconds": "\(response.durationMilliseconds)"
            ]
            evidence.merge(PTPResponseParser.evidence(for: response.responseContainer)) { _, new in new }

            switch PTPResponseParser.disposition(for: response.responseContainer) {
            case .ok:
                return ProbeResult(
                    command: probeCommand,
                    status: .passed,
                    message: "PTP read-only round-trip completed.",
                    evidence: evidence
                )
            case .unsupported:
                return ProbeResult(
                    command: probeCommand,
                    status: .inconclusive,
                    message: "PTP read-only command is unsupported by the camera.",
                    failureLayer: .ptpResponse,
                    evidence: evidence
                )
            case .other(let responseCode):
                evidence["responseCode"] = "0x\(String(responseCode, radix: 16, uppercase: true))"
                return ProbeResult(
                    command: probeCommand,
                    status: .failed,
                    message: "PTP read-only command returned an error response.",
                    failureLayer: .ptpResponse,
                    evidence: evidence
                )
            case .malformed:
                return ProbeResult(
                    command: probeCommand,
                    status: .inconclusive,
                    message: "PTP response container was missing or malformed.",
                    failureLayer: .ptpResponse,
                    evidence: evidence
                )
            }
        } catch let error as ProbeSafetyError {
            return ProbeResult(
                command: probeCommand,
                status: .failed,
                message: error.localizedDescription,
                failureLayer: .safetyGate
            )
        } catch {
            return ProbeResult(
                command: probeCommand,
                status: .failed,
                message: error.localizedDescription,
                failureLayer: .ptpTransport
            )
        }
    }
}

private extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        append(value.littleEndianData)
    }

    func readLittleEndianUInt16(at offset: Int) -> UInt16? {
        guard count >= offset + MemoryLayout<UInt16>.size else { return nil }
        return withUnsafeBytes { buffer in
            UInt16(littleEndian: buffer.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
        }
    }
}

private extension FixedWidthInteger {
    var littleEndianData: Data {
        var value = littleEndian
        return Data(bytes: &value, count: MemoryLayout<Self>.size)
    }
}
