import Metal

final class MetalFrameProcessor {
    struct RenderState {
        var lutResource: LUTTextureResource
        var isLUTApplied: Bool
        var lutUniforms: [SIMD4<Float>]
        var monitorUniforms: [SIMD4<Float>]
        var lutSamplerState: MTLSamplerState
    }

    enum ProcessorError: Error, LocalizedError {
        case samplerCreationFailed

        var errorDescription: String? {
            switch self {
            case .samplerCreationFailed:
                return "无法创建 Metal LUT sampler"
            }
        }
    }

    private let device: MTLDevice
    private let lutStore: LUTStore
    private let lutPass: LUTPass
    private let scopeComputePass: ScopeComputePass
    private let lutSamplerState: MTLSamplerState

    init(device: MTLDevice, library: MTLLibrary, lutStore: LUTStore) throws {
        self.device = device
        self.lutStore = lutStore
        lutPass = LUTPass(device: device)
        scopeComputePass = try ScopeComputePass(device: device, library: library)

        let lutSamplerDescriptor = MTLSamplerDescriptor()
        lutSamplerDescriptor.minFilter = .linear
        lutSamplerDescriptor.magFilter = .linear
        lutSamplerDescriptor.mipFilter = .notMipmapped
        lutSamplerDescriptor.sAddressMode = .clampToEdge
        lutSamplerDescriptor.tAddressMode = .clampToEdge
        lutSamplerDescriptor.rAddressMode = .clampToEdge

        guard let lutSamplerState = device.makeSamplerState(descriptor: lutSamplerDescriptor) else {
            throw ProcessorError.samplerCreationFailed
        }

        self.lutSamplerState = lutSamplerState
    }

    func makeRenderState(
        frame: VideoFrame,
        monitor: MonitorState,
        lut: LUTState
    ) -> RenderState {
        let lutRenderState = resolveLUTRenderState(frame: frame, lut: lut)
        return RenderState(
            lutResource: lutRenderState.resource,
            isLUTApplied: lutRenderState.isApplied,
            lutUniforms: Self.makeLUTUniforms(
                resource: lutRenderState.resource,
                isEnabled: lutRenderState.isApplied,
                intensity: lut.intensity
            ),
            monitorUniforms: Self.makeMonitorUniforms(monitor: monitor, format: frame.format),
            lutSamplerState: lutSamplerState
        )
    }

    @discardableResult
    func encodeScopeIfNeeded(
        sourceTexture: MTLTexture,
        frame: VideoFrame,
        monitor: MonitorState,
        renderState: RenderState,
        commandBuffer: MTLCommandBuffer,
        completion: @escaping (ScopeData) -> Void
    ) -> Bool {
        scopeComputePass.encodeIfNeeded(
            sourceTexture: sourceTexture,
            lutTexture: renderState.lutResource.texture,
            lutSamplerState: renderState.lutSamplerState,
            lutUniforms: renderState.lutUniforms,
            frame: frame,
            monitor: monitor,
            commandBuffer: commandBuffer,
            completion: completion
        )
    }

    private func resolveLUTRenderState(frame: VideoFrame, lut: LUTState) -> LUTRenderState {
        let fallback = (try? lutPass.fallbackResource()) ?? LUTTextureResource(
            texture: makeEmergencyFallbackTexture(),
            cubeSize: 1,
            domainMin: SIMD3<Float>(0, 0, 0),
            domainMax: SIMD3<Float>(1, 1, 1)
        )

        guard frame.format.colorEncoding == .nLog,
              lut.isEnabled,
              lut.intensity > 0,
              let descriptor = lut.selectedLUT,
              let resource = try? lutPass.textureResource(for: descriptor, store: lutStore) else {
            return LUTRenderState(resource: fallback, isApplied: false)
        }

        return LUTRenderState(resource: resource, isApplied: true)
    }

    private func makeEmergencyFallbackTexture() -> MTLTexture {
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type3D
        descriptor.pixelFormat = .rgba32Float
        descriptor.width = 1
        descriptor.height = 1
        descriptor.depth = 1
        descriptor.mipmapLevelCount = 1
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .shared

        guard let texture = device.makeTexture(descriptor: descriptor) else {
            preconditionFailure("Unable to create fallback LUT texture")
        }

        let pixel: [Float] = [0, 0, 0, 1]
        pixel.withUnsafeBytes { bytes in
            texture.replace(
                region: MTLRegionMake3D(0, 0, 0, 1, 1, 1),
                mipmapLevel: 0,
                slice: 0,
                withBytes: bytes.baseAddress!,
                bytesPerRow: 4 * MemoryLayout<Float>.stride,
                bytesPerImage: 4 * MemoryLayout<Float>.stride
            )
        }
        return texture
    }

    private static func makeLUTUniforms(
        resource: LUTTextureResource,
        isEnabled: Bool,
        intensity: Double
    ) -> [SIMD4<Float>] {
        [
            SIMD4<Float>(
                isEnabled ? 1 : 0,
                min(max(Float(intensity), 0), 1),
                Float(resource.cubeSize),
                0
            ),
            SIMD4<Float>(resource.domainMin.x, resource.domainMin.y, resource.domainMin.z, 0),
            SIMD4<Float>(resource.domainMax.x, resource.domainMax.y, resource.domainMax.z, 0)
        ]
    }

    private static func makeMonitorUniforms(
        monitor: MonitorState,
        format: FrameFormat
    ) -> [SIMD4<Float>] {
        [
            SIMD4<Float>(
                ColorTransformPass.encodingCode(for: format.colorEncoding),
                FalseColorPass.enabledFlag(for: monitor),
                ZebraPass.enabledFlag(for: monitor),
                ZebraPass.modeCode(for: monitor.zebraMode)
            ),
            SIMD4<Float>(
                ZebraPass.thresholdFraction(for: monitor),
                0.4,
                0.6,
                ExposureAnalysisPass.sourceCode(for: monitor.exposureAnalysisSource)
            )
        ]
    }
}

private struct LUTRenderState {
    var resource: LUTTextureResource
    var isApplied: Bool
}

private enum ExposureAnalysisPass {
    static func sourceCode(for source: ExposureAnalysisSource) -> Float {
        switch source {
        case .rawSignal:
            return 0
        case .previewDisplay:
            return 1
        }
    }
}
