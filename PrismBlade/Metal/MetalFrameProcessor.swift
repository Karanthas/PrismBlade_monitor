import Metal

final class MetalFrameProcessor {
    private let scopeComputePass: ScopeComputePass

    init(device: MTLDevice, library: MTLLibrary) throws {
        scopeComputePass = try ScopeComputePass(device: device, library: library)
    }

    @discardableResult
    func encodeScopeIfNeeded(
        sourceTexture: MTLTexture,
        frame: VideoFrame,
        monitor: MonitorState,
        commandBuffer: MTLCommandBuffer,
        completion: @escaping (ScopeData) -> Void
    ) -> Bool {
        scopeComputePass.encodeIfNeeded(
            sourceTexture: sourceTexture,
            frame: frame,
            monitor: monitor,
            commandBuffer: commandBuffer,
            completion: completion
        )
    }
}
