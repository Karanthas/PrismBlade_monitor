import XCTest
@testable import GPhotoProbe

final class ProbeDiagnosticsTests: XCTestCase {
    func testJSONLEncodingWritesOneEventPerLine() throws {
        let store = ProbeLogStore()
        let runID = UUID()

        store.append(
            ProbeLogEvent(
                runID: runID,
                probeID: "discovery",
                phase: "result",
                route: .internalFake,
                requestSummary: "discover",
                status: .passed
            )
        )
        store.append(
            ProbeLogEvent(
                runID: runID,
                probeID: "abilities",
                phase: "result",
                route: .ptp,
                requestSummary: "getDeviceInfo",
                status: .inconclusive,
                failureLayer: .iOSAPI
            )
        )

        let lines = try store.jsonl().split(separator: "\n")
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[0].contains("\"probeID\":\"discovery\""))
        XCTAssertTrue(lines[1].contains("\"failureLayer\":\"iOSAPI\""))
    }

    func testSerialEvidenceIsRedacted() throws {
        let store = ProbeLogStore()

        store.append(
            ProbeLogEvent(
                runID: UUID(),
                probeID: "discovery",
                phase: "result",
                route: .imageCaptureCore,
                requestSummary: "discover",
                status: .passed,
                evidence: ["serialNumber": "ABC123", "model": "Z6III"]
            )
        )

        let jsonl = try store.jsonl()
        XCTAssertTrue(jsonl.contains("\"serialNumber\":\"REDACTED\""))
        XCTAssertTrue(jsonl.contains("\"model\":\"Z6III\""))
        XCTAssertTrue(jsonl.contains("\"redactionStatus\":\"redacted\""))
    }

    func testExporterIncludesJSONL() throws {
        let store = ProbeLogStore()
        let runID = UUID()
        store.append(
            ProbeLogEvent(
                runID: runID,
                probeID: "exportDiagnostics",
                phase: "result",
                route: .internalFake,
                requestSummary: "export",
                status: .passed
            )
        )

        let bundle = try ProbeLogExporter.makeBundle(
            runID: runID,
            appBuild: "1",
            iOSVersion: "sim",
            deviceModel: "simulator",
            targetCamera: nil,
            setupNotes: ["unit test"],
            store: store
        )

        XCTAssertEqual(bundle.runID, runID)
        XCTAssertTrue(bundle.jsonl.contains("exportDiagnostics"))
    }

    func testExporterRedactsTargetCameraSerialNumber() throws {
        let camera = CameraDeviceProbeDescriptor(
            id: "camera-1",
            name: "Nikon Z6III",
            manufacturer: "Nikon",
            model: "Z6III",
            serialNumber: "ABC123456",
            connectionRoute: .imageCaptureCore,
            capabilities: [.canAcceptPTPCommands]
        )

        let bundle = try ProbeLogExporter.makeBundle(
            runID: UUID(),
            appBuild: "1",
            iOSVersion: "sim",
            deviceModel: "simulator",
            targetCamera: camera,
            setupNotes: [],
            store: ProbeLogStore()
        )

        XCTAssertEqual(bundle.targetCamera?.serialNumber, "REDACTED")
    }
}
