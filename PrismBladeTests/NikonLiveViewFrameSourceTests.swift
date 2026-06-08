import CoreVideo
import XCTest
@testable import PrismBlade

final class NikonLiveViewFrameSourceTests: XCTestCase {
    func testStartFetchesAndYieldsDecodedFrame() async throws {
        let runtime = ScriptedLiveViewRuntime(payloads: [try Self.liveViewPayload(width: 4, height: 3)])
        let source = NikonLiveViewFrameSource(runtime: runtime)
        let stream = source.frames()
        var iterator = stream.makeAsyncIterator()

        try await source.start()
        guard let frame = await iterator.next() else {
            return XCTFail("Expected one decoded frame.")
        }
        await source.stop()

        XCTAssertEqual(frame.sequence, 1)
        XCTAssertEqual(CVPixelBufferGetWidth(frame.pixelBuffer), 4)
        XCTAssertEqual(CVPixelBufferGetHeight(frame.pixelBuffer), 3)
        XCTAssertEqual(frame.format.colorEncoding, .rec709)
        let operations = await runtime.operations()
        XCTAssertEqual(Array(operations.prefix(2)), [.start, .fetch])
        XCTAssertEqual(operations.filter { $0 == .end }.count, 1)
    }

    func testFrameStreamBuffersNewestFrameOnly() async throws {
        let payload = try Self.liveViewPayload()
        let runtime = ScriptedLiveViewRuntime(payloads: Array(repeating: payload, count: 20))
        let source = NikonLiveViewFrameSource(runtime: runtime)
        let stream = source.frames()

        try await source.start()
        try await Task.sleep(nanoseconds: 50_000_000)
        var iterator = stream.makeAsyncIterator()
        guard let frame = await iterator.next() else {
            return XCTFail("Expected a buffered latest frame.")
        }
        await source.stop()

        XCTAssertGreaterThan(frame.sequence, 1)
    }

    func testFrameSourceUsesRuntimeSuppliedColorEncoding() async throws {
        let runtime = ScriptedLiveViewRuntime(
            payloads: [try Self.liveViewPayload()],
            evidence: .knownColorEncoding(.nLog)
        )
        let source = NikonLiveViewFrameSource(runtime: runtime)
        let stream = source.frames()
        var iterator = stream.makeAsyncIterator()

        try await source.start()
        guard let frame = await iterator.next() else {
            return XCTFail("Expected one decoded frame.")
        }
        await source.stop()

        XCTAssertEqual(frame.format.colorEncoding, .nLog)
    }

    func testFrameSourceRecordsFirstDecodedLiveViewSizeEvidence() async throws {
        let selected = PropertyValueObservation(raw: "2", display: "1920x1080")
        var evidence = NikonLiveViewSessionEvidence.knownColorEncoding(.rec709)
        evidence.selectedLiveViewSize = selected
        evidence.liveViewSizeEvidence.selectedValue = selected
        let diagnosticsLog = AppDiagnosticsLog()
        let runtime = ScriptedLiveViewRuntime(
            payloads: [try Self.liveViewPayload(width: 4, height: 3)],
            evidence: evidence
        )
        let source = NikonLiveViewFrameSource(runtime: runtime, diagnosticsLog: diagnosticsLog)
        let stream = source.frames()
        var iterator = stream.makeAsyncIterator()

        try await source.start()
        _ = await iterator.next()
        await source.stop()

        let logText = diagnosticsLog.exportText()
        XCTAssertTrue(logText.contains(#""event":"camera.liveView.decodedFrame""#))
        XCTAssertTrue(logText.contains(#""decodedWidth":"4""#))
        XCTAssertTrue(logText.contains(#""decodedHeight":"3""#))
        XCTAssertTrue(logText.contains(#""liveViewSizeSourceIs1920x1080":"false""#))
    }

    func testFrameSourceClassifies1080pFromDecodedFrameSize() async throws {
        let selected = PropertyValueObservation(raw: "3", display: "1024x576")
        var evidence = NikonLiveViewSessionEvidence.knownColorEncoding(.rec709)
        evidence.selectedLiveViewSize = selected
        evidence.liveViewSizeEvidence.selectedValue = selected
        let diagnosticsLog = AppDiagnosticsLog()
        let runtime = ScriptedLiveViewRuntime(
            payloads: [try Self.liveViewPayload(width: 1920, height: 1080)],
            evidence: evidence
        )
        let source = NikonLiveViewFrameSource(runtime: runtime, diagnosticsLog: diagnosticsLog)
        let stream = source.frames()
        var iterator = stream.makeAsyncIterator()

        try await source.start()
        _ = await iterator.next()
        await source.stop()

        let logText = diagnosticsLog.exportText()
        XCTAssertTrue(logText.contains(#""decodedWidth":"1920""#))
        XCTAssertTrue(logText.contains(#""decodedHeight":"1080""#))
        XCTAssertTrue(logText.contains(#""liveViewSizeSourceIs1920x1080":"true""#))
    }

    func testStopBeforeStartSendsNoCleanup() async {
        let runtime = ScriptedLiveViewRuntime(payloads: [])
        let source = NikonLiveViewFrameSource(runtime: runtime)

        await source.stop()

        let operations = await runtime.operations()
        XCTAssertEqual(operations, [])
    }

    func testStopAfterStartSendsExactlyOneCleanup() async throws {
        let runtime = ScriptedLiveViewRuntime(payloads: [try Self.liveViewPayload()])
        let source = NikonLiveViewFrameSource(runtime: runtime)
        let stream = source.frames()

        try await source.start()
        await source.stop()
        await source.stop()

        _ = stream
        let operations = await runtime.operations()
        XCTAssertEqual(operations.filter { $0 == .end }.count, 1)
    }

    func testDecodeFailureMarksFailedAndAttemptsCleanup() async throws {
        let runtime = ScriptedLiveViewRuntime(payloads: [Data([0x00, 0x01, 0x02])])
        let source = NikonLiveViewFrameSource(runtime: runtime)
        let stream = source.frames()

        try await source.start()
        try await waitForFailure(source)

        _ = stream
        let operations = await runtime.operations()
        XCTAssertEqual(operations.filter { $0 == .end }.count, 1)
        if case .failed = source.status {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected failed status.")
        }
    }

    private static func liveViewPayload(width: Int = 2, height: Int = 2) throws -> Data {
        Data([0xAA, 0xBB, 0xCC]) + (try JPEGPixelBufferDecoderTests.makeJPEG(width: width, height: height)) + Data([0xDD])
    }

    private func waitForFailure(_ source: NikonLiveViewFrameSource) async throws {
        for _ in 0..<50 {
            if case .failed = source.status {
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Frame source did not enter failed state.")
    }
}

private actor ScriptedLiveViewRuntime: NikonLiveViewRuntime {
    enum Operation: Equatable {
        case start
        case fetch
        case end
    }

    private var payloads: [Data]
    private let evidence: NikonLiveViewSessionEvidence
    private var recordedOperations: [Operation] = []
    private var isStarted = false

    init(payloads: [Data], evidence: NikonLiveViewSessionEvidence = .knownColorEncoding(.rec709)) {
        self.payloads = payloads
        self.evidence = evidence
    }

    func liveViewSessionEvidence() async throws -> NikonLiveViewSessionEvidence {
        evidence
    }

    func startLiveViewSession() async throws {
        recordedOperations.append(.start)
        isStarted = true
    }

    func fetchLiveViewPayload() async throws -> Data {
        recordedOperations.append(.fetch)
        while payloads.isEmpty {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        return payloads.removeFirst()
    }

    func endLiveViewSession() async throws -> Bool {
        guard isStarted else { return false }
        recordedOperations.append(.end)
        isStarted = false
        return true
    }

    func operations() -> [Operation] {
        recordedOperations
    }
}

private extension NikonLiveViewSessionEvidence {
    static func knownColorEncoding(_ encoding: SourceColorEncoding) -> NikonLiveViewSessionEvidence {
        let observation = PropertyObservation(
            code: 0xD1A2,
            name: "NikonVideoToneMode",
            access: "readOnly",
            currentValue: PropertyValueObservation(raw: "1", display: encoding.rawValue),
            permittedValues: [],
            permittedRange: nil,
            reason: "Test runtime color evidence."
        )
        let colorEvidence: NikonColorEncodingEvidence = encoding == .nLog ? .nLog(observation) : .rec709(observation)
        return NikonLiveViewSessionEvidence(
            colorEncoding: encoding,
            colorEvidence: colorEvidence,
            liveViewSizeEvidence: .init(
                observation: nil,
                selectedValue: nil,
                decodedFrameSize: nil,
                sourceIs1920x1080: false,
                reason: "No live-view size evidence in frame-source color tests."
            ),
            selectedLiveViewSize: nil,
            decodedFrameSize: nil
        )
    }
}
