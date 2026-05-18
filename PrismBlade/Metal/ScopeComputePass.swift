import Foundation
import Metal

final class ScopeComputePass {
    enum PassError: Error, LocalizedError {
        case shaderFunctionMissing(String)
        case pipelineCreationFailed
        case bufferCreationFailed

        var errorDescription: String? {
            switch self {
            case let .shaderFunctionMissing(name):
                return "找不到 Metal compute shader function：\(name)"
            case .pipelineCreationFailed:
                return "无法创建 scope compute pipeline"
            case .bufferCreationFailed:
                return "无法创建 scope bins buffer"
            }
        }
    }

    struct Configuration: Equatable {
        var binWidth: Int
        var binHeight: Int
        var frameInterval: Int
        var maxSampleWidth: Int
        var maxSampleHeight: Int

        init(
            binWidth: Int,
            binHeight: Int,
            frameInterval: Int,
            maxSampleWidth: Int = 320,
            maxSampleHeight: Int = 180
        ) {
            self.binWidth = binWidth
            self.binHeight = binHeight
            self.frameInterval = frameInterval
            self.maxSampleWidth = maxSampleWidth
            self.maxSampleHeight = maxSampleHeight
        }

        static let `default` = Configuration(binWidth: 96, binHeight: 64, frameInterval: 3)
    }

    private let device: MTLDevice
    private let pipelineState: MTLComputePipelineState
    private let configuration: Configuration
    private let lumaBinsBuffer: MTLBuffer
    private let redBinsBuffer: MTLBuffer
    private let greenBinsBuffer: MTLBuffer
    private let blueBinsBuffer: MTLBuffer
    private let bufferLength: Int
    private let stateLock = NSLock()

    private var lastSubmittedSequence: Int?
    private var isReadbackPending = false
    private(set) var encodedPassCount = 0

    init(
        device: MTLDevice,
        library: MTLLibrary,
        configuration: Configuration = .default
    ) throws {
        self.device = device
        self.configuration = Configuration(
            binWidth: max(configuration.binWidth, 1),
            binHeight: max(configuration.binHeight, 1),
            frameInterval: max(configuration.frameInterval, 1),
            maxSampleWidth: max(configuration.maxSampleWidth, 1),
            maxSampleHeight: max(configuration.maxSampleHeight, 1)
        )

        guard let function = library.makeFunction(name: "scopeCompute") else {
            throw PassError.shaderFunctionMissing("scopeCompute")
        }

        do {
            pipelineState = try device.makeComputePipelineState(function: function)
        } catch {
            throw PassError.pipelineCreationFailed
        }

        bufferLength = self.configuration.binWidth *
            self.configuration.binHeight *
            MemoryLayout<UInt32>.stride

        guard let lumaBinsBuffer = device.makeBuffer(length: bufferLength, options: .storageModeShared),
              let redBinsBuffer = device.makeBuffer(length: bufferLength, options: .storageModeShared),
              let greenBinsBuffer = device.makeBuffer(length: bufferLength, options: .storageModeShared),
              let blueBinsBuffer = device.makeBuffer(length: bufferLength, options: .storageModeShared) else {
            throw PassError.bufferCreationFailed
        }

        self.lumaBinsBuffer = lumaBinsBuffer
        self.redBinsBuffer = redBinsBuffer
        self.greenBinsBuffer = greenBinsBuffer
        self.blueBinsBuffer = blueBinsBuffer
    }

    @discardableResult
    func encodeIfNeeded(
        sourceTexture: MTLTexture,
        lutTexture: MTLTexture,
        lutSamplerState: MTLSamplerState,
        lutUniforms: [SIMD4<Float>],
        frame: VideoFrame,
        monitor: MonitorState,
        commandBuffer: MTLCommandBuffer,
        completion: @escaping (ScopeData) -> Void
    ) -> Bool {
        guard beginSubmissionIfNeeded(sequence: frame.sequence, monitor: monitor) else {
            return false
        }

        clearBins(on: commandBuffer)

        guard let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
            finishSubmission()
            return false
        }

        computeEncoder.label = "PrismBlade Scope Compute Encoder"
        computeEncoder.setComputePipelineState(pipelineState)
        computeEncoder.setTexture(sourceTexture, index: 0)
        computeEncoder.setTexture(lutTexture, index: 1)
        computeEncoder.setSamplerState(lutSamplerState, index: 0)
        computeEncoder.setBuffer(lumaBinsBuffer, offset: 0, index: 0)
        computeEncoder.setBuffer(redBinsBuffer, offset: 0, index: 1)
        computeEncoder.setBuffer(greenBinsBuffer, offset: 0, index: 2)
        computeEncoder.setBuffer(blueBinsBuffer, offset: 0, index: 3)

        let sampleWidth = min(sourceTexture.width, configuration.maxSampleWidth)
        let sampleHeight = min(sourceTexture.height, configuration.maxSampleHeight)
        let uniforms = [
            SIMD4<Float>(
                Float(configuration.binWidth),
                Float(configuration.binHeight),
                ColorTransformPass.encodingCode(for: frame.format.colorEncoding),
                exposureAnalysisSourceCode(for: monitor.exposureAnalysisSource)
            ),
            SIMD4<Float>(
                Float(sourceTexture.width),
                Float(sourceTexture.height),
                Float(sampleWidth),
                Float(sampleHeight)
            )
        ]
        uniforms.withUnsafeBytes { bytes in
            computeEncoder.setBytes(bytes.baseAddress!, length: bytes.count, index: 4)
        }
        lutUniforms.withUnsafeBytes { bytes in
            computeEncoder.setBytes(bytes.baseAddress!, length: bytes.count, index: 5)
        }

        let width = pipelineState.threadExecutionWidth
        let height = max(pipelineState.maxTotalThreadsPerThreadgroup / max(width, 1), 1)
        let threadsPerThreadgroup = MTLSize(width: width, height: height, depth: 1)
        let threadgroupsPerGrid = MTLSize(
            width: Self.threadgroupCount(for: sampleWidth, threadsPerThreadgroup: threadsPerThreadgroup.width),
            height: Self.threadgroupCount(for: sampleHeight, threadsPerThreadgroup: threadsPerThreadgroup.height),
            depth: 1
        )
        computeEncoder.dispatchThreadgroups(threadgroupsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        computeEncoder.endEncoding()

        commandBuffer.addCompletedHandler { [weak self] _ in
            guard let self else { return }
            let scopeData = self.makeScopeData(sourceSequence: frame.sequence)
            self.finishSubmission()
            completion(scopeData)
        }

        return true
    }

    private func beginSubmissionIfNeeded(sequence: Int, monitor: MonitorState) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }

        guard monitor.scopeMode != .off, !isReadbackPending else {
            return false
        }

        if let lastSubmittedSequence,
           sequence - lastSubmittedSequence < configuration.frameInterval {
            return false
        }

        isReadbackPending = true
        lastSubmittedSequence = sequence
        encodedPassCount += 1
        return true
    }

    private func finishSubmission() {
        stateLock.lock()
        isReadbackPending = false
        stateLock.unlock()
    }

    private func clearBins(on commandBuffer: MTLCommandBuffer) {
        guard let blitEncoder = commandBuffer.makeBlitCommandEncoder() else { return }
        for buffer in [lumaBinsBuffer, redBinsBuffer, greenBinsBuffer, blueBinsBuffer] {
            blitEncoder.fill(buffer: buffer, range: 0..<bufferLength, value: 0)
        }
        blitEncoder.endEncoding()
    }

    private static func threadgroupCount(for threadCount: Int, threadsPerThreadgroup: Int) -> Int {
        (threadCount + threadsPerThreadgroup - 1) / threadsPerThreadgroup
    }

    private func makeScopeData(sourceSequence: Int) -> ScopeData {
        ScopeData(
            lumaBins: normalizedBins(from: lumaBinsBuffer),
            redBins: normalizedBins(from: redBinsBuffer),
            greenBins: normalizedBins(from: greenBinsBuffer),
            blueBins: normalizedBins(from: blueBinsBuffer),
            binWidth: configuration.binWidth,
            binHeight: configuration.binHeight,
            sourceSequence: sourceSequence
        )
    }

    private func normalizedBins(from buffer: MTLBuffer) -> [Float] {
        let count = configuration.binWidth * configuration.binHeight
        let pointer = buffer.contents().bindMemory(to: UInt32.self, capacity: count)
        var values = [UInt32]()
        values.reserveCapacity(count)

        var maximum: UInt32 = 0
        for index in 0..<count {
            let value = pointer[index]
            values.append(value)
            maximum = max(maximum, value)
        }

        guard maximum > 0 else {
            return Array(repeating: 0, count: count)
        }

        let scale = Float(maximum)
        return values.map { Float($0) / scale }
    }

    private func exposureAnalysisSourceCode(for source: ExposureAnalysisSource) -> Float {
        switch source {
        case .rawSignal:
            return 0
        case .previewDisplay:
            return 1
        }
    }
}
