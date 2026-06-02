import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation

final class NikonLiveViewFrameSource: FrameSource, FrameSourceConnectionLossReporting {
    private(set) var status: FrameSourceStatus = .stopped
    private(set) var format: FrameFormat?
    private(set) var didFailFromConnectionLoss = false

    private let runtime: NikonLiveViewRuntime
    private let payloadParser: NikonLiveViewPayloadParser
    private let decoder: JPEGPixelBufferDecoder
    private let nominalFrameRate: Double
    private let metadata: FrameCameraMetadata
    private let sessionState = NikonLiveViewFrameSourceSessionState()

    private var continuation: AsyncStream<VideoFrame>.Continuation?
    private var task: Task<Void, Never>?
    private var sequence = 0

    init(
        runtime: NikonLiveViewRuntime,
        payloadParser: NikonLiveViewPayloadParser = NikonLiveViewPayloadParser(),
        decoder: JPEGPixelBufferDecoder = JPEGPixelBufferDecoder(),
        nominalFrameRate: Double = 30,
        metadata: FrameCameraMetadata = FrameCameraMetadata(iso: "-", shutter: "-", aperture: "-", whiteBalance: "-")
    ) {
        self.runtime = runtime
        self.payloadParser = payloadParser
        self.decoder = decoder
        self.nominalFrameRate = nominalFrameRate
        self.metadata = metadata
    }

    func start() async throws {
        task?.cancel()
        task = nil
        status = .running
        didFailFromConnectionLoss = false
        sequence = 0

        try await runtime.startLiveViewSession()
        await sessionState.begin()

        task = Task { [weak self] in
            await self?.runFrameLoop()
        }
    }

    func stop() async {
        task?.cancel()
        task = nil
        await cleanupLiveViewIfNeeded()
        status = .stopped
        continuation?.finish()
    }

    func frames() -> AsyncStream<VideoFrame> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            self.continuation = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.streamTerminated() }
            }
        }
    }

    private func runFrameLoop() async {
        while !Task.isCancelled {
            do {
                let payload = try await runtime.fetchLiveViewPayload()
                let jpegData = try payloadParser.extractJPEG(from: payload)
                let pixelBuffer = try decoder.decode(jpegData)
                sequence += 1

                let currentFormat = FrameFormat(
                    resolution: CGSize(
                        width: CVPixelBufferGetWidth(pixelBuffer),
                        height: CVPixelBufferGetHeight(pixelBuffer)
                    ),
                    frameRate: nominalFrameRate,
                    colorEncoding: .rec709
                )
                format = currentFormat

                continuation?.yield(VideoFrame(
                    sequence: sequence,
                    timestamp: Self.timestamp(for: sequence, frameRate: currentFormat.frameRate),
                    format: currentFormat,
                    pixelBuffer: pixelBuffer,
                    metadata: metadata
                ))
            } catch is CancellationError {
                break
            } catch {
                didFailFromConnectionLoss = Self.isConnectionLoss(error)
                status = .failed(error.localizedDescription)
                continuation?.finish()
                break
            }
        }

        await cleanupLiveViewIfNeeded()
    }

    private func cleanupLiveViewIfNeeded() async {
        guard await sessionState.claimCleanup() else { return }
        _ = try? await runtime.endLiveViewSession()
    }

    private func streamTerminated() async {
        task?.cancel()
        task = nil
        await cleanupLiveViewIfNeeded()
    }

    private static func timestamp(for sequence: Int, frameRate: Double) -> CMTime {
        let timescale = max(Int32(frameRate.rounded()), 1)
        return CMTime(value: CMTimeValue(sequence), timescale: timescale)
    }

    private static func isConnectionLoss(_ error: Error) -> Bool {
        if let discoveryError = error as? NikonCameraDiscoveryError {
            switch discoveryError {
            case .noCamera, .missingPTPCapability:
                return true
            case .authorizationDenied, .unsupportedCamera:
                return false
            }
        }

        if let runtimeError = error as? NikonCameraRuntimeError {
            if case .notConnected = runtimeError {
                return true
            }
        }

        if let clientError = error as? PTPClientError {
            switch clientError {
            case .missingPTPCapability, .timeout, .timedOutOperationStillInFlight, .transactionMismatch:
                return true
            case .responseError:
                return false
            }
        }

        return false
    }
}

private actor NikonLiveViewFrameSourceSessionState {
    private var active = false
    private var cleanupClaimed = false

    func begin() {
        active = true
        cleanupClaimed = false
    }

    func claimCleanup() -> Bool {
        guard active, !cleanupClaimed else { return false }
        active = false
        cleanupClaimed = true
        return true
    }
}
