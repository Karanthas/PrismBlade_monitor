import CoreGraphics
import Foundation

enum NikonPTPDeviceProperty {
    static let whiteBalance: UInt16 = 0x5005
    static let aperture: UInt16 = 0x5007
    static let focusMode: UInt16 = 0x500A
    static let exposureTime: UInt16 = 0x500D
    static let exposureProgramMode: UInt16 = 0x500E
    static let exposureIndex: UInt16 = 0x500F

    // Nikon exposes the user-selectable shutter speed here; 0x500D is the generic ExposureTime value.
    static let nikonExposureTime: UInt16 = 0xD100

    // Nikon vendor property exposed by libgphoto2 as LiveViewImageSize.
    static let liveViewSize: UInt16 = 0xD1AC

    static let nikonVideoToneMode: UInt16 = 0xD1A2
    static let nikonFlatPictureControl: UInt16 = 0xD1B2
    static let nikonNLogViewAssist: UInt16 = 0xD1B3

    static let standardImmediateControlCodes: [CameraParameter: UInt16] = [
        .exposureMode: exposureProgramMode,
        .iso: exposureIndex,
        .shutter: nikonExposureTime,
        .aperture: aperture,
        .whiteBalance: whiteBalance,
        .focusMode: focusMode
    ]

    static let nLogCandidateCodes: [NamedPTPPropertyCode] = [
        NamedPTPPropertyCode(code: nikonVideoToneMode, name: "NikonVideoToneMode"),
        NamedPTPPropertyCode(code: nikonFlatPictureControl, name: "NikonFlatPictureControl"),
        NamedPTPPropertyCode(code: nikonNLogViewAssist, name: "NikonNLogViewAssist")
    ]

    static func name(for code: UInt16) -> String {
        switch code {
        case whiteBalance:
            return "WhiteBalance"
        case aperture:
            return "FNumber"
        case focusMode:
            return "FocusMode"
        case exposureTime:
            return "ExposureTime"
        case exposureProgramMode:
            return "ExposureProgramMode"
        case exposureIndex:
            return "ExposureIndex"
        case nikonExposureTime:
            return "NikonExposureTime"
        case liveViewSize:
            return "NikonLiveViewImageSize"
        default:
            return nLogCandidateCodes.first { $0.code == code }?.name ?? "UnknownProperty"
        }
    }
}

struct NamedPTPPropertyCode: Equatable, Sendable {
    var code: UInt16
    var name: String

    var evidenceFields: [String: String] {
        [
            "propertyCode": PTPDiagnostics.hex(code),
            "propertyName": name
        ]
    }
}

enum NikonCameraEvidenceConfidence: String, Equatable, Sendable {
    case direct
    case indirect
    case inconclusive
}

enum NikonColorEncodingEvidence: Equatable, Sendable {
    case nLog(PropertyObservation)
    case nLogComposite([PropertyObservation], reason: String)
    case rec709(PropertyObservation)
    case inconclusive([PropertyObservation], reason: String)

    var sourceColorEncoding: SourceColorEncoding? {
        switch self {
        case .nLog, .nLogComposite:
            return .nLog
        case .rec709:
            return .rec709
        case .inconclusive:
            return nil
        }
    }

    var evidenceFields: [String: String] {
        switch self {
        case .nLog(let observation):
            return fields(
                classification: "nLog",
                confidence: .direct,
                reason: "known direct Nikon/PTP color evidence",
                observations: [observation]
            )
        case .nLogComposite(let observations, let reason):
            return fields(
                classification: "nLog",
                confidence: .indirect,
                reason: reason,
                observations: observations
            )
        case .rec709(let observation):
            return fields(
                classification: "rec709",
                confidence: .direct,
                reason: "known direct Nikon/PTP color evidence",
                observations: [observation]
            )
        case .inconclusive(let observations, let reason):
            return fields(
                classification: "inconclusive",
                confidence: .inconclusive,
                reason: reason,
                observations: observations
            )
        }
    }

    private func fields(
        classification: String,
        confidence: NikonCameraEvidenceConfidence,
        reason: String,
        observations: [PropertyObservation]
    ) -> [String: String] {
        var fields = [
            "colorEncoding": classification,
            "colorConfidence": confidence.rawValue,
            "colorReason": reason,
            "colorObservationCount": "\(observations.count)"
        ]
        for (index, observation) in observations.enumerated() {
            observation.evidenceFields.forEach { key, value in
                fields["colorObservation\(index).\(key)"] = value
            }
        }
        return fields
    }
}

struct NikonLiveViewSizeEvidence: Equatable, Sendable {
    var observation: PropertyObservation?
    var selectedValue: PropertyValueObservation?
    var decodedFrameSize: CGSize?
    var sourceIs1920x1080: Bool
    var reason: String

    var evidenceFields: [String: String] {
        var fields = [
            "liveViewSizeReason": reason,
            "liveViewSizeSourceIs1920x1080": sourceIs1920x1080 ? "true" : "false"
        ]
        if let observation {
            observation.evidenceFields.forEach { key, value in
                fields["liveViewSize.\(key)"] = value
            }
        }
        if let selectedValue {
            selectedValue.evidenceFields.forEach { key, value in
                fields["selectedLiveViewSize.\(key)"] = value
            }
        }
        if let decodedFrameSize {
            fields["decodedWidth"] = "\(Int(decodedFrameSize.width))"
            fields["decodedHeight"] = "\(Int(decodedFrameSize.height))"
        }
        return fields
    }
}

struct NikonLiveViewSizeSelector: Equatable, Sendable {
    var preferredValue: PropertyValueObservation?

    init(preferredValue: PropertyValueObservation? = nil) {
        self.preferredValue = preferredValue
    }

    static let nikonZ6IIILargestObservedLiveViewSize = NikonLiveViewSizeSelector(
        preferredValue: PropertyValueObservation(raw: "3", display: "1024x576")
    )

    func validatedTarget(for descriptor: NikonPropertyDescriptor) -> NikonLiveViewSizeSelection {
        guard let preferredValue else {
            return .notSelected("No preferred Nikon liveviewsize raw value is configured.")
        }
        guard descriptor.isWritable else {
            return .notSelected("Nikon liveviewsize descriptor is read-only.")
        }
        guard let rawValue = UInt32(preferredValue.raw) else {
            return .notSelected("Preferred Nikon liveviewsize raw value is not numeric.")
        }
        guard descriptor.permits(rawValue) else {
            return .notSelected("Nikon liveviewsize descriptor does not permit the preferred raw value.")
        }
        return .select(rawValue: rawValue, value: preferredValue)
    }
}

enum NikonLiveViewSizeSelection: Equatable, Sendable {
    case select(rawValue: UInt32, value: PropertyValueObservation)
    case notSelected(String)
}

struct NikonLiveViewSessionEvidence: Equatable, Sendable {
    var colorEncoding: SourceColorEncoding?
    var colorEvidence: NikonColorEncodingEvidence
    var liveViewSizeEvidence: NikonLiveViewSizeEvidence
    var selectedLiveViewSize: PropertyValueObservation?
    var decodedFrameSize: CGSize?

    static let inconclusive = NikonLiveViewSessionEvidence(
        colorEncoding: nil,
        colorEvidence: .inconclusive([], reason: "No live-view session evidence has been collected."),
        liveViewSizeEvidence: NikonLiveViewSizeEvidence(
            observation: nil,
            selectedValue: nil,
            decodedFrameSize: nil,
            sourceIs1920x1080: false,
            reason: "No live-view size evidence has been collected."
        ),
        selectedLiveViewSize: nil,
        decodedFrameSize: nil
    )

    var evidenceFields: [String: String] {
        var fields = colorEvidence.evidenceFields
        liveViewSizeEvidence.evidenceFields.forEach { key, value in
            fields[key] = value
        }
        if let colorEncoding {
            fields["sessionColorEncoding"] = colorEncoding.rawValue
        }
        if let selectedLiveViewSize {
            selectedLiveViewSize.evidenceFields.forEach { key, value in
                fields["sessionSelectedLiveViewSize.\(key)"] = value
            }
        }
        if let decodedFrameSize {
            fields["sessionDecodedWidth"] = "\(Int(decodedFrameSize.width))"
            fields["sessionDecodedHeight"] = "\(Int(decodedFrameSize.height))"
        }
        return fields
    }
}

struct PropertyObservation: Equatable, Sendable {
    var code: UInt16
    var name: String
    var access: String
    var currentValue: PropertyValueObservation?
    var permittedValues: [PropertyValueObservation]
    var permittedRange: PropertyValueRangeObservation?
    var reason: String

    var evidenceFields: [String: String] {
        var fields = [
            "propertyCode": PTPDiagnostics.hex(code),
            "propertyName": name,
            "propertyAccess": access,
            "reason": reason
        ]
        if let currentValue {
            currentValue.evidenceFields.forEach { key, value in
                fields["current.\(key)"] = value
            }
        }
        if !permittedValues.isEmpty {
            fields["allowedValuesRaw"] = permittedValues.map(\.raw).joined(separator: ",")
            fields["allowedValuesDisplay"] = permittedValues.map(\.display).joined(separator: ",")
        }
        if let permittedRange {
            permittedRange.evidenceFields.forEach { key, value in
                fields["range.\(key)"] = value
            }
        }
        return fields
    }
}

struct PropertyValueObservation: Equatable, Sendable {
    var raw: String
    var display: String

    var evidenceFields: [String: String] {
        [
            "raw": raw,
            "display": display
        ]
    }
}

struct PropertyValueRangeObservation: Equatable, Sendable {
    var minimum: PropertyValueObservation
    var maximum: PropertyValueObservation
    var step: PropertyValueObservation

    var evidenceFields: [String: String] {
        [
            "minimumRaw": minimum.raw,
            "minimumDisplay": minimum.display,
            "maximumRaw": maximum.raw,
            "maximumDisplay": maximum.display,
            "stepRaw": step.raw,
            "stepDisplay": step.display
        ]
    }
}

enum CameraParameterWriteBlockReason: String, Equatable, Sendable {
    case applied
    case unsupportedMapping
    case readOnlyDescriptor
    case unsupportedDisplayValue
    case unsupportedRawValue
    case descriptorRangeRejected
    case ptpResponseError
    case modeLock
    case readbackMismatch
}

struct NikonColorEncodingClassifier: Equatable, Sendable {
    struct DirectMapping: Equatable, Sendable {
        var propertyCode: UInt16
        var rawValue: String
        var encoding: SourceColorEncoding
        var displayValue: String
    }

    struct CompositeMapping: Equatable, Sendable {
        var requiredRawValues: [UInt16: String]
        var encoding: SourceColorEncoding
        var reason: String
    }

    var directMappings: [DirectMapping]
    var compositeMappings: [CompositeMapping]

    init(
        directMappings: [DirectMapping] = [],
        compositeMappings: [CompositeMapping] = Self.defaultCompositeMappings
    ) {
        self.directMappings = directMappings
        self.compositeMappings = compositeMappings
    }

    static let z6IIIObservedNLogCompositeMapping = CompositeMapping(
        requiredRawValues: [
            NikonPTPDeviceProperty.nikonVideoToneMode: "0",
            NikonPTPDeviceProperty.nikonFlatPictureControl: "0",
            NikonPTPDeviceProperty.nikonNLogViewAssist: "1"
        ],
        encoding: .nLog,
        reason: "Observed Nikon Z6III N-Log hardware evidence from iPhone/PTP diagnostics."
    )

    static let defaultCompositeMappings = [
        z6IIIObservedNLogCompositeMapping
    ]

    func classify(_ observations: [PropertyObservation]) -> NikonColorEncodingEvidence {
        for observation in observations {
            guard let currentValue = observation.currentValue else { continue }
            if let mapping = directMappings.first(where: {
                $0.propertyCode == observation.code && $0.rawValue == currentValue.raw
            }) {
                let mappedObservation = PropertyObservation(
                    code: observation.code,
                    name: observation.name,
                    access: observation.access,
                    currentValue: PropertyValueObservation(raw: currentValue.raw, display: mapping.displayValue),
                    permittedValues: observation.permittedValues,
                    permittedRange: observation.permittedRange,
                    reason: observation.reason
                )
                switch mapping.encoding {
                case .nLog:
                    return .nLog(mappedObservation)
                case .rec709:
                    return .rec709(mappedObservation)
                case .unknown, .hlg:
                    break
                }
            }
        }

        for mapping in compositeMappings {
            guard compositeMappingMatches(mapping, observations: observations) else { continue }
            let mappedObservations = observations.filter { observation in
                mapping.requiredRawValues[observation.code] != nil
            }
            switch mapping.encoding {
            case .nLog:
                return .nLogComposite(mappedObservations, reason: mapping.reason)
            case .rec709:
                if let observation = mappedObservations.first {
                    return .rec709(observation)
                }
            case .unknown, .hlg:
                break
            }
        }

        return .inconclusive(
            observations,
            reason: "No candidate property had a known direct N-Log or Rec.709 raw value."
        )
    }

    private func compositeMappingMatches(_ mapping: CompositeMapping, observations: [PropertyObservation]) -> Bool {
        for (propertyCode, rawValue) in mapping.requiredRawValues {
            guard observations.contains(where: { observation in
                observation.code == propertyCode && observation.currentValue?.raw == rawValue
            }) else {
                return false
            }
        }
        return true
    }
}


struct CameraParameterWriteDiagnostic: Equatable, Sendable {
    var parameterName: String
    var propertyCode: UInt16?
    var descriptor: PropertyObservation?
    var attemptedValue: PropertyValueObservation?
    var responseCode: UInt16?
    var readbackValue: PropertyValueObservation?
    var blockReason: CameraParameterWriteBlockReason
    var userMessage: String

    var evidenceFields: [String: String] {
        var fields = [
            "parameter": parameterName,
            "blockReason": blockReason.rawValue,
            "userMessage": userMessage
        ]
        if let propertyCode {
            fields["propertyCode"] = PTPDiagnostics.hex(propertyCode)
            fields["propertyName"] = NikonPTPDeviceProperty.name(for: propertyCode)
        }
        if let descriptor {
            descriptor.evidenceFields.forEach { key, value in
                fields["descriptor.\(key)"] = value
            }
        }
        if let attemptedValue {
            attemptedValue.evidenceFields.forEach { key, value in
                fields["attempted.\(key)"] = value
            }
        }
        if let responseCode {
            fields["responseCode"] = PTPDiagnostics.hex(responseCode)
        }
        if let readbackValue {
            readbackValue.evidenceFields.forEach { key, value in
                fields["readback.\(key)"] = value
            }
        }
        return fields
    }
}
