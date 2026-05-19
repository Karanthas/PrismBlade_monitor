import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation

protocol FrameSource {
    // 帧源协议只描述画面输入，不关心 USB、视频文件或模拟器生成方式。
    var status: FrameSourceStatus { get }
    var format: FrameFormat? { get }

    func start() async throws
    func stop() async
    func frames() -> AsyncStream<VideoFrame>
}

enum FrameSourceStatus: Equatable {
    case stopped
    case running
    case failed(String)
}

struct FrameFormat: Equatable, Sendable {
    var resolution: CGSize
    var frameRate: Double
    var colorEncoding: SourceColorEncoding
}

enum SourceColorEncoding: String, Sendable {
    case rec709 = "Rec.709"
    case nLog = "N-Log"
    case hlg = "HLG"
}

struct VideoFrame: Equatable, @unchecked Sendable {
    // sequence 用于后续丢帧/性能统计；timestamp 用于未来延迟和同步分析。
    var sequence: Int
    var timestamp: CMTime
    var format: FrameFormat
    var pixelBuffer: CVPixelBuffer
    // metadata 预留给未来真实 live view，把相机参数随帧带进显示链路。
    var metadata: FrameCameraMetadata

    static let placeholder: VideoFrame = {
        let format = FrameFormat(
            resolution: CGSize(width: 1280, height: 720),
            frameRate: 30,
            colorEncoding: .rec709
        )

        return VideoFrame(
            sequence: 0,
            timestamp: .zero,
            format: format,
            pixelBuffer: SimulatedPixelBufferFactory.makePlaceholderBuffer(format: format),
            metadata: FrameCameraMetadata(iso: "400", shutter: "1/50", aperture: "f/2.8", whiteBalance: "5600K")
        )
    }()

    static func == (lhs: VideoFrame, rhs: VideoFrame) -> Bool {
        // CVPixelBuffer is a Core Foundation object, so semantic pixel-by-pixel equality would be too
        // expensive for frame state comparisons. Identity plus metadata is enough for tests and UI diffing.
        lhs.sequence == rhs.sequence &&
            lhs.timestamp == rhs.timestamp &&
            lhs.format == rhs.format &&
            lhs.metadata == rhs.metadata &&
            lhs.pixelBuffer === rhs.pixelBuffer
    }
}

struct FrameCameraMetadata: Equatable, Sendable {
    var iso: String
    var shutter: String
    var aperture: String
    var whiteBalance: String
}

final class SimulatedFrameSource: FrameSource {
    private(set) var status: FrameSourceStatus = .stopped
    private(set) var format: FrameFormat?

    private let metadata: FrameCameraMetadata
    private var continuation: AsyncStream<VideoFrame>.Continuation?
    private var task: Task<Void, Never>?

    init(
        format: FrameFormat = FrameFormat(
            resolution: CGSize(width: 1280, height: 720),
            frameRate: 30,
            colorEncoding: .rec709
        ),
        metadata: FrameCameraMetadata = FrameCameraMetadata(
            iso: "400",
            shutter: "1/50",
            aperture: "f/2.8",
            whiteBalance: "5600K"
        )
    ) {
        self.format = format
        self.metadata = metadata
    }

    func start() async throws {
        status = .running
        // 重新 start 时先取消旧任务，避免多个模拟帧循环同时向同一个 stream yield。
        task?.cancel()

        task = Task { [weak self] in
            guard let self else { return }
            var sequence = 0

            while !Task.isCancelled {
                sequence += 1
                let currentFormat = format ?? VideoFrame.placeholder.format

                do {
                    // 阶段 2 开始模拟源也必须生成真实 CVPixelBuffer。后续 Metal renderer、
                    // LUT、伪色、斑马纹和 scope 都会消费同一份像素数据，而不是各自重建画面。
                    let pixelBuffer = try SimulatedPixelBufferFactory.makeFrame(
                        sequence: sequence,
                        format: currentFormat
                    )

                    continuation?.yield(VideoFrame(
                        sequence: sequence,
                        timestamp: Self.timestamp(for: sequence, frameRate: currentFormat.frameRate),
                        format: currentFormat,
                        pixelBuffer: pixelBuffer,
                        metadata: metadata
                    ))
                } catch {
                    status = .failed(error.localizedDescription)
                    continuation?.finish()
                    return
                }

                // 约 30fps，匹配技术文档中首版监看目标，同时避免模拟器负载过高。
                try? await Task.sleep(nanoseconds: 33_333_333)
            }
        }
    }

    func stop() async {
        task?.cancel()
        task = nil
        status = .stopped
        continuation?.finish()
    }

    func frames() -> AsyncStream<VideoFrame> {
        AsyncStream { continuation in
            // 保存 continuation 让 start() 中的后台任务可以持续推送模拟帧。
            self.continuation = continuation
        }
    }

    private static func timestamp(for sequence: Int, frameRate: Double) -> CMTime {
        let timescale = max(Int32(frameRate.rounded()), 1)
        return CMTime(value: CMTimeValue(sequence), timescale: timescale)
    }
}
