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

struct PTPProbeOutcome: Equatable {
    var result: ProbeResult
    var response: PTPTransportResponse?
}

struct PTPDeviceInfo: Equatable {
    var standardVersion: UInt16
    var vendorExtensionID: UInt32
    var vendorExtensionVersion: UInt16
    var vendorExtensionDescription: String
    var functionalMode: UInt16
    var operationsSupported: [UInt16]
    var eventsSupported: [UInt16]
    var devicePropertiesSupported: [UInt16]
    var captureFormats: [UInt16]
    var imageFormats: [UInt16]
    var manufacturer: String
    var model: String
    var deviceVersion: String
    var serialNumber: String

    var evidence: [String: String] {
        var evidence = [
            "standardVersion": "\(standardVersion)",
            "vendorExtensionID": PTPDeviceInfoParser.hex(vendorExtensionID),
            "vendorExtensionVersion": "\(vendorExtensionVersion)",
            "vendorExtensionDescription": vendorExtensionDescription,
            "functionalMode": PTPDeviceInfoParser.hex(functionalMode),
            "manufacturer": manufacturer,
            "model": model,
            "deviceVersion": deviceVersion,
            "supportedOperationCount": "\(operationsSupported.count)",
            "supportedEventCount": "\(eventsSupported.count)",
            "supportedDevicePropertyCount": "\(devicePropertiesSupported.count)",
            "captureFormatCount": "\(captureFormats.count)",
            "imageFormatCount": "\(imageFormats.count)",
            "supportedOperations": operationsSupported.map(PTPDeviceInfoParser.hex).joined(separator: ","),
            "supportedEvents": eventsSupported.map(PTPDeviceInfoParser.hex).joined(separator: ","),
            "supportedDeviceProperties": devicePropertiesSupported.map(PTPDeviceInfoParser.hex).joined(separator: ",")
        ]
        if !serialNumber.isEmpty {
            evidence["serialNumber"] = "REDACTED"
        }
        return evidence
    }

    func probePropertyCodes(limit: Int = 12) -> [UInt16] {
        guard limit > 0 else { return [] }

        let supported = Set(devicePropertiesSupported)
        let preferred = PTPDevicePropertyCatalog.preferredProbeOrder.filter(supported.contains)
        let remaining = devicePropertiesSupported.filter { !preferred.contains($0) }
        var propertyCodes = Array((preferred + remaining).prefix(limit))
        if isNikonPTPDevice, !propertyCodes.contains(PTPDevicePropertyCatalog.nikonLiveViewSize) {
            if propertyCodes.count < limit {
                propertyCodes.append(PTPDevicePropertyCatalog.nikonLiveViewSize)
            } else {
                propertyCodes[propertyCodes.count - 1] = PTPDevicePropertyCatalog.nikonLiveViewSize
            }
        }
        return propertyCodes
    }

    private var isNikonPTPDevice: Bool {
        manufacturer.localizedCaseInsensitiveContains("nikon") ||
            model.localizedCaseInsensitiveContains("nikon")
    }
}

enum PTPPayloadParseError: Error, Equatable, LocalizedError {
    case truncated(field: String, offset: Int)
    case unsupportedDataType(UInt16, field: String)

    var errorDescription: String? {
        switch self {
        case .truncated(let field, let offset):
            return "PTP payload ended while parsing \(field) at byte offset \(offset)."
        case .unsupportedDataType(let dataType, let field):
            return "Unsupported PTP property data type \(PTPDeviceInfoParser.hex(dataType)) while parsing \(field)."
        }
    }
}

enum PTPDeviceInfoParser {
    static func parse(_ data: Data) throws -> PTPDeviceInfo {
        var cursor = PTPPayloadCursor(data: data)
        return PTPDeviceInfo(
            standardVersion: try cursor.readUInt16(field: "standardVersion"),
            vendorExtensionID: try cursor.readUInt32(field: "vendorExtensionID"),
            vendorExtensionVersion: try cursor.readUInt16(field: "vendorExtensionVersion"),
            vendorExtensionDescription: try cursor.readString(field: "vendorExtensionDescription"),
            functionalMode: try cursor.readUInt16(field: "functionalMode"),
            operationsSupported: try cursor.readUInt16Array(field: "operationsSupported"),
            eventsSupported: try cursor.readUInt16Array(field: "eventsSupported"),
            devicePropertiesSupported: try cursor.readUInt16Array(field: "devicePropertiesSupported"),
            captureFormats: try cursor.readUInt16Array(field: "captureFormats"),
            imageFormats: try cursor.readUInt16Array(field: "imageFormats"),
            manufacturer: try cursor.readString(field: "manufacturer"),
            model: try cursor.readString(field: "model"),
            deviceVersion: try cursor.readString(field: "deviceVersion"),
            serialNumber: try cursor.readString(field: "serialNumber")
        )
    }

    static func hex(_ value: UInt16) -> String {
        "0x\(String(value, radix: 16, uppercase: true))"
    }

    static func hex(_ value: UInt32) -> String {
        "0x\(String(value, radix: 16, uppercase: true))"
    }
}

enum PTPDevicePropertyCatalog {
    static let nikonLiveViewSize: UInt16 = 0xD1AC

    static let preferredProbeOrder: [UInt16] = [
        0x5001, // BatteryLevel
        0x5005, // WhiteBalance
        0x5007, // FNumber
        0x500A, // FocusMode
        0x500B, // ExposureMeteringMode
        0x500D, // ExposureTime
        0x500E, // ExposureProgramMode
        0x500F, // ExposureIndex
        0x5010, // ExposureBiasCompensation
        0x5013, // StillCaptureMode
        0x501C  // FocusMeteringMode
    ]

    static func name(for code: UInt16) -> String {
        switch code {
        case 0x5001: return "BatteryLevel"
        case 0x5002: return "FunctionalMode"
        case 0x5003: return "ImageSize"
        case 0x5004: return "CompressionSetting"
        case 0x5005: return "WhiteBalance"
        case 0x5006: return "RGBGain"
        case 0x5007: return "FNumber"
        case 0x5008: return "FocalLength"
        case 0x5009: return "FocusDistance"
        case 0x500A: return "FocusMode"
        case 0x500B: return "ExposureMeteringMode"
        case 0x500C: return "FlashMode"
        case 0x500D: return "ExposureTime"
        case 0x500E: return "ExposureProgramMode"
        case 0x500F: return "ExposureIndex"
        case 0x5010: return "ExposureBiasCompensation"
        case 0x5011: return "DateTime"
        case 0x5012: return "CaptureDelay"
        case 0x5013: return "StillCaptureMode"
        case 0x5014: return "Contrast"
        case 0x5015: return "Sharpness"
        case 0x5016: return "DigitalZoom"
        case 0x5017: return "EffectMode"
        case 0x5018: return "BurstNumber"
        case 0x5019: return "BurstInterval"
        case 0x501A: return "TimelapseNumber"
        case 0x501B: return "TimelapseInterval"
        case 0x501C: return "FocusMeteringMode"
        case 0x501D: return "UploadURL"
        case 0x501E: return "Artist"
        case 0x501F: return "CopyrightInfo"
        case 0xD1AC: return "NikonLiveViewImageSize"
        case 0xD1B0: return "NikonExposureDisplayStatus"
        default:
            if code >= 0xD000 {
                return "VendorProperty"
            }
            return "UnknownProperty"
        }
    }
}

struct PTPPropertyValue: Equatable {
    var dataType: UInt16
    var raw: String
    var display: String
}

enum PTPDevicePropertyDataType {
    static func name(for dataType: UInt16) -> String {
        switch dataType {
        case 0x0000: return "Undefined"
        case 0x0001: return "Int8"
        case 0x0002: return "UInt8"
        case 0x0003: return "Int16"
        case 0x0004: return "UInt16"
        case 0x0005: return "Int32"
        case 0x0006: return "UInt32"
        case 0x0007: return "Int64"
        case 0x0008: return "UInt64"
        case 0x0009: return "Int128"
        case 0x000A: return "UInt128"
        case 0x4001: return "Int8Array"
        case 0x4002: return "UInt8Array"
        case 0x4003: return "Int16Array"
        case 0x4004: return "UInt16Array"
        case 0x4005: return "Int32Array"
        case 0x4006: return "UInt32Array"
        case 0x4007: return "Int64Array"
        case 0x4008: return "UInt64Array"
        case 0x4009: return "Int128Array"
        case 0x400A: return "UInt128Array"
        case 0xFFFF: return "String"
        default: return "Unknown"
        }
    }
}

enum PTPDevicePropertyAccess: String, Equatable {
    case readOnly
    case readWrite
    case unknown

    init(rawValue: UInt8) {
        switch rawValue {
        case 0x00:
            self = .readOnly
        case 0x01:
            self = .readWrite
        default:
            self = .unknown
        }
    }
}

enum PTPDevicePropertyForm: Equatable {
    case none
    case range(minimum: PTPPropertyValue, maximum: PTPPropertyValue, step: PTPPropertyValue)
    case enumeration([PTPPropertyValue])
    case unknown(UInt8)

    var kind: String {
        switch self {
        case .none:
            return "none"
        case .range:
            return "range"
        case .enumeration:
            return "enumeration"
        case .unknown:
            return "unknown"
        }
    }
}

struct PTPDevicePropDesc: Equatable {
    var propertyCode: UInt16
    var dataType: UInt16
    var access: PTPDevicePropertyAccess
    var factoryDefaultValue: PTPPropertyValue
    var currentValue: PTPPropertyValue
    var form: PTPDevicePropertyForm

    func evidence(propertyCode expectedPropertyCode: UInt16? = nil) -> [String: String] {
        var evidence = [
            "descriptorPropertyCode": PTPDeviceInfoParser.hex(propertyCode),
            "descriptorPropertyName": PTPDevicePropertyCatalog.name(for: propertyCode),
            "propertyDataType": PTPDeviceInfoParser.hex(dataType),
            "propertyDataTypeName": PTPDevicePropertyDataType.name(for: dataType),
            "propertyAccess": access.rawValue,
            "factoryDefaultRaw": factoryDefaultValue.raw,
            "factoryDefaultDisplay": factoryDefaultValue.display,
            "currentRaw": currentValue.raw,
            "currentDisplay": currentValue.display,
            "formKind": form.kind
        ]

        if let expectedPropertyCode {
            evidence["descriptorMatchesRequest"] = expectedPropertyCode == propertyCode ? "true" : "false"
        }

        switch form {
        case .none:
            break
        case .range(let minimum, let maximum, let step):
            evidence["rangeMinimumRaw"] = minimum.raw
            evidence["rangeMinimumDisplay"] = minimum.display
            evidence["rangeMaximumRaw"] = maximum.raw
            evidence["rangeMaximumDisplay"] = maximum.display
            evidence["rangeStepRaw"] = step.raw
            evidence["rangeStepDisplay"] = step.display
        case .enumeration(let values):
            evidence["allowedValueCount"] = "\(values.count)"
            evidence["allowedValuesRaw"] = Self.join(values.map(\.raw))
            evidence["allowedValuesDisplay"] = Self.join(values.map(\.display))
        case .unknown(let rawFormFlag):
            evidence["formFlag"] = PTPDeviceInfoParser.hex(UInt16(rawFormFlag))
        }

        return evidence
    }

    private static func join(_ values: [String], limit: Int = 40) -> String {
        let visibleValues = values.prefix(limit).joined(separator: ",")
        guard values.count > limit else { return visibleValues }
        return "\(visibleValues),...+\(values.count - limit)"
    }
}

enum PTPDevicePropDescParser {
    static func parse(_ data: Data, expectedPropertyCode: UInt16? = nil) throws -> PTPDevicePropDesc {
        var cursor = PTPPayloadCursor(data: data)
        let propertyCode = try cursor.readUInt16(field: "propertyCode")
        let dataType = try cursor.readUInt16(field: "dataType")
        let access = PTPDevicePropertyAccess(rawValue: try cursor.readUInt8(field: "getSet"))
        let factoryDefaultValue = try cursor.readPropertyValue(
            dataType: dataType,
            propertyCode: expectedPropertyCode ?? propertyCode,
            field: "factoryDefaultValue"
        )
        let currentValue = try cursor.readPropertyValue(
            dataType: dataType,
            propertyCode: expectedPropertyCode ?? propertyCode,
            field: "currentValue"
        )
        let formFlag = try cursor.readUInt8(field: "formFlag")
        let form: PTPDevicePropertyForm
        switch formFlag {
        case 0x00:
            form = .none
        case 0x01:
            form = .range(
                minimum: try cursor.readPropertyValue(dataType: dataType, propertyCode: propertyCode, field: "range.minimum"),
                maximum: try cursor.readPropertyValue(dataType: dataType, propertyCode: propertyCode, field: "range.maximum"),
                step: try cursor.readPropertyValue(dataType: dataType, propertyCode: propertyCode, field: "range.step")
            )
        case 0x02:
            let count = try cursor.readUInt16(field: "enumeration.count")
            var values: [PTPPropertyValue] = []
            values.reserveCapacity(Int(count))
            for index in 0..<count {
                values.append(
                    try cursor.readPropertyValue(
                        dataType: dataType,
                        propertyCode: propertyCode,
                        field: "enumeration[\(index)]"
                    )
                )
            }
            form = .enumeration(values)
        default:
            form = .unknown(formFlag)
        }

        return PTPDevicePropDesc(
            propertyCode: propertyCode,
            dataType: dataType,
            access: access,
            factoryDefaultValue: factoryDefaultValue,
            currentValue: currentValue,
            form: form
        )
    }
}

enum PTPDevicePropValueParser {
    static func parse(_ data: Data, dataType: UInt16, propertyCode: UInt16) throws -> PTPPropertyValue {
        var cursor = PTPPayloadCursor(data: data)
        return try cursor.readPropertyValue(dataType: dataType, propertyCode: propertyCode, field: "value")
    }
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
        await sendDetailed(
            command,
            probeCommand: probeCommand,
            parameters: parameters,
            outData: outData,
            transport: transport
        ).result
    }

    mutating func sendDetailed(
        _ command: ReadOnlyPTPCommand,
        probeCommand: ProbeCommand = .abilities,
        parameters: [UInt32] = [],
        outData: Data? = nil,
        transport: PTPHardwareTransport
    ) async -> PTPProbeOutcome {
        guard transport.canAcceptPTPCommands else {
            return PTPProbeOutcome(
                result: ProbeResult(
                    command: probeCommand,
                    status: .inconclusive,
                    message: "PTP command capability is unavailable; user decision required.",
                    failureLayer: .iOSAPI,
                    requiresUserDecision: true,
                    evidence: ["criticalPause": "true"]
                ),
                response: nil
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
            if let firstParameter = parameters.first {
                let propertyCode = UInt16(truncatingIfNeeded: firstParameter)
                evidence["parameter1"] = PTPDeviceInfoParser.hex(firstParameter)
                evidence["devicePropertyCode"] = PTPDeviceInfoParser.hex(propertyCode)
                evidence["devicePropertyName"] = PTPDevicePropertyCatalog.name(for: propertyCode)
            }
            evidence.merge(PTPResponseParser.evidence(for: response.responseContainer)) { _, new in new }

            switch PTPResponseParser.disposition(for: response.responseContainer) {
            case .ok:
                return PTPProbeOutcome(
                    result: ProbeResult(
                        command: probeCommand,
                        status: .passed,
                        message: "PTP read-only round-trip completed.",
                        evidence: evidence
                    ),
                    response: response
                )
            case .unsupported:
                return PTPProbeOutcome(
                    result: ProbeResult(
                        command: probeCommand,
                        status: .inconclusive,
                        message: "PTP read-only command is unsupported by the camera.",
                        failureLayer: .ptpResponse,
                        evidence: evidence
                    ),
                    response: response
                )
            case .other(let responseCode):
                evidence["responseCode"] = "0x\(String(responseCode, radix: 16, uppercase: true))"
                return PTPProbeOutcome(
                    result: ProbeResult(
                        command: probeCommand,
                        status: .failed,
                        message: "PTP read-only command returned an error response.",
                        failureLayer: .ptpResponse,
                        evidence: evidence
                    ),
                    response: response
                )
            case .malformed:
                return PTPProbeOutcome(
                    result: ProbeResult(
                        command: probeCommand,
                        status: .inconclusive,
                        message: "PTP response container was missing or malformed.",
                        failureLayer: .ptpResponse,
                        evidence: evidence
                    ),
                    response: response
                )
            }
        } catch let error as ProbeSafetyError {
            return PTPProbeOutcome(
                result: ProbeResult(
                    command: probeCommand,
                    status: .failed,
                    message: error.localizedDescription,
                    failureLayer: .safetyGate
                ),
                response: nil
            )
        } catch {
            return PTPProbeOutcome(
                result: ProbeResult(
                    command: probeCommand,
                    status: .failed,
                    message: error.localizedDescription,
                    failureLayer: .ptpTransport
                ),
                response: nil
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

    func readLittleEndianUInt32(at offset: Int) -> UInt32? {
        guard count >= offset + MemoryLayout<UInt32>.size else { return nil }
        return withUnsafeBytes { buffer in
            UInt32(littleEndian: buffer.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
        }
    }

    func readLittleEndianUInt64(at offset: Int) -> UInt64? {
        guard count >= offset + MemoryLayout<UInt64>.size else { return nil }
        return withUnsafeBytes { buffer in
            UInt64(littleEndian: buffer.loadUnaligned(fromByteOffset: offset, as: UInt64.self))
        }
    }
}

private extension FixedWidthInteger {
    var littleEndianData: Data {
        var value = littleEndian
        return Data(bytes: &value, count: MemoryLayout<Self>.size)
    }
}

private struct PTPPayloadCursor {
    private let data: Data
    private(set) var offset = 0

    init(data: Data) {
        self.data = data
    }

    mutating func readUInt16(field: String) throws -> UInt16 {
        guard let value = data.readLittleEndianUInt16(at: offset) else {
            throw PTPPayloadParseError.truncated(field: field, offset: offset)
        }
        offset += 2
        return value
    }

    mutating func readUInt8(field: String) throws -> UInt8 {
        guard offset < data.count else {
            throw PTPPayloadParseError.truncated(field: field, offset: offset)
        }
        let value = data[offset]
        offset += 1
        return value
    }

    mutating func readUInt32(field: String) throws -> UInt32 {
        guard let value = data.readLittleEndianUInt32(at: offset) else {
            throw PTPPayloadParseError.truncated(field: field, offset: offset)
        }
        offset += 4
        return value
    }

    mutating func readUInt64(field: String) throws -> UInt64 {
        guard let value = data.readLittleEndianUInt64(at: offset) else {
            throw PTPPayloadParseError.truncated(field: field, offset: offset)
        }
        offset += 8
        return value
    }

    mutating func readBytes(count: Int, field: String) throws -> Data {
        guard data.count >= offset + count else {
            throw PTPPayloadParseError.truncated(field: field, offset: offset)
        }
        let bytes = data.subdata(in: offset..<(offset + count))
        offset += count
        return bytes
    }

    mutating func readUInt16Array(field: String) throws -> [UInt16] {
        let count = try readUInt32(field: "\(field).count")
        let remainingValueCapacity = (data.count - offset) / 2
        guard count <= UInt32(remainingValueCapacity) else {
            throw PTPPayloadParseError.truncated(field: field, offset: offset)
        }
        var values: [UInt16] = []
        values.reserveCapacity(Int(count))
        for index in 0..<count {
            values.append(try readUInt16(field: "\(field)[\(index)]"))
        }
        return values
    }

    mutating func readString(field: String) throws -> String {
        guard offset < data.count else {
            throw PTPPayloadParseError.truncated(field: field, offset: offset)
        }

        let characterCount = Int(data[offset])
        offset += 1
        guard characterCount > 0 else { return "" }

        let byteCount = characterCount * 2
        guard data.count >= offset + byteCount else {
            throw PTPPayloadParseError.truncated(field: field, offset: offset)
        }

        let bytes = data.subdata(in: offset..<(offset + byteCount))
        offset += byteCount
        var codeUnits: [UInt16] = []
        codeUnits.reserveCapacity(characterCount)
        for characterIndex in 0..<characterCount {
            let byteOffset = characterIndex * 2
            guard let codeUnit = bytes.readLittleEndianUInt16(at: byteOffset) else {
                throw PTPPayloadParseError.truncated(field: field, offset: offset)
            }
            if codeUnit != 0 {
                codeUnits.append(codeUnit)
            }
        }
        return String(decoding: codeUnits, as: UTF16.self)
    }

    mutating func readPropertyValue(dataType: UInt16, propertyCode: UInt16, field: String) throws -> PTPPropertyValue {
        if dataType >= 0x4001 && dataType <= 0x400A {
            return try readArrayPropertyValue(dataType: dataType, propertyCode: propertyCode, field: field)
        }

        switch dataType {
        case 0x0001:
            let rawValue = Int8(bitPattern: try readUInt8(field: field))
            return propertyValue(dataType: dataType, propertyCode: propertyCode, signed: Int64(rawValue))
        case 0x0002:
            return propertyValue(dataType: dataType, propertyCode: propertyCode, unsigned: UInt64(try readUInt8(field: field)))
        case 0x0003:
            let rawValue = Int16(bitPattern: try readUInt16(field: field))
            return propertyValue(dataType: dataType, propertyCode: propertyCode, signed: Int64(rawValue))
        case 0x0004:
            return propertyValue(dataType: dataType, propertyCode: propertyCode, unsigned: UInt64(try readUInt16(field: field)))
        case 0x0005:
            let rawValue = Int32(bitPattern: try readUInt32(field: field))
            return propertyValue(dataType: dataType, propertyCode: propertyCode, signed: Int64(rawValue))
        case 0x0006:
            return propertyValue(dataType: dataType, propertyCode: propertyCode, unsigned: UInt64(try readUInt32(field: field)))
        case 0x0007:
            let rawValue = Int64(bitPattern: try readUInt64(field: field))
            return propertyValue(dataType: dataType, propertyCode: propertyCode, signed: rawValue)
        case 0x0008:
            return propertyValue(dataType: dataType, propertyCode: propertyCode, unsigned: try readUInt64(field: field))
        case 0x0009, 0x000A:
            let bytes = try readBytes(count: 16, field: field)
            let raw = hex(bytes)
            return PTPPropertyValue(dataType: dataType, raw: raw, display: raw)
        case 0xFFFF:
            let value = try readString(field: field)
            return PTPPropertyValue(dataType: dataType, raw: value, display: value)
        default:
            throw PTPPayloadParseError.unsupportedDataType(dataType, field: field)
        }
    }

    private mutating func readArrayPropertyValue(dataType: UInt16, propertyCode: UInt16, field: String) throws -> PTPPropertyValue {
        let count = try readUInt32(field: "\(field).count")
        let scalarDataType = dataType - 0x4000
        var values: [PTPPropertyValue] = []
        values.reserveCapacity(Int(min(count, 1024)))
        for index in 0..<count {
            values.append(
                try readPropertyValue(
                    dataType: scalarDataType,
                    propertyCode: propertyCode,
                    field: "\(field)[\(index)]"
                )
            )
        }
        let raw = values.map(\.raw).joined(separator: ",")
        let display = values.map(\.display).joined(separator: ",")
        return PTPPropertyValue(dataType: dataType, raw: "[\(raw)]", display: "[\(display)]")
    }

    private func propertyValue(
        dataType: UInt16,
        propertyCode: UInt16,
        signed: Int64? = nil,
        unsigned: UInt64? = nil
    ) -> PTPPropertyValue {
        let raw = signed.map(String.init) ?? unsigned.map(String.init) ?? ""
        let display = displayValue(propertyCode: propertyCode, signed: signed, unsigned: unsigned, fallback: raw)
        return PTPPropertyValue(dataType: dataType, raw: raw, display: display)
    }

    private func displayValue(
        propertyCode: UInt16,
        signed: Int64?,
        unsigned: UInt64?,
        fallback: String
    ) -> String {
        switch propertyCode {
        case 0x5001:
            guard let unsigned else { return fallback }
            return "\(unsigned)%"
        case 0x5005:
            guard let unsigned else { return fallback }
            return Self.mappedUnsignedValue(unsigned, names: [
                0x0001: "Manual",
                0x0002: "Auto",
                0x0003: "One-push auto",
                0x0004: "Daylight",
                0x0005: "Fluorescent",
                0x0006: "Tungsten",
                0x0007: "Flash"
            ])
        case 0x5007:
            guard let unsigned else { return fallback }
            return "f/\(Self.formatDecimal(Double(unsigned) / 100.0))"
        case 0x500A:
            guard let unsigned else { return fallback }
            return Self.mappedUnsignedValue(unsigned, names: [
                0x0001: "Manual",
                0x0002: "Auto",
                0x0003: "Auto macro"
            ])
        case 0x500B:
            guard let unsigned else { return fallback }
            return Self.mappedUnsignedValue(unsigned, names: [
                0x0001: "Average",
                0x0002: "Center-weighted average",
                0x0003: "Multi-spot",
                0x0004: "Multi-segment",
                0x0005: "Center spot"
            ])
        case 0x500D:
            guard let unsigned else { return fallback }
            return Self.exposureTimeDisplay(unsigned)
        case 0x500E:
            guard let unsigned else { return fallback }
            return Self.mappedUnsignedValue(unsigned, names: [
                0x0001: "Manual",
                0x0002: "Auto",
                0x0003: "Aperture priority",
                0x0004: "Shutter priority",
                0x0005: "Creative",
                0x0006: "Action",
                0x0007: "Portrait",
                0x0008: "Landscape"
            ])
        case 0x500F:
            guard let unsigned else { return fallback }
            return "ISO \(unsigned)"
        case 0x5010:
            if let signed {
                return Self.exposureBiasDisplay(signed)
            }
            guard let unsigned else { return fallback }
            return Self.exposureBiasDisplay(Int64(unsigned))
        case 0x5013:
            guard let unsigned else { return fallback }
            return Self.mappedUnsignedValue(unsigned, names: [
                0x0001: "Single shot",
                0x0002: "Burst",
                0x0003: "Timelapse"
            ])
        default:
            return fallback
        }
    }

    private static func mappedUnsignedValue(_ value: UInt64, names: [UInt64: String]) -> String {
        if let name = names[value] {
            return name
        }
        if value >= 0x8000 {
            return "Vendor(\(PTPDeviceInfoParser.hex(UInt32(truncatingIfNeeded: value))))"
        }
        return "\(value)"
    }

    private static func exposureTimeDisplay(_ rawValue: UInt64) -> String {
        guard rawValue > 0 else { return "0 s" }
        let seconds = Double(rawValue) / 10_000.0
        if seconds >= 1 {
            return "\(formatDecimal(seconds, maximumFractionDigits: 3)) s"
        }

        let denominator = 1.0 / seconds
        if denominator.rounded() == denominator {
            return "1/\(Int(denominator)) s"
        }
        return "\(formatDecimal(seconds, maximumFractionDigits: 4)) s"
    }

    private static func exposureBiasDisplay(_ rawValue: Int64) -> String {
        let ev = Double(rawValue) / 1_000.0
        let sign = ev > 0 ? "+" : ""
        return "\(sign)\(formatDecimal(ev, maximumFractionDigits: 3)) EV"
    }

    private static func formatDecimal(_ value: Double, maximumFractionDigits: Int = 1) -> String {
        let normalizedValue = abs(value) < 0.0005 ? 0 : value
        var text = String(format: "%.\(maximumFractionDigits)f", normalizedValue)
        while text.contains(".") && text.last == "0" {
            text.removeLast()
        }
        if text.last == "." {
            text.removeLast()
        }
        return text
    }

    private func hex(_ data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined()
    }
}
