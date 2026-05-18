import CoreGraphics
import CoreVideo
import Foundation
import Metal
import MetalKit

final class MetalPreviewRenderer: NSObject, MTKViewDelegate {
    enum RendererError: Error, LocalizedError {
        case commandQueueCreationFailed
        case defaultLibraryMissing
        case shaderFunctionMissing(String)

        var errorDescription: String? {
            switch self {
            case .commandQueueCreationFailed:
                return "无法创建 Metal command queue"
            case .defaultLibraryMissing:
                return "找不到默认 Metal shader library"
            case let .shaderFunctionMissing(name):
                return "找不到 Metal shader function：\(name)"
            }
        }
    }

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let textureBridge: MetalTextureBridge
    private let lutStore: LUTStore
    private let lutPass: LUTPass
    private let frameProcessor: MetalFrameProcessor
    private let pipelineState: MTLRenderPipelineState
    private let samplerState: MTLSamplerState
    private let lutSamplerState: MTLSamplerState
    private let frameLock = NSLock()

    private var latestFrame = VideoFrame.placeholder
    private var monitorState = MonitorState.initial
    private var zoomMode: ZoomMode = .fit
    private var lutState = LUTState.initial
    private var lastRenderedSequence: Int?
    var scopeDataHandler: ((ScopeData) -> Void)?

    init(device: MTLDevice, colorPixelFormat: MTLPixelFormat, lutStore: LUTStore) throws {
        self.device = device
        self.lutStore = lutStore

        guard let commandQueue = device.makeCommandQueue() else {
            throw RendererError.commandQueueCreationFailed
        }

        let textureBridge = try MetalTextureBridge(device: device)
        let lutPass = LUTPass(device: device)

        guard let library = device.makeDefaultLibrary() else {
            throw RendererError.defaultLibraryMissing
        }

        guard let vertexFunction = library.makeFunction(name: "previewVertex") else {
            throw RendererError.shaderFunctionMissing("previewVertex")
        }

        guard let fragmentFunction = library.makeFunction(name: "previewFragment") else {
            throw RendererError.shaderFunctionMissing("previewFragment")
        }

        let frameProcessor = try MetalFrameProcessor(device: device, library: library)

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.label = "PrismBlade Preview Pipeline"
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = colorPixelFormat

        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.mipFilter = .notMipmapped
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        samplerDescriptor.rAddressMode = .clampToEdge

        guard let samplerState = device.makeSamplerState(descriptor: samplerDescriptor) else {
            throw RendererError.commandQueueCreationFailed
        }

        let lutSamplerDescriptor = MTLSamplerDescriptor()
        lutSamplerDescriptor.minFilter = .linear
        lutSamplerDescriptor.magFilter = .linear
        lutSamplerDescriptor.mipFilter = .notMipmapped
        lutSamplerDescriptor.sAddressMode = .clampToEdge
        lutSamplerDescriptor.tAddressMode = .clampToEdge
        lutSamplerDescriptor.rAddressMode = .clampToEdge

        guard let lutSamplerState = device.makeSamplerState(descriptor: lutSamplerDescriptor) else {
            throw RendererError.commandQueueCreationFailed
        }

        self.commandQueue = commandQueue
        self.textureBridge = textureBridge
        self.lutPass = lutPass
        self.frameProcessor = frameProcessor
        self.pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        self.samplerState = samplerState
        self.lutSamplerState = lutSamplerState

        super.init()
    }

    func update(frame: VideoFrame, monitor: MonitorState, lut: LUTState) {
        frameLock.lock()
        latestFrame = frame
        monitorState = monitor
        zoomMode = monitor.zoomMode
        lutState = lut
        frameLock.unlock()
    }

    func draw(in view: MTKView) {
        let renderSnapshot = snapshot()

        guard let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            return
        }

        do {
            let sourceTexture = try textureBridge.makeTexture(from: renderSnapshot.frame.pixelBuffer)
            let lutRenderState = resolveLUTRenderState(from: renderSnapshot.lut)
            frameProcessor.encodeScopeIfNeeded(
                sourceTexture: sourceTexture,
                frame: renderSnapshot.frame,
                monitor: renderSnapshot.monitor,
                commandBuffer: commandBuffer
            ) { [weak self] scopeData in
                self?.scopeDataHandler?(scopeData)
            }

            guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
                return
            }

            renderEncoder.label = "PrismBlade Preview Encoder"
            renderEncoder.setRenderPipelineState(pipelineState)
            renderEncoder.setViewport(Self.viewport(
                sourceSize: CGSize(width: sourceTexture.width, height: sourceTexture.height),
                drawableSize: view.drawableSize,
                zoomMode: renderSnapshot.zoomMode
            ))
            renderEncoder.setFragmentTexture(sourceTexture, index: 0)
            renderEncoder.setFragmentTexture(lutRenderState.resource.texture, index: 1)
            renderEncoder.setFragmentSamplerState(samplerState, index: 0)
            renderEncoder.setFragmentSamplerState(lutSamplerState, index: 1)
            let lutUniforms = Self.makeLUTUniforms(
                resource: lutRenderState.resource,
                isEnabled: lutRenderState.isEnabled,
                intensity: renderSnapshot.lut.intensity
            )
            lutUniforms.withUnsafeBytes { bytes in
                renderEncoder.setFragmentBytes(bytes.baseAddress!, length: bytes.count, index: 0)
            }
            let monitorUniforms = Self.makeMonitorUniforms(
                monitor: renderSnapshot.monitor,
                format: renderSnapshot.frame.format
            )
            monitorUniforms.withUnsafeBytes { bytes in
                renderEncoder.setFragmentBytes(bytes.baseAddress!, length: bytes.count, index: 1)
            }
            renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            renderEncoder.endEncoding()

            commandBuffer.present(drawable)
            commandBuffer.commit()
            lastRenderedSequence = renderSnapshot.frame.sequence
        } catch {
            clear(drawable: drawable, renderPassDescriptor: renderPassDescriptor, commandBuffer: commandBuffer)
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        textureBridge.flush()
    }

    private func snapshot() -> RenderSnapshot {
        frameLock.lock()
        let snapshot = RenderSnapshot(
            frame: latestFrame,
            monitor: monitorState,
            zoomMode: zoomMode,
            lut: lutState
        )
        frameLock.unlock()
        return snapshot
    }

    private func resolveLUTRenderState(from lut: LUTState) -> LUTRenderState {
        let fallback = (try? lutPass.fallbackResource()) ?? LUTTextureResource(
            texture: makeEmergencyFallbackTexture(),
            cubeSize: 2,
            domainMin: SIMD3<Float>(0, 0, 0),
            domainMax: SIMD3<Float>(1, 1, 1)
        )

        guard lut.isEnabled,
              lut.intensity > 0,
              let descriptor = lut.selectedLUT,
              let resource = try? lutPass.textureResource(for: descriptor, store: lutStore) else {
            return LUTRenderState(resource: fallback, isEnabled: false)
        }

        return LUTRenderState(resource: resource, isEnabled: true)
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
                0
            )
        ]
    }

    private func clear(
        drawable: CAMetalDrawable,
        renderPassDescriptor: MTLRenderPassDescriptor,
        commandBuffer: MTLCommandBuffer
    ) {
        guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }

        renderEncoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private static func viewport(
        sourceSize: CGSize,
        drawableSize: CGSize,
        zoomMode: ZoomMode
    ) -> MTLViewport {
        let drawableWidth = max(Double(drawableSize.width), 1)
        let drawableHeight = max(Double(drawableSize.height), 1)
        let sourceWidth = max(Double(sourceSize.width), 1)
        let sourceHeight = max(Double(sourceSize.height), 1)
        let scale: Double

        switch zoomMode {
        case .fit:
            scale = min(drawableWidth / sourceWidth, drawableHeight / sourceHeight)
        case .fill:
            scale = max(drawableWidth / sourceWidth, drawableHeight / sourceHeight)
        case .oneX:
            scale = 1
        case .twoX:
            scale = 2
        }

        let width = sourceWidth * scale
        let height = sourceHeight * scale
        return MTLViewport(
            originX: (drawableWidth - width) / 2,
            originY: (drawableHeight - height) / 2,
            width: width,
            height: height,
            znear: 0,
            zfar: 1
        )
    }
}

private struct RenderSnapshot {
    var frame: VideoFrame
    var monitor: MonitorState
    var zoomMode: ZoomMode
    var lut: LUTState
}

private struct LUTRenderState {
    var resource: LUTTextureResource
    var isEnabled: Bool
}
