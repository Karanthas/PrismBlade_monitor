@testable import PrismBlade
import AVFoundation
import CoreMedia
import CoreVideo
import XCTest

final class FrameSourceStage2Tests: XCTestCase {
    func testVideoFrameCarriesPixelBufferAndMetadata() throws {
        let format = FrameFormat(
            resolution: CGSize(width: 16, height: 16),
            frameRate: 24,
            colorEncoding: .rec709
        )
        let pixelBuffer = try PixelBufferFixtureFactory.makeHorizontalGrayRamp(width: 16, height: 16)
        let metadata = FrameCameraMetadata(
            iso: "800",
            shutter: "1/48",
            aperture: "f/4",
            whiteBalance: "5600K"
        )

        let frame = VideoFrame(
            sequence: 7,
            timestamp: CMTime(value: 7, timescale: 24),
            format: format,
            pixelBuffer: pixelBuffer,
            metadata: metadata
        )

        XCTAssertEqual(frame.sequence, 7)
        XCTAssertEqual(frame.timestamp, CMTime(value: 7, timescale: 24))
        XCTAssertEqual(frame.format, format)
        XCTAssertEqual(frame.metadata, metadata)
        XCTAssertEqual(CVPixelBufferGetWidth(frame.pixelBuffer), 16)
        XCTAssertEqual(CVPixelBufferGetHeight(frame.pixelBuffer), 16)
        XCTAssertEqual(CVPixelBufferGetPixelFormatType(frame.pixelBuffer), kCVPixelFormatType_32BGRA)
    }

    func testSimulatedFrameSourceOutputsRealPixelBuffer() async throws {
        // 用小分辨率测试模拟源，避免单元测试为了验证媒体边界而承担 720p/1080p 的填充成本。
        let format = FrameFormat(
            resolution: CGSize(width: 64, height: 36),
            frameRate: 30,
            colorEncoding: .rec709
        )
        let source = SimulatedFrameSource(format: format)
        let stream = source.frames()
        let firstFrameTask = Task { () -> VideoFrame? in
            var iterator = stream.makeAsyncIterator()
            return await iterator.next()
        }

        try await source.start()
        let frame = try await awaitOptionalValue(firstFrameTask)
        await source.stop()

        XCTAssertEqual(source.status, .stopped)
        XCTAssertEqual(frame.sequence, 1)
        XCTAssertEqual(frame.timestamp, CMTime(value: 1, timescale: 30))
        XCTAssertEqual(frame.format, format)
        XCTAssertEqual(CVPixelBufferGetWidth(frame.pixelBuffer), 64)
        XCTAssertEqual(CVPixelBufferGetHeight(frame.pixelBuffer), 36)
        XCTAssertEqual(CVPixelBufferGetPixelFormatType(frame.pixelBuffer), kCVPixelFormatType_32BGRA)

        // 阶段 2 不只检查“有 buffer”，还要确认 buffer 中确实写入了可预测像素。
        // 水平 ramp 的右边缘应该比左边缘更亮，这会保护后续 Metal 采样测试的输入质量。
        let darkEdge = try PixelBufferFixtureFactory.readPixel(frame.pixelBuffer, x: 0, y: 0)
        let brightEdge = try PixelBufferFixtureFactory.readPixel(frame.pixelBuffer, x: 63, y: 0)
        XCTAssertLessThan(darkEdge.red, brightEdge.red)
    }

    func testVideoFileFrameSourceReadsGeneratedMovieFrames() async throws {
        let url = try makeTemporaryMovie(
            filename: "stage2_REC709.mov",
            frameCount: 3,
            width: 32,
            height: 18,
            frameRate: 30
        )
        let source = VideoFileFrameSource(
            url: url,
            loops: false,
            playsInRealtime: false,
            colorEncodingHint: .rec709
        )
        let stream = source.frames()
        // 先建立 iterator 再 start，模拟 MonitorSession 的长期订阅模式，同时避免首帧竞争。
        let frameTask = Task { () -> [VideoFrame] in
            var iterator = stream.makeAsyncIterator()
            var frames: [VideoFrame] = []

            while frames.count < 3, let frame = await iterator.next() {
                frames.append(frame)
            }

            return frames
        }

        try await source.start()
        let frames = try await awaitValue(frameTask, timeoutNanoseconds: 10_000_000_000)
        await source.stop()

        XCTAssertEqual(frames.count, 3)
        XCTAssertEqual(frames.map(\.sequence), [1, 2, 3])
        XCTAssertEqual(frames.map(\.format.colorEncoding), [.rec709, .rec709, .rec709])
        XCTAssertEqual(CVPixelBufferGetWidth(frames[0].pixelBuffer), 32)
        XCTAssertEqual(CVPixelBufferGetHeight(frames[0].pixelBuffer), 18)
        XCTAssertLessThanOrEqual(frames[0].timestamp, frames[1].timestamp)
        XCTAssertLessThanOrEqual(frames[1].timestamp, frames[2].timestamp)
    }

    func testVideoFileFrameSourceInfersColorEncodingFromMaterialStyleFilename() async throws {
        let url = try makeTemporaryMovie(
            filename: "NLOG_stage2.mov",
            frameCount: 1,
            width: 16,
            height: 16,
            frameRate: 24
        )
        let source = VideoFileFrameSource(url: url, loops: false, playsInRealtime: false)
        let stream = source.frames()
        let firstFrameTask = Task { () -> VideoFrame? in
            var iterator = stream.makeAsyncIterator()
            return await iterator.next()
        }

        try await source.start()
        let frame = try await awaitOptionalValue(firstFrameTask)
        await source.stop()

        XCTAssertEqual(frame.format.colorEncoding, .nLog)
    }

    private func makeTemporaryMovie(
        filename: String,
        frameCount: Int,
        width: Int,
        height: Int,
        frameRate: Int32
    ) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: url)

        // 临时视频由 AVAssetWriter 生成，不进入 git，也不依赖 material/ 中的真实素材。
        // 这样阶段 2 的基础视频读取测试可以在任意开发机和 CI 上稳定复现。
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height
            ]
        )
        input.expectsMediaDataInRealTime = false

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferMetalCompatibilityKey as String: true
            ]
        )

        XCTAssertTrue(writer.canAdd(input))
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)

        let queue = DispatchQueue(label: "PrismBladeTests.MovieWriter")
        let semaphore = DispatchSemaphore(value: 0)
        var writeError: Error?
        var frameIndex = 0

        input.requestMediaDataWhenReady(on: queue) {
            // AVAssetWriterInputPixelBufferAdaptor 接收的正是阶段 2 约定的 CVPixelBuffer，
            // 因此这个 fixture 同时验证了“生成帧 -> 编码 -> AVAssetReader 解码”的完整媒体边界。
            while input.isReadyForMoreMediaData, frameIndex < frameCount {
                do {
                    let format = FrameFormat(
                        resolution: CGSize(width: width, height: height),
                        frameRate: Double(frameRate),
                        colorEncoding: .rec709
                    )
                    let pixelBuffer = try SimulatedPixelBufferFactory.makeFrame(sequence: frameIndex + 1, format: format)
                    let presentationTime = CMTime(value: CMTimeValue(frameIndex), timescale: frameRate)

                    guard adaptor.append(pixelBuffer, withPresentationTime: presentationTime) else {
                        throw writer.error ?? VideoFileFrameSource.SourceError.readingFailed("asset writer append failed")
                    }

                    frameIndex += 1
                } catch {
                    writeError = error
                    input.markAsFinished()
                    writer.cancelWriting()
                    semaphore.signal()
                    return
                }
            }

            if frameIndex == frameCount {
                input.markAsFinished()
                writer.finishWriting {
                    semaphore.signal()
                }
            }
        }

        semaphore.wait()

        if let writeError {
            throw writeError
        }

        if writer.status == .failed {
            throw writer.error ?? VideoFileFrameSource.SourceError.readingFailed("asset writer failed")
        }

        return url
    }

    private func awaitOptionalValue<T>(
        _ task: Task<T?, Never>,
        timeoutNanoseconds: UInt64 = 2_000_000_000
    ) async throws -> T {
        let value = try await awaitValue(task, timeoutNanoseconds: timeoutNanoseconds)

        guard let value else {
            throw Stage2TestError.missingValue
        }

        return value
    }

    private func awaitValue<T>(
        _ task: Task<T, Never>,
        timeoutNanoseconds: UInt64 = 2_000_000_000
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                await task.value
            }
            group.addTask {
                try await Task.sleep(nanoseconds: timeoutNanoseconds)
                throw Stage2TestError.timeout
            }

            let value = try await group.next()!
            group.cancelAll()
            return value
        }
    }
}

private enum Stage2TestError: Error {
    case timeout
    case missingValue
}
