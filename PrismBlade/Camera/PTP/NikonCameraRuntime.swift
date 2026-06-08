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
    case parameterWriteFailed(CameraParameterWriteDiagnostic)

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
            recordWriteDiagnostic(diagnostic, event: "camera.parameter.write.failed")
            throw NikonCameraRuntimeError.parameterWriteFailed(diagnostic)
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
            return "\(parameter.title) 写入后读回值不一致。"
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
