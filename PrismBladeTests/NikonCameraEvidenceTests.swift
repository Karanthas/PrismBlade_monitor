import CoreGraphics
import XCTest
@testable import PrismBlade

final class NikonCameraEvidenceTests: XCTestCase {
    func testNamedPropertyConstantsMatchPolicyMappings() {
        XCTAssertEqual(NikonPTPDeviceProperty.standardImmediateControlCodes, PTPOperationPolicy.nikonZ6IIIImmediateWritePropertyCodes)
        XCTAssertEqual(NikonPTPDeviceProperty.liveViewSize, 0xD1AC)
        XCTAssertEqual(NikonPTPDeviceProperty.name(for: NikonPTPDeviceProperty.liveViewSize), "NikonLiveViewImageSize")
        XCTAssertTrue(NikonPTPDeviceProperty.nLogCandidateCodes.allSatisfy { $0.code >= 0xD000 })
    }

    func testColorEvidenceKeepsUnknownVendorValuesInconclusive() {
        let observation = PropertyObservation(
            code: 0xD1A2,
            name: "NikonVideoToneMode",
            access: "readOnly",
            currentValue: PropertyValueObservation(raw: "7", display: "raw:7"),
            permittedValues: [],
            permittedRange: nil,
            reason: "Raw value is not mapped by hardware or upstream evidence yet."
        )

        let evidence = NikonColorEncodingEvidence.inconclusive(
            [observation],
            reason: "Unknown raw Nikon tone value."
        )

        XCTAssertNil(evidence.sourceColorEncoding)
        XCTAssertEqual(evidence.evidenceFields["colorEncoding"], "inconclusive")
        XCTAssertEqual(evidence.evidenceFields["colorObservation0.propertyCode"], "0xD1A2")
        XCTAssertEqual(evidence.evidenceFields["colorObservation0.current.raw"], "7")
    }

    func testLiveViewSessionEvidenceSerializesFrameSizeAndSelection() {
        let selected = PropertyValueObservation(raw: "2", display: "1920x1080")
        let sizeEvidence = NikonLiveViewSizeEvidence(
            observation: PropertyObservation(
                code: NikonPTPDeviceProperty.liveViewSize,
                name: NikonPTPDeviceProperty.name(for: NikonPTPDeviceProperty.liveViewSize),
                access: "readWrite",
                currentValue: selected,
                permittedValues: [selected],
                permittedRange: nil,
                reason: "Descriptor permits selected value and readback matched."
            ),
            selectedValue: selected,
            decodedFrameSize: CGSize(width: 1920, height: 1080),
            sourceIs1920x1080: true,
            reason: "First decoded source frame matched selected live-view size."
        )
        let sessionEvidence = NikonLiveViewSessionEvidence(
            colorEncoding: .rec709,
            colorEvidence: .rec709(PropertyObservation(
                code: 0xD1A2,
                name: "NikonVideoToneMode",
                access: "readOnly",
                currentValue: PropertyValueObservation(raw: "0", display: "Rec.709"),
                permittedValues: [],
                permittedRange: nil,
                reason: "Known direct tone value."
            )),
            liveViewSizeEvidence: sizeEvidence,
            selectedLiveViewSize: selected,
            decodedFrameSize: CGSize(width: 1920, height: 1080)
        )

        let fields = sessionEvidence.evidenceFields
        XCTAssertEqual(fields["sessionColorEncoding"], "Rec.709")
        XCTAssertEqual(fields["liveViewSizeSourceIs1920x1080"], "true")
        XCTAssertEqual(fields["decodedWidth"], "1920")
        XCTAssertEqual(fields["sessionDecodedHeight"], "1080")
        XCTAssertEqual(fields["sessionSelectedLiveViewSize.display"], "1920x1080")
    }

    func testNikonZ6IIISelectorTargetsLargestObservedLiveViewRawValue() {
        let descriptor = NikonPropertyDescriptor(
            propertyCode: NikonPTPDeviceProperty.liveViewSize,
            dataType: .unsignedInt16,
            isWritable: true,
            currentValue: 1,
            permittedValues: [1, 2, 3]
        )

        let selection = NikonLiveViewSizeSelector.nikonZ6IIILargestObservedLiveViewSize.validatedTarget(for: descriptor)

        switch selection {
        case .select(let rawValue, let value):
            XCTAssertEqual(rawValue, 3)
            XCTAssertEqual(value.display, "1024x576")
        case .notSelected(let reason):
            XCTFail("Expected observed largest selector to select a preferred value, got: \(reason)")
        }
    }

    func testWriteDiagnosticCarriesDescriptorAttemptAndReadbackEvidence() {
        let diagnostic = CameraParameterWriteDiagnostic(
            parameterName: "ISO",
            propertyCode: NikonPTPDeviceProperty.exposureIndex,
            descriptor: PropertyObservation(
                code: NikonPTPDeviceProperty.exposureIndex,
                name: NikonPTPDeviceProperty.name(for: NikonPTPDeviceProperty.exposureIndex),
                access: "readWrite",
                currentValue: PropertyValueObservation(raw: "400", display: "400"),
                permittedValues: [PropertyValueObservation(raw: "400", display: "400")],
                permittedRange: nil,
                reason: "Descriptor read before write."
            ),
            attemptedValue: PropertyValueObservation(raw: "800", display: "800"),
            responseCode: 0x2001,
            readbackValue: PropertyValueObservation(raw: "400", display: "400"),
            blockReason: .readbackMismatch,
            userMessage: "ISO readback did not match the requested value."
        )

        let fields = diagnostic.evidenceFields
        XCTAssertEqual(fields["parameter"], "ISO")
        XCTAssertEqual(fields["propertyCode"], "0x500F")
        XCTAssertEqual(fields["attempted.display"], "800")
        XCTAssertEqual(fields["readback.raw"], "400")
        XCTAssertEqual(fields["blockReason"], "readbackMismatch")
    }
}
