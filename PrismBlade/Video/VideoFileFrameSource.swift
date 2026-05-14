import AVFoundation
import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation

final class VideoFileFrameSource: FrameSource {
    enum SourceError: Error, LocalizedError, Equatable {
        case missingVideoTrack
        case readerCreationFailed(String)
        case outputNotAccepted
        case noPixelBuffer
        case readingFailed(String)

        var errorDescription: String? {
            switch self {
            case .missingVideoTrack:
                return "测试视频中没有可读取的视频轨道"
            case let .readerCreationFailed(message):
                return "无法创建 AVAssetReader：\(message)"
            case .outputNotAccepted:
                return "AVAssetReader 无法接受视频轨道输出"
            case .noPixelBuffer:
                return "视频 sample buffer 没有携带 CVPixelBuffer"
            case let .readingFailed(message):
                return "视频读取失败：\(message)"
            }
        }
    }

    private(set) var status: FrameSourceStatus = .stopped
    private(set) var format: FrameFormat?

    private let url: URL
    private let loops: Bool
    private let playsInRealtime: Bool
    private let colorEncodingHint: SourceColorEncoding?
    private let metadata: FrameCameraMetadata
    private var continuation: AsyncStream<VideoFrame>.Continuation?
    private var task: Task<Void, Never>?

    init(
        url: URL,
        loops: Bool = true,
        playsInRealtime: Bool = true,
        colorEncodingHint: SourceColorEncoding? = nil,
        metadata: FrameCameraMetadata = FrameCameraMetadata(
            iso: "--",
            shutter: "--",
            aperture: "--",
            whiteBalance: "--"
        )
    ) {
        self.url = url
        self.loops = loops
        self.playsInRealtime = playsInRealtime
        self.colorEncodingHint = colorEncodingHint
        self.metadata = metadata
    }

    func start() async throws {
        task?.cancel()

        let asset = AVURLAsset(url: url)
        // start() 先建立 format，保证 UI 状态栏在第一帧到来前也能显示
        // 分辨率、帧率和初步色彩编码；真正的帧读取放进后台 task。
        let videoTrack = try await loadVideoTrack(from: asset)
        let resolvedFormat = try await makeFormat(videoTrack: videoTrack)
        format = resolvedFormat
        status = .running

        task = Task { [weak self] in
            guard let self else { return }
            await self.readLoop(asset: asset, videoTrack: videoTrack, resolvedFormat: resolvedFormat)
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
            // 与 SimulatedFrameSource 保持同一消费模型：Session 或测试先拿 stream，
            // start() 后后台任务持续 yield。后续切换真实 live view 时 UI 不需要改结构。
            self.continuation = continuation
        }
    }

    private func readLoop(
        asset: AVAsset,
        videoTrack: AVAssetTrack,
        resolvedFormat: FrameFormat
    ) async {
        var sequence = 0

        repeat {
            do {
                let readerBundle = try makeReader(asset: asset, videoTrack: videoTrack)
                readerBundle.reader.startReading()
                var previousTimestamp: CMTime?

                while !Task.isCancelled, let sampleBuffer = readerBundle.output.copyNextSampleBuffer() {
                    // AVAssetReaderTrackOutput 会把压缩视频解码成 CMSampleBuffer；
                    // 阶段 2 的媒体边界只接受其中的 CVPixelBuffer，不把 AVPlayer 或 UI 类型泄漏出去。
                    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                        throw SourceError.noPixelBuffer
                    }

                    let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                    await waitIfNeeded(previousTimestamp: previousTimestamp, timestamp: timestamp)
                    previousTimestamp = timestamp
                    sequence += 1

                    continuation?.yield(VideoFrame(
                        sequence: sequence,
                        timestamp: timestamp,
                        format: resolvedFormat,
                        pixelBuffer: pixelBuffer,
                        metadata: metadata
                    ))
                }

                if readerBundle.reader.status == .failed {
                    throw SourceError.readingFailed(readerBundle.reader.error?.localizedDescription ?? "unknown error")
                }
            } catch {
                // 失败时结束 stream，让调用方不会永远 await 下一帧；UI 层可以根据 status
                // 决定展示短提示或回退到 SimulatedFrameSource。
                status = .failed(error.localizedDescription)
                continuation?.finish()
                return
            }
        } while loops && !Task.isCancelled

        if !Task.isCancelled {
            status = .stopped
            continuation?.finish()
        }
    }

    private func loadVideoTrack(from asset: AVAsset) async throws -> AVAssetTrack {
        let tracks = try await asset.loadTracks(withMediaType: .video)

        guard let track = tracks.first else {
            throw SourceError.missingVideoTrack
        }

        return track
    }

    private func makeReader(
        asset: AVAsset,
        videoTrack: AVAssetTrack
    ) throws -> (reader: AVAssetReader, output: AVAssetReaderTrackOutput) {
        let reader: AVAssetReader

        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            throw SourceError.readerCreationFailed(error.localizedDescription)
        }

        // 暂时强制 BGRA 输出，让阶段 3 的 CVMetalTextureCache 桥接路径先稳定。
        // HLG / N-Log 的真实颜色解释后续在 ColorTransformPass 中处理，而不是在帧源里做。
        let outputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]
        let output = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: outputSettings)
        output.alwaysCopiesSampleData = false

        guard reader.canAdd(output) else {
            throw SourceError.outputNotAccepted
        }

        reader.add(output)
        return (reader, output)
    }

    private func makeFormat(videoTrack: AVAssetTrack) async throws -> FrameFormat {
        let naturalSize = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        let nominalFrameRate = Double(try await videoTrack.load(.nominalFrameRate))
        let minFrameDuration = try await videoTrack.load(.minFrameDuration)
        let transformedSize = naturalSize.applying(preferredTransform)
        let width = abs(transformedSize.width) > 0 ? abs(transformedSize.width) : abs(naturalSize.width)
        let height = abs(transformedSize.height) > 0 ? abs(transformedSize.height) : abs(naturalSize.height)
        let fallbackFrameRate = minFrameDuration.seconds > 0 ? 1 / minFrameDuration.seconds : 30

        let colorEncoding: SourceColorEncoding
        if let colorEncodingHint {
            colorEncoding = colorEncodingHint
        } else {
            colorEncoding = try await inferColorEncoding(videoTrack: videoTrack)
        }

        return FrameFormat(
            resolution: CGSize(width: width, height: height),
            frameRate: nominalFrameRate > 0 ? nominalFrameRate : fallbackFrameRate,
            colorEncoding: colorEncoding
        )
    }

    private func inferColorEncoding(videoTrack: AVAssetTrack) async throws -> SourceColorEncoding {
        let filename = url.lastPathComponent.uppercased()

        // 本地 material/ 约定使用 REC709/NLOG/HLG 命名；先尊重文件名能让真实素材
        // 在 metadata 不完整或机内标记不统一时仍进入正确的阶段 5 验证路径。
        if filename.contains("NLOG") || filename.contains("N-LOG") {
            return .nLog
        }

        if filename.contains("HLG") {
            return .hlg
        }

        if filename.contains("REC709") || filename.contains("REC.709") {
            return .rec709
        }

        let formatDescriptions = try await videoTrack.load(.formatDescriptions)

        for formatDescription in formatDescriptions {
            guard let extensions = CMFormatDescriptionGetExtensions(formatDescription) as? [String: Any] else {
                continue
            }

            let transferFunction = extensions[kCMFormatDescriptionExtension_TransferFunction as String] as? String
            let colorPrimaries = extensions[kCMFormatDescriptionExtension_ColorPrimaries as String] as? String

            if transferFunction == kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG as String {
                return .hlg
            }

            if colorPrimaries == kCMFormatDescriptionColorPrimaries_ITU_R_709_2 as String {
                return .rec709
            }
        }

        return .rec709
    }

    private func waitIfNeeded(previousTimestamp: CMTime?, timestamp: CMTime) async {
        guard playsInRealtime, let previousTimestamp else { return }

        let delta = timestamp - previousTimestamp
        guard delta.isNumeric, delta.seconds > 0 else { return }

        // 这里根据 sample 的 presentation timestamp 控制推送节奏，而不是依赖 AVPlayer。
        // 测试可以关闭 playsInRealtime，快速读取临时生成的视频 fixture。
        let nanoseconds = UInt64((delta.seconds * 1_000_000_000).rounded())
        try? await Task.sleep(nanoseconds: nanoseconds)
    }
}
