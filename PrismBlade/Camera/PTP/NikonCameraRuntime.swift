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
        rawToDisplay[rawValue] ?? "\(rawValue)"
    }

    func rawValue(for displayValue: String) -> UInt32? {
        rawToDisplay.first { $0.value == displayValue }?.key
    }
}

struct NikonZ6IIIPropertyMapper {
    private let mappings: [CameraParameter: NikonCameraPropertyMapping]

    init(mappings: [CameraParameter: NikonCameraPropertyMapping] = Self.defaultMappings) {
        self.mappings = mappings
    }

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
            propertyCode: 0x500D,
            dataType: .unsignedInt32,
            rawToDisplay: [400: "1/25", 200: "1/50", 167: "1/60", 100: "1/100", 80: "1/125", 40: "1/250"],
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
            rawToDisplay: [2: "Auto", 4: "5600K", 6: "6500K", 7: "3200K", 32784: "4300K"],
            isWriteApproved: true
        ),
        .focusMode: NikonCameraPropertyMapping(
            parameter: .focusMode,
            propertyCode: 0x500A,
            dataType: .unsignedInt16,
            rawToDisplay: [1: "MF", 2: "AF-S", 3: "AF-C"],
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
            let options = mapping.rawToDisplay.keys.sorted().map(mapping.displayValue)
            return CameraValue(current: options.first ?? "Unknown", options: options, isWritable: false)
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
            return mapping.rawToDisplay.keys
                .filter { descriptor.permits($0) && permittedRange.contains($0) }
                .sorted()
        }

        return mapping.rawToDisplay.keys.sorted()
    }
}

enum NikonCameraRuntimeError: Error, Equatable, LocalizedError {
    case notConnected
    case liveViewNotActive
    case unsupportedParameter(CameraParameter)
    case readOnlyParameter(CameraParameter)
    case unsupportedAction(CameraAction)
    case readbackMismatch(parameter: CameraParameter, expected: String, actual: String)

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
        }
    }
}

protocol NikonLiveViewRuntime {
    func startLiveViewSession() async throws
    func fetchLiveViewPayload() async throws -> Data
    func endLiveViewSession() async throws -> Bool
}

actor NikonCameraRuntime {
    private let discovery: NikonCameraDiscoveryService
    private let ptp: NikonRuntimePTPSending
    private let mapper: NikonZ6IIIPropertyMapper
    private var selectedCamera: NikonCameraDescriptor?
    private var isConnected = false
    private var isLiveViewActive = false
    private var connectionGeneration = 0

    init(
        discovery: NikonCameraDiscoveryService,
        ptp: NikonRuntimePTPSending,
        mapper: NikonZ6IIIPropertyMapper = NikonZ6IIIPropertyMapper()
    ) {
        self.discovery = discovery
        self.ptp = ptp
        self.mapper = mapper
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
            throw NikonCameraRuntimeError.unsupportedParameter(parameter)
        }

        let descriptor = try await readDescriptor(mapping: mapping, generation: generation)
        let write = try mapper.encodedWrite(parameter: parameter, value: value, descriptor: descriptor)
        try assertConnected(generation)
        _ = try await ptp.send(.writeImmediateControl(
            parameter: parameter,
            propertyCode: write.propertyCode,
            encodedValue: write.encodedValue
        ))
        try assertConnected(generation)
        let updatedState = try await currentState(generation: generation)
        let readbackValue = cameraValue(for: parameter, in: updatedState).current
        guard readbackValue == value else {
            throw NikonCameraRuntimeError.readbackMismatch(parameter: parameter, expected: value, actual: readbackValue)
        }
        return updatedState
    }

    func trigger(_ action: CameraAction) async throws -> CameraState {
        throw NikonCameraRuntimeError.unsupportedAction(action)
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

    private func readDescriptors(generation: Int) async throws -> [CameraParameter: NikonPropertyDescriptor] {
        var descriptors: [CameraParameter: NikonPropertyDescriptor] = [:]
        for parameter in CameraParameter.allCases {
            guard let mapping = mapper.mapping(for: parameter) else { continue }
            descriptors[parameter] = try await readDescriptor(mapping: mapping, generation: generation)
        }
        return descriptors
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
