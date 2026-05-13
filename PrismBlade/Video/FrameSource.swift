import Foundation
import CoreGraphics

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

struct VideoFrame: Equatable, Sendable {
    // sequence 用于后续丢帧/性能统计；timestamp 用于未来延迟和同步分析。
    var sequence: Int
    var timestamp: Date
    var format: FrameFormat
    var phase: Double
    // metadata 预留给未来真实 live view，把相机参数随帧带进显示链路。
    var metadata: FrameCameraMetadata

    static let placeholder = VideoFrame(
        sequence: 0,
        timestamp: Date(),
        format: FrameFormat(resolution: CGSize(width: 1920, height: 1080), frameRate: 30, colorEncoding: .rec709),
        phase: 0,
        metadata: FrameCameraMetadata(iso: "400", shutter: "1/50", aperture: "f/2.8", whiteBalance: "5600K")
    )
}

struct FrameCameraMetadata: Equatable, Sendable {
    var iso: String
    var shutter: String
    var aperture: String
    var whiteBalance: String
}

final class SimulatedFrameSource: FrameSource {
    private(set) var status: FrameSourceStatus = .stopped
    private(set) var format: FrameFormat? = FrameFormat(
        resolution: CGSize(width: 1920, height: 1080),
        frameRate: 30,
        colorEncoding: .rec709
    )

    private var continuation: AsyncStream<VideoFrame>.Continuation?
    private var task: Task<Void, Never>?

    func start() async throws {
        status = .running
        // 重新 start 时先取消旧任务，避免多个模拟帧循环同时向同一个 stream yield。
        task?.cancel()

        task = Task { [weak self] in
            guard let self else { return }
            var sequence = 0

            while !Task.isCancelled {
                sequence += 1
                // phase 是 0...1 的循环进度，SyntheticPreviewView 用它驱动移动色块。
                let phase = Double(sequence % 240) / 240

                // 程序生成 ramp + 色块，避免首版依赖外部测试视频资源。
                continuation?.yield(VideoFrame(
                    sequence: sequence,
                    timestamp: Date(),
                    format: format ?? VideoFrame.placeholder.format,
                    phase: phase,
                    metadata: FrameCameraMetadata(iso: "400", shutter: "1/50", aperture: "f/2.8", whiteBalance: "5600K")
                ))

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
}
