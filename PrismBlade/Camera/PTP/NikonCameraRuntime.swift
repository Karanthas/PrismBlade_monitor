import Foundation

enum PTPDevicePropertyDataType: UInt16, Equatable {
    case unsignedInt8 = 0x0002
    case unsignedInt16 = 0x0004
    case unsignedInt32 = 0x0006

    var byteCount: Int {
        switch self {
        case .unsignedInt8:
            return 1
        case .unsignedInt16:
            return 2
        case .unsignedInt32:
            return 4
        }
    }
}

struct NikonPropertyDescriptor: Equatable {
    var propertyCode: UInt16
    var dataType: PTPDevicePropertyDataType
    var isWritable: Bool
    var currentValue: UInt32
    var permittedValues: [UInt32]
    var permittedRange: ClosedRange<UInt32>?
    var permittedStep: UInt32?

    func permits(_ rawValue: UInt32) -> Bool {
        if !permittedValues.isEmpty {
            return permittedValues.contains(rawValue)
        }

        if let permittedRange {
            guard permittedRange.contains(rawValue) else { return false }
            guard let permittedStep, permittedStep > 0 else { return true }
            return (rawValue - permittedRange.lowerBound).isMultiple(of: permittedStep)
        }

        return true
    }
}

enum NikonPropertyDescriptorParserError: Error, Equatable, LocalizedError {
    case unsupportedDataType(UInt16)
    case unsupportedForm(UInt8)
    case mismatchedPropertyCode(expected: UInt16, actual: UInt16)

    var errorDescription: String? {
        switch self {
        case .unsupportedDataType(let dataType):
            return "Unsupported PTP property data type \(PTPDiagnostics.hex(dataType))."
        case .unsupportedForm(let form):
            return "Unsupported PTP property descriptor form \(form)."
        case .mismatchedPropertyCode(let expected, let actual):
            return "Expected property \(PTPDiagnostics.hex(expected)) but received \(PTPDiagnostics.hex(actual))."
        }
    }
}

enum NikonPropertyDescriptorParser {
    static func parse(_ data: Data, expectedPropertyCode: UInt16) throws -> NikonPropertyDescriptor {
        var offset = 0
        let propertyCode = try data.readLittleEndianUInt16(at: offset)
        offset += 2
        guard propertyCode == expectedPropertyCode else {
            throw NikonPropertyDescriptorParserError.mismatchedPropertyCode(expected: expectedPropertyCode, actual: propertyCode)
        }

        let rawDataType = try data.readLittleEndianUInt16(at: offset)
        offset += 2
        guard let dataType = PTPDevicePropertyDataType(rawValue: rawDataType) else {
            throw NikonPropertyDescriptorParserError.unsupportedDataType(rawDataType)
        }

        let isWritable = try data.readUInt8(at: offset) != 0
        offset += 1
        _ = try readValue(from: data, dataType: dataType, offset: &offset)
        let currentValue = try readValue(from: data, dataType: dataType, offset: &offset)
        let form = try data.readUInt8(at: offset)
        offset += 1

        switch form {
        case 0:
            return NikonPropertyDescriptor(
                propertyCode: propertyCode,
                dataType: dataType,
                isWritable: isWritable,
                currentValue: currentValue,
                permittedValues: []
            )
        case 1:
            let minimum = try readValue(from: data, dataType: dataType, offset: &offset)
            let maximum = try readValue(from: data, dataType: dataType, offset: &offset)
            let step = try readValue(from: data, dataType: dataType, offset: &offset)
            return NikonPropertyDescriptor(
                propertyCode: propertyCode,
                dataType: dataType,
                isWritable: isWritable,
                currentValue: currentValue,
                permittedValues: [],
                permittedRange: minimum...maximum,
                permittedStep: step
            )
        case 2:
            let count = Int(try data.readLittleEndianUInt16(at: offset))
            offset += 2
            var values: [UInt32] = []
            for _ in 0..<count {
                values.append(try readValue(from: data, dataType: dataType, offset: &offset))
            }
            return NikonPropertyDescriptor(
                propertyCode: propertyCode,
                dataType: dataType,
                isWritable: isWritable,
                currentValue: currentValue,
                permittedValues: values
            )
        default:
            throw NikonPropertyDescriptorParserError.unsupportedForm(form)
        }
    }

    static func decodeValue(_ data: Data, dataType: PTPDevicePropertyDataType) throws -> UInt32 {
        var offset = 0
        return try readValue(from: data, dataType: dataType, offset: &offset)
    }

    static func encodeValue(_ value: UInt32, dataType: PTPDevicePropertyDataType) -> Data {
        var data = Data()
        switch dataType {
        case .unsignedInt8:
            data.append(UInt8(value & 0xFF))
        case .unsignedInt16:
            data.appendLittleEndian(UInt16(value & 0xFFFF))
        case .unsignedInt32:
            data.appendLittleEndian(value)
        }
        return data
    }

    private static func readValue(from data: Data, dataType: PTPDevicePropertyDataType, offset: inout Int) throws -> UInt32 {
        defer { offset += dataType.byteCount }
        switch dataType {
        case .unsignedInt8:
            return UInt32(try data.readUInt8(at: offset))
        case .unsignedInt16:
            return UInt32(try data.readLittleEndianUInt16(at: offset))
        case .unsignedInt32:
            return try data.readLittleEndianUInt32(at: offset)
        }
    }
}

struct NikonCameraPropertyMapping: Equatable {
    var parameter: CameraParameter
    var propertyCode: UInt16
    var dataType: PTPDevicePropertyDataType
    var rawToDisplay: [UInt32: String]
    var isWriteApproved: Bool

    func displayValue(for rawValue: UInt32) -> String {
        if let displayValue = rawToDisplay[rawValue] {
            return displayValue
        }

        switch parameter {
        case .iso:
            return "\(rawValue)"
        case .shutter:
            return Self.nikonExposureTimeDisplay(rawValue)
        case .aperture:
            return "f/\(Self.formatDecimal(Double(rawValue) / 100.0))"
        case .whiteBalance:
            return Self.whiteBalanceDisplay(rawValue)
        case .focusMode:
            return Self.focusModeDisplay(rawValue)
        case .exposureMode:
            return Self.exposureModeDisplay(rawValue)
        }
    }

    func rawValue(for displayValue: String) -> UInt32? {
        let normalizedValue = Self.normalized(displayValue)
        if let rawValue = rawToDisplay.first(where: { Self.normalized($0.value) == normalizedValue })?.key {
            return rawValue
        }

        switch parameter {
        case .iso:
            return Self.rawISO(from: displayValue)
        case .shutter:
            return Self.rawNikonExposureTime(from: displayValue)
        case .aperture:
            return Self.rawAperture(from: displayValue)
        case .whiteBalance:
            return Self.rawWhiteBalance(from: displayValue)
        case .focusMode:
            return Self.rawFocusMode(from: displayValue)
        case .exposureMode:
            return Self.rawExposureMode(from: displayValue)
        }
    }

    private static func rawISO(from displayValue: String) -> UInt32? {
        let trimmed = displayValue
            .replacingOccurrences(of: "ISO", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return UInt32(trimmed)
    }

    static func nikonExposureTimeRaw(numerator: UInt32, denominator: UInt32) -> UInt32 {
        (numerator << 16) | denominator
    }

    private static func rawNikonExposureTime(from displayValue: String) -> UInt32? {
        let trimmed = displayValue
            .replacingOccurrences(of: "sec", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "s", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        switch normalized(trimmed) {
        case "bulb":
            return 0xFFFFFFFF
        case "time":
            return 0xFFFFFFFD
        case "x 200", "x200":
            return 0xFFFFFFFE
        default:
            break
        }

        if trimmed.contains("/") {
            let parts = trimmed.split(separator: "/", maxSplits: 1).map(String.init)
            guard parts.count == 2,
                  let numerator = UInt32(parts[0].trimmingCharacters(in: .whitespacesAndNewlines)),
                  let denominator = UInt32(parts[1].trimmingCharacters(in: .whitespacesAndNewlines)),
                  numerator > 0,
                  denominator > 0,
                  numerator <= UInt32(UInt16.max),
                  denominator <= UInt32(UInt16.max) else {
                return nil
            }
            return nikonExposureTimeRaw(numerator: numerator, denominator: denominator)
        }

        guard let seconds = Double(trimmed), seconds > 0 else { return nil }
        if seconds.rounded() == seconds, seconds <= Double(UInt32.max >> 16) {
            return nikonExposureTimeRaw(numerator: UInt32(seconds), denominator: 1)
        }

        return closestNikonExposureTimeRaw(forSeconds: seconds)
    }

    private static func rawAperture(from displayValue: String) -> UInt32? {
        let trimmed = displayValue
            .replacingOccurrences(of: "f/", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let aperture = Double(trimmed), aperture >= 0 else { return nil }
        return UInt32((aperture * 100.0).rounded())
    }

    private static func rawWhiteBalance(from displayValue: String) -> UInt32? {
        switch normalized(displayValue) {
        case "auto":
            return 0x0002
        case "daylight", "sunny", "5600k":
            return 0x0004
        case "fluorescent", "4300k":
            return 0x0005
        case "tungsten", "incandescent", "3200k":
            return 0x0006
        case "flash", "6500k":
            return 0x0007
        default:
            return rawVendorValue(from: displayValue)
        }
    }

    private static func rawFocusMode(from displayValue: String) -> UInt32? {
        switch normalized(displayValue) {
        case "mf", "manual":
            return 0x0001
        case "auto", "automatic":
            return 0x0002
        case "auto macro", "automacro":
            return 0x0003
        case "af-s":
            return 0x8010
        case "af-c":
            return 0x8011
        case "af-a":
            return 0x8012
        case "af-f":
            return 0x8013
        default:
            return rawVendorValue(from: displayValue)
        }
    }

    private static func rawExposureMode(from displayValue: String) -> UInt32? {
        switch normalized(displayValue) {
        case "auto":
            return 0x0000
        case "m", "manual":
            return 0x0001
        case "p", "program", "normal program", "normalprogram":
            return 0x0002
        case "a", "aperture priority", "aperturepriority":
            return 0x0003
        case "s", "shutter priority", "shutterpriority":
            return 0x0004
        default:
            return rawVendorValue(from: displayValue)
        }
    }

    private static func whiteBalanceDisplay(_ rawValue: UInt32) -> String {
        switch rawValue {
        case 0x0001:
            return "Manual"
        case 0x0002:
            return "Auto"
        case 0x0003:
            return "One-push auto"
        case 0x0004:
            return "5600K"
        case 0x0005:
            return "4300K"
        case 0x0006:
            return "3200K"
        case 0x0007:
            return "6500K"
        default:
            return vendorOrRaw(rawValue)
        }
    }

    private static func focusModeDisplay(_ rawValue: UInt32) -> String {
        switch rawValue {
        case 0x0001:
            return "MF"
        case 0x0002:
            return "Auto"
        case 0x0003:
            return "Auto macro"
        case 0x8010:
            return "AF-S"
        case 0x8011:
            return "AF-C"
        case 0x8012:
            return "AF-A"
        case 0x8013:
            return "AF-F"
        default:
            return vendorOrRaw(rawValue)
        }
    }

    private static func exposureModeDisplay(_ rawValue: UInt32) -> String {
        switch rawValue {
        case 0x0000:
            return ExposureMode.auto.rawValue
        case 0x0001:
            return ExposureMode.manual.rawValue
        case 0x0002:
            return ExposureMode.program.rawValue
        case 0x0003:
            return ExposureMode.aperturePriority.rawValue
        case 0x0004:
            return ExposureMode.shutterPriority.rawValue
        case 0x0005:
            return "Creative"
        case 0x0006:
            return "Action"
        case 0x0007:
            return "Portrait"
        case 0x0008:
            return "Landscape"
        default:
            return vendorOrRaw(rawValue)
        }
    }

    private static func nikonExposureTimeDisplay(_ rawValue: UInt32) -> String {
        switch rawValue {
        case 0xFFFFFFFF:
            return "Bulb"
        case 0xFFFFFFFE:
            return "x 200"
        case 0xFFFFFFFD:
            return "Time"
        default:
            break
        }

        let numerator = rawValue >> 16
        let denominator = rawValue & 0xFFFF
        guard numerator > 0, denominator > 0 else { return "\(rawValue)" }
        if denominator == 1 {
            return "\(numerator) s"
        }
        return "\(numerator)/\(denominator)"
    }

    private static func closestNikonExposureTimeRaw(forSeconds seconds: Double) -> UInt32? {
        let denominators: [UInt32] = [
            2, 3, 4, 5, 6, 8, 10, 13, 15, 20, 24, 25, 30, 40, 48, 50, 60, 80,
            100, 120, 125, 160, 200, 240, 250, 320, 400, 500, 640, 800, 1_000,
            1_250, 1_600, 2_000, 2_500, 3_200, 4_000, 5_000, 6_400, 8_000
        ]
        for denominator in denominators {
            let numerator = (seconds * Double(denominator)).rounded()
            guard numerator > 0, numerator <= Double(UInt32.max >> 16) else { continue }
            let resolvedSeconds = numerator / Double(denominator)
            if abs(resolvedSeconds - seconds) < 0.000_001 {
                return nikonExposureTimeRaw(numerator: UInt32(numerator), denominator: denominator)
            }
        }
        return nil
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

    private static func rawVendorValue(from displayValue: String) -> UInt32? {
        let trimmed = displayValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("Vendor(0x"), trimmed.hasSuffix(")") {
            let start = trimmed.index(trimmed.startIndex, offsetBy: 9)
            let end = trimmed.index(before: trimmed.endIndex)
            return UInt32(trimmed[start..<end], radix: 16)
        }
        return UInt32(trimmed)
    }

    private static func vendorOrRaw(_ rawValue: UInt32) -> String {
        if rawValue >= 0x8000 {
            return "Vendor(\(PTPDiagnostics.hex(rawValue)))"
        }
        return "\(rawValue)"
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

struct NikonZ6IIIPropertyMapper {
    private let mappings: [CameraParameter: NikonCameraPropertyMapping]

    init(mappings: [CameraParameter: NikonCameraPropertyMapping] = Self.defaultMappings) {
        self.mappings = mappings
    }

    static let defaultShutterDisplays: [UInt32: String] = [
        NikonCameraPropertyMapping.nikonExposureTimeRaw(numerator: 1, denominator: 25): "1/25",
        NikonCameraPropertyMapping.nikonExposureTimeRaw(numerator: 1, denominator: 30): "1/30",
        NikonCameraPropertyMapping.nikonExposureTimeRaw(numerator: 1, denominator: 48): "1/48",
        NikonCameraPropertyMapping.nikonExposureTimeRaw(numerator: 1, denominator: 50): "1/50",
        NikonCameraPropertyMapping.nikonExposureTimeRaw(numerator: 1, denominator: 60): "1/60",
        NikonCameraPropertyMapping.nikonExposureTimeRaw(numerator: 1, denominator: 100): "1/100",
        NikonCameraPropertyMapping.nikonExposureTimeRaw(numerator: 1, denominator: 120): "1/120",
        NikonCameraPropertyMapping.nikonExposureTimeRaw(numerator: 1, denominator: 125): "1/125",
        NikonCameraPropertyMapping.nikonExposureTimeRaw(numerator: 1, denominator: 250): "1/250"
    ]

    static let defaultMappings: [CameraParameter: NikonCameraPropertyMapping] = [
        .exposureMode: NikonCameraPropertyMapping(
            parameter: .exposureMode,
            propertyCode: 0x500E,
            dataType: .unsignedInt16,
            rawToDisplay: [0: ExposureMode.auto.rawValue, 1: ExposureMode.manual.rawValue, 2: ExposureMode.program.rawValue, 3: ExposureMode.aperturePriority.rawValue, 4: ExposureMode.shutterPriority.rawValue],
            isWriteApproved: true
        ),
        .iso: NikonCameraPropertyMapping(
            parameter: .iso,
            propertyCode: 0x500F,
            dataType: .unsignedInt16,
            rawToDisplay: [100: "100", 200: "200", 400: "400", 800: "800", 1600: "1600", 3200: "3200", 6400: "6400"],
            isWriteApproved: true
        ),
        .shutter: NikonCameraPropertyMapping(
            parameter: .shutter,
            propertyCode: NikonPTPDeviceProperty.nikonExposureTime,
            dataType: .unsignedInt32,
            rawToDisplay: defaultShutterDisplays,
            isWriteApproved: true
        ),
        .aperture: NikonCameraPropertyMapping(
            parameter: .aperture,
            propertyCode: 0x5007,
            dataType: .unsignedInt16,
            rawToDisplay: [180: "f/1.8", 200: "f/2.0", 280: "f/2.8", 400: "f/4.0", 560: "f/5.6", 800: "f/8.0"],
            isWriteApproved: true
        ),
        .whiteBalance: NikonCameraPropertyMapping(
            parameter: .whiteBalance,
            propertyCode: 0x5005,
            dataType: .unsignedInt16,
            rawToDisplay: [2: "Auto", 4: "5600K", 5: "4300K", 6: "3200K", 7: "6500K"],
            isWriteApproved: true
        ),
        .focusMode: NikonCameraPropertyMapping(
            parameter: .focusMode,
            propertyCode: 0x500A,
            dataType: .unsignedInt16,
            rawToDisplay: [
                1: "MF",
                2: "Auto",
                3: "Auto macro",
                0x8010: "AF-S",
                0x8011: "AF-C",
                0x8012: "AF-A",
                0x8013: "AF-F"
            ],
            isWriteApproved: true
        )
    ]

    func mapping(for parameter: CameraParameter) -> NikonCameraPropertyMapping? {
        mappings[parameter]
    }

    func state(from descriptors: [CameraParameter: NikonPropertyDescriptor]) -> CameraState {
        CameraState(
            exposureMode: cameraValue(for: .exposureMode, descriptors: descriptors),
            iso: cameraValue(for: .iso, descriptors: descriptors),
            shutter: cameraValue(for: .shutter, descriptors: descriptors),
            aperture: cameraValue(for: .aperture, descriptors: descriptors),
            whiteBalance: cameraValue(for: .whiteBalance, descriptors: descriptors),
            focusMode: cameraValue(for: .focusMode, descriptors: descriptors),
            isRecording: false,
            batteryLevel: nil,
            storageRemaining: nil,
            lastActionStatus: nil
        )
    }

    func encodedWrite(parameter: CameraParameter, value: String, descriptor: NikonPropertyDescriptor) throws -> (propertyCode: UInt16, encodedValue: Data) {
        guard let mapping = mappings[parameter] else {
            throw NikonCameraRuntimeError.unsupportedParameter(parameter)
        }
        guard mapping.isWriteApproved else {
            throw NikonCameraRuntimeError.unsupportedParameter(parameter)
        }
        guard descriptor.isWritable else {
            throw NikonCameraRuntimeError.readOnlyParameter(parameter)
        }
        guard let rawValue = mapping.rawValue(for: value) else {
            throw CameraTransportError.unsupportedValue(parameter: parameter, value: value)
        }
        guard descriptor.permits(rawValue) else {
            throw CameraTransportError.unsupportedValue(parameter: parameter, value: value)
        }
        return (
            propertyCode: mapping.propertyCode,
            encodedValue: NikonPropertyDescriptorParser.encodeValue(rawValue, dataType: mapping.dataType)
        )
    }

    private func cameraValue(for parameter: CameraParameter, descriptors: [CameraParameter: NikonPropertyDescriptor]) -> CameraValue {
        guard let mapping = mappings[parameter] else {
            return CameraValue(current: "Unsupported", options: [], isWritable: false)
        }

        guard let descriptor = descriptors[parameter] else {
            return CameraValue(current: "--", options: [], isWritable: false)
        }

        let rawOptions = rawOptions(for: mapping, descriptor: descriptor)
        let options = rawOptions.map(mapping.displayValue)
        return CameraValue(
            current: mapping.displayValue(for: descriptor.currentValue),
            options: options,
            isWritable: descriptor.isWritable && mapping.isWriteApproved
        )
    }

    private func rawOptions(for mapping: NikonCameraPropertyMapping, descriptor: NikonPropertyDescriptor) -> [UInt32] {
        if !descriptor.permittedValues.isEmpty {
            return descriptor.permittedValues
        }

        if let permittedRange = descriptor.permittedRange {
            let rangedOptions = steppedValues(in: permittedRange, step: descriptor.permittedStep)
            if !rangedOptions.isEmpty, rangedOptions.count <= 80 {
                return rangedOptions
            }
            return mapping.rawToDisplay.keys
                .filter { descriptor.permits($0) && permittedRange.contains($0) }
                .sorted()
        }

        return mapping.rawToDisplay.keys.sorted()
    }

    private func steppedValues(in range: ClosedRange<UInt32>, step: UInt32?) -> [UInt32] {
        let resolvedStep = max(step ?? 1, 1)
        var values: [UInt32] = []
        var value = range.lowerBound
        while value <= range.upperBound, values.count <= 80 {
            values.append(value)
            guard UInt32.max - value >= resolvedStep else { break }
            value += resolvedStep
        }
        return values
    }
}

enum NikonCameraRuntimeError: Error, Equatable, LocalizedError {
    case notConnected
    case liveViewNotActive
    case unsupportedParameter(CameraParameter)
    case readOnlyParameter(CameraParameter)
    case unsupportedAction(CameraAction)
    case readbackMismatch(parameter: CameraParameter, expected: String, actual: String)
    case parameterWriteFailed(CameraParameterWriteDiagnostic)
    case parameterWriteReadbackMismatch(CameraParameterWriteDiagnostic, CameraState)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Nikon camera runtime is not connected."
        case .liveViewNotActive:
            return "Nikon live view has not been started."
        case .unsupportedParameter(let parameter):
            return "\(parameter.title) is not supported by the Nikon runtime yet."
        case .readOnlyParameter(let parameter):
            return "\(parameter.title) is read-only on the selected camera."
        case .unsupportedAction(let action):
            return "Camera action \(action) is disabled for the real Nikon runtime."
        case .readbackMismatch(let parameter, let expected, let actual):
            return "\(parameter.title) readback mismatch after write: expected \(expected), got \(actual)."
        case .parameterWriteFailed(let diagnostic):
            return diagnostic.userMessage
        case .parameterWriteReadbackMismatch(let diagnostic, _):
            return diagnostic.userMessage
        }
    }
}

private extension PTPClientError {
    var shouldAbortParameterSnapshot: Bool {
        switch self {
        case .responseError:
            return false
        case .missingPTPCapability, .timeout, .timedOutOperationStillInFlight, .transactionMismatch:
            return true
        }
    }
}

protocol NikonLiveViewRuntime {
    func liveViewSessionEvidence() async throws -> NikonLiveViewSessionEvidence
    func startLiveViewSession() async throws
    func fetchLiveViewPayload() async throws -> Data
    func endLiveViewSession() async throws -> Bool
}

extension NikonLiveViewRuntime {
    func liveViewSessionEvidence() async throws -> NikonLiveViewSessionEvidence {
        NikonLiveViewSessionEvidence.inconclusive
    }
}

actor NikonCameraRuntime {
    private let discovery: NikonCameraDiscoveryService
    private let ptp: NikonRuntimePTPSending
    private let mapper: NikonZ6IIIPropertyMapper
    private let colorClassifier: NikonColorEncodingClassifier
    private let liveViewSizeSelector: NikonLiveViewSizeSelector
    private let diagnosticsLog: AppDiagnosticsLog?
    private var selectedCamera: NikonCameraDescriptor?
    private var isConnected = false
    private var isLiveViewActive = false
    private var connectionGeneration = 0

    init(
        discovery: NikonCameraDiscoveryService,
        ptp: NikonRuntimePTPSending,
        mapper: NikonZ6IIIPropertyMapper = NikonZ6IIIPropertyMapper(),
        colorClassifier: NikonColorEncodingClassifier = NikonColorEncodingClassifier(),
        liveViewSizeSelector: NikonLiveViewSizeSelector = NikonLiveViewSizeSelector(),
        diagnosticsLog: AppDiagnosticsLog? = nil
    ) {
        self.discovery = discovery
        self.ptp = ptp
        self.mapper = mapper
        self.colorClassifier = colorClassifier
        self.liveViewSizeSelector = liveViewSizeSelector
        self.diagnosticsLog = diagnosticsLog
    }

    func connect() async throws -> CameraState {
        connectionGeneration += 1
        let generation = connectionGeneration
        isConnected = false
        isLiveViewActive = false
        selectedCamera = nil

        let camera = try await discovery.discoverSupportedCamera()
        try assertCurrentGeneration(generation)
        selectedCamera = camera
        isConnected = true

        do {
            _ = try await ptp.send(.readDeviceInfo)
            try assertConnected(generation)
            return try await currentState(generation: generation)
        } catch {
            if connectionGeneration == generation {
                isConnected = false
                isLiveViewActive = false
                selectedCamera = nil
                await ptp.resetSessionAfterDisconnect()
            }
            throw error
        }
    }

    func disconnect() async {
        connectionGeneration += 1
        isConnected = false
        isLiveViewActive = false
        selectedCamera = nil
        await ptp.resetSessionAfterDisconnect()
    }

    func reconnect() async throws -> CameraState {
        await disconnect()
        return try await connect()
    }

    func currentState() async throws -> CameraState {
        let generation = try activeConnectionGeneration()
        return try await currentState(generation: generation)
    }

    func setValue(_ value: String, for parameter: CameraParameter) async throws -> CameraState {
        let generation = try activeConnectionGeneration()
        guard let mapping = mapper.mapping(for: parameter) else {
            let diagnostic = writeDiagnostic(
                parameter: parameter,
                value: value,
                mapping: nil,
                descriptor: nil,
                responseCode: nil,
                readbackValue: nil,
                blockReason: .unsupportedMapping
            )
            recordWriteDiagnostic(diagnostic, event: "camera.parameter.write.failed")
            throw NikonCameraRuntimeError.parameterWriteFailed(diagnostic)
        }

        let descriptor: NikonPropertyDescriptor
        do {
            descriptor = try await readDescriptor(mapping: mapping, generation: generation)
        } catch let error as PTPClientError {
            let diagnostic = writeDiagnostic(
                parameter: parameter,
                value: value,
                mapping: mapping,
                descriptor: nil,
                responseCode: responseCode(from: error),
                readbackValue: nil,
                blockReason: .ptpResponseError
            )
            recordWriteDiagnostic(diagnostic, event: "camera.parameter.write.failed")
            throw NikonCameraRuntimeError.parameterWriteFailed(diagnostic)
        }

        let write: (propertyCode: UInt16, encodedValue: Data)
        do {
            write = try mapper.encodedWrite(parameter: parameter, value: value, descriptor: descriptor)
        } catch {
            let diagnostic = writeDiagnostic(
                parameter: parameter,
                value: value,
                mapping: mapping,
                descriptor: descriptor,
                responseCode: nil,
                readbackValue: nil,
                blockReason: writeBlockReason(parameter: parameter, value: value, mapping: mapping, descriptor: descriptor)
            )
            recordWriteDiagnostic(diagnostic, event: "camera.parameter.write.failed")
            throw NikonCameraRuntimeError.parameterWriteFailed(diagnostic)
        }

        try assertConnected(generation)
        do {
            _ = try await ptp.send(.writeImmediateControl(
                parameter: parameter,
                propertyCode: write.propertyCode,
                encodedValue: write.encodedValue
            ))
        } catch let error as PTPClientError {
            let diagnostic = writeDiagnostic(
                parameter: parameter,
                value: value,
                mapping: mapping,
                descriptor: descriptor,
                responseCode: responseCode(from: error),
                readbackValue: nil,
                blockReason: .ptpResponseError
            )
            recordWriteDiagnostic(diagnostic, event: "camera.parameter.write.failed")
            throw NikonCameraRuntimeError.parameterWriteFailed(diagnostic)
        }
        try assertConnected(generation)
        let updatedState = try await currentState(generation: generation)
        let readbackValue = cameraValue(for: parameter, in: updatedState).current
        guard readbackValue == value else {
            let diagnostic = writeDiagnostic(
                parameter: parameter,
                value: value,
                mapping: mapping,
                descriptor: descriptor,
                responseCode: PTPResponseCode.ok.rawValue,
                readbackValue: readbackValue,
                blockReason: .readbackMismatch
            )
            recordWriteDiagnostic(diagnostic, event: "camera.parameter.write.readbackMismatch")
            throw NikonCameraRuntimeError.parameterWriteReadbackMismatch(diagnostic, updatedState)
        }
        let diagnostic = writeDiagnostic(
            parameter: parameter,
            value: value,
            mapping: mapping,
            descriptor: descriptor,
            responseCode: PTPResponseCode.ok.rawValue,
            readbackValue: readbackValue,
            blockReason: .applied
        )
        recordWriteDiagnostic(diagnostic, event: "camera.parameter.write.succeeded")
        return updatedState
    }

    func trigger(_ action: CameraAction) async throws -> CameraState {
        throw NikonCameraRuntimeError.unsupportedAction(action)
    }

    func liveViewSessionEvidence() async throws -> NikonLiveViewSessionEvidence {
        let generation = try activeConnectionGeneration()
        let observations = try await readColorEncodingObservations(generation: generation)
        let colorEvidence = colorClassifier.classify(observations)
        let liveViewSizeEvidence = try await readLiveViewSizeEvidence(generation: generation)
        let evidence = NikonLiveViewSessionEvidence(
            colorEncoding: colorEvidence.sourceColorEncoding,
            colorEvidence: colorEvidence,
            liveViewSizeEvidence: liveViewSizeEvidence,
            selectedLiveViewSize: liveViewSizeEvidence.selectedValue,
            decodedFrameSize: nil
        )
        diagnosticsLog?.record("camera.liveView.evidence", fields: evidence.evidenceFields)
        return evidence
    }

    func startLiveViewSession() async throws {
        let generation = try activeConnectionGeneration()
        guard !isLiveViewActive else { return }

        _ = try await ptp.send(.liveViewStart)
        try assertConnected(generation)
        isLiveViewActive = true
    }

    func fetchLiveViewPayload() async throws -> Data {
        let generation = try activeConnectionGeneration()
        guard isLiveViewActive else { throw NikonCameraRuntimeError.liveViewNotActive }

        let payload = try await ptp.send(.liveViewFrameFetch).payloadData
        try assertConnected(generation)
        return payload
    }

    func endLiveViewSession() async throws -> Bool {
        let generation = try activeConnectionGeneration()
        guard isLiveViewActive else { return false }

        isLiveViewActive = false
        _ = try await ptp.send(.liveViewEnd)
        try assertConnected(generation)
        return true
    }

    private func currentState(generation: Int) async throws -> CameraState {
        let descriptors = try await readDescriptors(generation: generation)
        return mapper.state(from: descriptors)
    }

    private func readColorEncodingObservations(generation: Int) async throws -> [PropertyObservation] {
        var observations: [PropertyObservation] = []
        for candidate in NikonPTPDeviceProperty.nLogCandidateCodes {
            do {
                if let observation = try await readPropertyObservation(candidate: candidate, generation: generation) {
                    observations.append(observation)
                }
            } catch PTPClientError.responseError(let code, let rawCode) {
                observations.append(PropertyObservation(
                    code: candidate.code,
                    name: candidate.name,
                    access: "unknown",
                    currentValue: nil,
                    permittedValues: [],
                    permittedRange: nil,
                    reason: "Candidate property read returned \(code) (\(PTPDiagnostics.hex(rawCode)))."
                ))
            } catch NikonCameraRuntimeError.notConnected {
                throw NikonCameraRuntimeError.notConnected
            } catch {
                observations.append(PropertyObservation(
                    code: candidate.code,
                    name: candidate.name,
                    access: "unknown",
                    currentValue: nil,
                    permittedValues: [],
                    permittedRange: nil,
                    reason: "Candidate property read failed: \(error.localizedDescription)"
                ))
            }
        }
        return observations
    }

    private func readLiveViewSizeEvidence(generation: Int) async throws -> NikonLiveViewSizeEvidence {
        let candidate = NamedPTPPropertyCode(
            code: NikonPTPDeviceProperty.liveViewSize,
            name: NikonPTPDeviceProperty.name(for: NikonPTPDeviceProperty.liveViewSize)
        )
        let descriptor: NikonPropertyDescriptor
        do {
            guard let parsedDescriptor = try await readPropertyDescriptor(candidate: candidate, generation: generation) else {
                return NikonLiveViewSizeEvidence(
                    observation: nil,
                    selectedValue: nil,
                    decodedFrameSize: nil,
                    sourceIs1920x1080: false,
                    reason: "Nikon liveviewsize descriptor could not be parsed."
                )
            }
            descriptor = parsedDescriptor
        } catch PTPClientError.responseError(let code, let rawCode) {
            return NikonLiveViewSizeEvidence(
                observation: nil,
                selectedValue: nil,
                decodedFrameSize: nil,
                sourceIs1920x1080: false,
                reason: "Nikon liveviewsize descriptor/value read returned \(code) (\(PTPDiagnostics.hex(rawCode)))."
            )
        } catch NikonCameraRuntimeError.notConnected {
            throw NikonCameraRuntimeError.notConnected
        }

        let beforeSelection = propertyObservation(candidate: candidate, descriptor: descriptor)
        switch liveViewSizeSelector.validatedTarget(for: descriptor) {
        case .notSelected(let reason):
            return NikonLiveViewSizeEvidence(
                observation: beforeSelection,
                selectedValue: nil,
                decodedFrameSize: nil,
                sourceIs1920x1080: false,
                reason: reason
            )
        case .select(let rawValue, let value):
            let encodedValue = NikonPropertyDescriptorParser.encodeValue(rawValue, dataType: descriptor.dataType)
            do {
                _ = try await ptp.send(.selectNikonLiveViewSize(
                    propertyCode: NikonPTPDeviceProperty.liveViewSize,
                    encodedValue: encodedValue
                ))
                try assertConnected(generation)
            } catch PTPClientError.responseError(let code, let rawCode) {
                return NikonLiveViewSizeEvidence(
                    observation: beforeSelection,
                    selectedValue: nil,
                    decodedFrameSize: nil,
                    sourceIs1920x1080: false,
                    reason: "Nikon liveviewsize write of \(value.display) raw \(rawValue) returned \(code) (\(PTPDiagnostics.hex(rawCode)))."
                )
            } catch NikonCameraRuntimeError.notConnected {
                throw NikonCameraRuntimeError.notConnected
            }

            let readbackResult: PTPClientResult
            do {
                readbackResult = try await ptp.send(.readPropertyValue(NikonPTPDeviceProperty.liveViewSize))
                try assertConnected(generation)
            } catch PTPClientError.responseError(let code, let rawCode) {
                return NikonLiveViewSizeEvidence(
                    observation: beforeSelection,
                    selectedValue: nil,
                    decodedFrameSize: nil,
                    sourceIs1920x1080: false,
                    reason: "Nikon liveviewsize readback after writing \(value.display) raw \(rawValue) returned \(code) (\(PTPDiagnostics.hex(rawCode)))."
                )
            } catch NikonCameraRuntimeError.notConnected {
                throw NikonCameraRuntimeError.notConnected
            }

            let readbackRawValue = try NikonPropertyDescriptorParser.decodeValue(
                readbackResult.payloadData,
                dataType: descriptor.dataType
            )
            guard readbackRawValue == rawValue else {
                return NikonLiveViewSizeEvidence(
                    observation: beforeSelection,
                    selectedValue: nil,
                    decodedFrameSize: nil,
                    sourceIs1920x1080: false,
                    reason: "Nikon liveviewsize readback \(readbackRawValue) did not match selected value \(rawValue)."
                )
            }
            var readbackDescriptor = descriptor
            readbackDescriptor.currentValue = readbackRawValue
            return NikonLiveViewSizeEvidence(
                observation: propertyObservation(candidate: candidate, descriptor: readbackDescriptor),
                selectedValue: value,
                decodedFrameSize: nil,
                sourceIs1920x1080: false,
                reason: "Nikon liveviewsize \(value.display) selected and read back; decoded frame dimensions determine whether the source is 1920x1080."
            )
        }
    }

    private func readPropertyObservation(candidate: NamedPTPPropertyCode, generation: Int) async throws -> PropertyObservation? {
        guard let descriptor = try await readPropertyDescriptor(candidate: candidate, generation: generation) else {
            return PropertyObservation(
                code: candidate.code,
                name: candidate.name,
                access: "unknown",
                currentValue: nil,
                permittedValues: [],
                permittedRange: nil,
                reason: "Candidate property descriptor could not be parsed."
            )
        }
        return propertyObservation(candidate: candidate, descriptor: descriptor)
    }

    private func readPropertyDescriptor(candidate: NamedPTPPropertyCode, generation: Int) async throws -> NikonPropertyDescriptor? {
        try assertConnected(generation)
        let descriptorResult = try await ptp.send(.readPropertyDescription(candidate.code))
        try assertConnected(generation)
        guard var descriptor = try? NikonPropertyDescriptorParser.parse(
            descriptorResult.payloadData,
            expectedPropertyCode: candidate.code
        ) else {
            return nil
        }

        let valueResult = try await ptp.send(.readPropertyValue(candidate.code))
        try assertConnected(generation)
        if let rawValue = try? NikonPropertyDescriptorParser.decodeValue(valueResult.payloadData, dataType: descriptor.dataType) {
            descriptor.currentValue = rawValue
        }
        return descriptor
    }

    private func propertyObservation(candidate: NamedPTPPropertyCode, descriptor: NikonPropertyDescriptor) -> PropertyObservation {
        PropertyObservation(
            code: descriptor.propertyCode,
            name: candidate.name,
            access: descriptor.isWritable ? "readWrite" : "readOnly",
            currentValue: PropertyValueObservation(
                raw: "\(descriptor.currentValue)",
                display: "\(descriptor.currentValue)"
            ),
            permittedValues: descriptor.permittedValues.map {
                PropertyValueObservation(raw: "\($0)", display: "\($0)")
            },
            permittedRange: propertyRangeObservation(from: descriptor),
            reason: "Read during live-view session evidence startup."
        )
    }

    private func propertyRangeObservation(from descriptor: NikonPropertyDescriptor) -> PropertyValueRangeObservation? {
        guard let range = descriptor.permittedRange else { return nil }
        let step = descriptor.permittedStep ?? 0
        return PropertyValueRangeObservation(
            minimum: PropertyValueObservation(raw: "\(range.lowerBound)", display: "\(range.lowerBound)"),
            maximum: PropertyValueObservation(raw: "\(range.upperBound)", display: "\(range.upperBound)"),
            step: PropertyValueObservation(raw: "\(step)", display: "\(step)")
        )
    }

    private func writeDiagnostic(
        parameter: CameraParameter,
        value: String,
        mapping: NikonCameraPropertyMapping?,
        descriptor: NikonPropertyDescriptor?,
        responseCode: UInt16?,
        readbackValue: String?,
        blockReason: CameraParameterWriteBlockReason
    ) -> CameraParameterWriteDiagnostic {
        let rawAttempt = mapping?.rawValue(for: value)
        return CameraParameterWriteDiagnostic(
            parameterName: parameter.rawValue,
            propertyCode: mapping?.propertyCode,
            descriptor: writeDescriptorObservation(mapping: mapping, descriptor: descriptor),
            attemptedValue: PropertyValueObservation(raw: rawAttempt.map(String.init) ?? value, display: value),
            responseCode: responseCode,
            readbackValue: readbackValue.map { readbackDisplay in
                PropertyValueObservation(raw: rawReadbackValue(for: readbackDisplay, mapping: mapping), display: readbackDisplay)
            },
            blockReason: blockReason,
            userMessage: userMessage(parameter: parameter, value: value, blockReason: blockReason)
        )
    }

    private func writeDescriptorObservation(
        mapping: NikonCameraPropertyMapping?,
        descriptor: NikonPropertyDescriptor?
    ) -> PropertyObservation? {
        guard let mapping, let descriptor else { return nil }
        return PropertyObservation(
            code: descriptor.propertyCode,
            name: NikonPTPDeviceProperty.name(for: descriptor.propertyCode),
            access: descriptor.isWritable ? "readWrite" : "readOnly",
            currentValue: PropertyValueObservation(
                raw: "\(descriptor.currentValue)",
                display: mapping.displayValue(for: descriptor.currentValue)
            ),
            permittedValues: descriptor.permittedValues.map {
                PropertyValueObservation(raw: "\($0)", display: mapping.displayValue(for: $0))
            },
            permittedRange: writeRangeObservation(from: descriptor, mapping: mapping),
            reason: "Descriptor read before parameter write."
        )
    }

    private func writeRangeObservation(
        from descriptor: NikonPropertyDescriptor,
        mapping: NikonCameraPropertyMapping
    ) -> PropertyValueRangeObservation? {
        guard let range = descriptor.permittedRange else { return nil }
        let step = descriptor.permittedStep ?? 0
        return PropertyValueRangeObservation(
            minimum: PropertyValueObservation(raw: "\(range.lowerBound)", display: mapping.displayValue(for: range.lowerBound)),
            maximum: PropertyValueObservation(raw: "\(range.upperBound)", display: mapping.displayValue(for: range.upperBound)),
            step: PropertyValueObservation(raw: "\(step)", display: "\(step)")
        )
    }

    private func writeBlockReason(
        parameter: CameraParameter,
        value: String,
        mapping: NikonCameraPropertyMapping,
        descriptor: NikonPropertyDescriptor
    ) -> CameraParameterWriteBlockReason {
        guard mapper.mapping(for: parameter) != nil, mapping.isWriteApproved else {
            return .unsupportedMapping
        }
        guard descriptor.isWritable else {
            return .readOnlyDescriptor
        }
        guard let rawValue = mapping.rawValue(for: value) else {
            return .unsupportedDisplayValue
        }
        guard descriptor.permits(rawValue) else {
            return descriptor.permittedRange == nil ? .unsupportedRawValue : .descriptorRangeRejected
        }
        return .ptpResponseError
    }

    private func rawReadbackValue(for displayValue: String, mapping: NikonCameraPropertyMapping?) -> String {
        guard let mapping, let rawValue = mapping.rawValue(for: displayValue) else {
            return displayValue
        }
        return "\(rawValue)"
    }

    private func userMessage(
        parameter: CameraParameter,
        value: String,
        blockReason: CameraParameterWriteBlockReason
    ) -> String {
        switch blockReason {
        case .applied:
            return "\(parameter.title) 已写入 \(value)"
        case .unsupportedMapping:
            return "\(parameter.title) 当前没有可验证的相机写入映射。"
        case .readOnlyDescriptor:
            return "\(parameter.title) 当前由相机报告为不可写。"
        case .unsupportedDisplayValue:
            return "\(parameter.title) 不支持 \(value)。"
        case .unsupportedRawValue:
            return "\(parameter.title) 的相机能力表不包含 \(value)。"
        case .descriptorRangeRejected:
            return "\(parameter.title) 超出相机报告的可写范围。"
        case .ptpResponseError:
            return "\(parameter.title) 写入被相机拒绝。"
        case .modeLock:
            return "\(parameter.title) 当前被曝光模式锁定。"
        case .readbackMismatch:
            return "\(parameter.title) 已由相机接受，但当前值由机身状态决定。"
        }
    }

    private func responseCode(from error: PTPClientError) -> UInt16? {
        guard case .responseError(_, let rawCode) = error else { return nil }
        return rawCode
    }

    private func recordWriteDiagnostic(_ diagnostic: CameraParameterWriteDiagnostic, event: String) {
        diagnosticsLog?.record(event, fields: diagnostic.evidenceFields)
    }

    private func readDescriptors(generation: Int) async throws -> [CameraParameter: NikonPropertyDescriptor] {
        var descriptors: [CameraParameter: NikonPropertyDescriptor] = [:]
        for parameter in CameraParameter.allCases {
            guard let mapping = mapper.mapping(for: parameter) else { continue }
            do {
                descriptors[parameter] = try await readDescriptor(mapping: mapping, generation: generation)
            } catch NikonCameraRuntimeError.notConnected {
                throw NikonCameraRuntimeError.notConnected
            } catch let error as PTPClientError where error.shouldAbortParameterSnapshot {
                throw error
            } catch {
                diagnosticsLog?.record("camera.parameter.read.failed", fields: readFailureFields(
                    parameter: parameter,
                    mapping: mapping,
                    error: error
                ))
            }
        }
        return descriptors
    }

    private func readFailureFields(
        parameter: CameraParameter,
        mapping: NikonCameraPropertyMapping,
        error: Error
    ) -> [String: String] {
        var fields = [
            "parameter": parameter.rawValue,
            "propertyCode": PTPDiagnostics.hex(mapping.propertyCode),
            "propertyName": NikonPTPDeviceProperty.name(for: mapping.propertyCode),
            "errorType": String(describing: type(of: error)),
            "error": error.localizedDescription
        ]
        if let ptpError = error as? PTPClientError,
           case .responseError(let code, let rawCode) = ptpError {
            fields["responseCode"] = PTPDiagnostics.hex(rawCode)
            fields["response"] = String(describing: code)
        }
        return fields
    }

    private func readDescriptor(mapping: NikonCameraPropertyMapping, generation: Int) async throws -> NikonPropertyDescriptor {
        try assertConnected(generation)
        let descriptorResult = try await ptp.send(.readPropertyDescription(mapping.propertyCode))
        try assertConnected(generation)
        var descriptor = try NikonPropertyDescriptorParser.parse(
            descriptorResult.payloadData,
            expectedPropertyCode: mapping.propertyCode
        )
        let valueResult = try await ptp.send(.readPropertyValue(mapping.propertyCode))
        try assertConnected(generation)
        descriptor.currentValue = try NikonPropertyDescriptorParser.decodeValue(
            valueResult.payloadData,
            dataType: mapping.dataType
        )
        return descriptor
    }

    private func activeConnectionGeneration() throws -> Int {
        guard isConnected else { throw NikonCameraRuntimeError.notConnected }
        return connectionGeneration
    }

    private func assertCurrentGeneration(_ generation: Int) throws {
        guard connectionGeneration == generation else {
            throw NikonCameraRuntimeError.notConnected
        }
    }

    private func assertConnected(_ generation: Int) throws {
        guard isConnected, connectionGeneration == generation else {
            throw NikonCameraRuntimeError.notConnected
        }
    }

    private func cameraValue(for parameter: CameraParameter, in state: CameraState) -> CameraValue {
        switch parameter {
        case .exposureMode:
            return state.exposureMode
        case .iso:
            return state.iso
        case .shutter:
            return state.shutter
        case .aperture:
            return state.aperture
        case .whiteBalance:
            return state.whiteBalance
        case .focusMode:
            return state.focusMode
        }
    }
}

extension NikonCameraRuntime: NikonLiveViewRuntime {}

actor NikonPTPCameraTransport: CameraTransport {
    private let runtime: NikonCameraRuntime

    init(runtime: NikonCameraRuntime) {
        self.runtime = runtime
    }

    func connect() async throws {
        _ = try await runtime.connect()
    }

    func disconnect() async {
        await runtime.disconnect()
    }

    func currentState() async throws -> CameraState {
        try await runtime.currentState()
    }

    func setValue(_ value: String, for parameter: CameraParameter) async throws -> CameraState {
        try await runtime.setValue(value, for: parameter)
    }

    func trigger(_ action: CameraAction) async throws -> CameraState {
        try await runtime.trigger(action)
    }
}
