@testable import PrismBlade
import Metal
import XCTest

final class MetalLUTShaderTests: XCTestCase {
    func testPreviewShaderAppliesLUTIntensityMix() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal is not available in this test environment")
        }

        guard let commandQueue = device.makeCommandQueue() else {
            XCTFail("Unable to create command queue")
            return
        }

        guard let library = device.makeDefaultLibrary(),
              let vertexFunction = library.makeFunction(name: "previewVertex"),
              let fragmentFunction = library.makeFunction(name: "previewFragment") else {
            throw XCTSkip("Preview shader library is not available in this test environment")
        }

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = .rgba32Float
        let pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)

        let sourceColor = SIMD3<Float>(0.25, 0.5, 0.75)
        let parsed = try LUTParser().parse(CubeFixtureFactory.redChannelRamp(size: 2))
        let lutResource = try LUTPass(device: device).makeTextureResource(from: parsed)

        let noMix = try render(
            device: device,
            commandQueue: commandQueue,
            pipelineState: pipelineState,
            sourceColor: sourceColor,
            lutResource: lutResource,
            intensity: 0
        )
        let halfMix = try render(
            device: device,
            commandQueue: commandQueue,
            pipelineState: pipelineState,
            sourceColor: sourceColor,
            lutResource: lutResource,
            intensity: 0.5
        )
        let fullMix = try render(
            device: device,
            commandQueue: commandQueue,
            pipelineState: pipelineState,
            sourceColor: sourceColor,
            lutResource: lutResource,
            intensity: 1
        )

        XCTAssertEqual(noMix.x, sourceColor.x, accuracy: 0.02)
        XCTAssertEqual(noMix.y, sourceColor.y, accuracy: 0.02)
        XCTAssertEqual(noMix.z, sourceColor.z, accuracy: 0.02)

        XCTAssertEqual(halfMix.x, 0.25, accuracy: 0.02)
        XCTAssertEqual(halfMix.y, 0.25, accuracy: 0.02)
        XCTAssertEqual(halfMix.z, 0.375, accuracy: 0.02)

        XCTAssertEqual(fullMix.x, 0.25, accuracy: 0.02)
        XCTAssertEqual(fullMix.y, 0, accuracy: 0.02)
        XCTAssertEqual(fullMix.z, 0, accuracy: 0.02)
    }

    private func render(
        device: MTLDevice,
        commandQueue: MTLCommandQueue,
        pipelineState: MTLRenderPipelineState,
        sourceColor: SIMD3<Float>,
        lutResource: LUTTextureResource,
        intensity: Float
    ) throws -> SIMD3<Float> {
        let sourceTexture = makeTexture2D(device: device, pixelFormat: .rgba32Float, usage: [.shaderRead])
        var sourcePixel: [Float] = [sourceColor.x, sourceColor.y, sourceColor.z, 1]
        sourcePixel.withUnsafeBytes { bytes in
            sourceTexture.replace(
                region: MTLRegionMake2D(0, 0, 1, 1),
                mipmapLevel: 0,
                withBytes: bytes.baseAddress!,
                bytesPerRow: 4 * MemoryLayout<Float>.stride
            )
        }

        let outputTexture = makeTexture2D(device: device, pixelFormat: .rgba32Float, usage: [.renderTarget])
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = outputTexture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].storeAction = .store

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            throw XCTSkip("Unable to create offscreen render command")
        }

        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        samplerDescriptor.rAddressMode = .clampToEdge
        let samplerState = device.makeSamplerState(descriptor: samplerDescriptor)

        var uniforms = [
            SIMD4<Float>(1, intensity, Float(lutResource.cubeSize), 0),
            SIMD4<Float>(lutResource.domainMin.x, lutResource.domainMin.y, lutResource.domainMin.z, 0),
            SIMD4<Float>(lutResource.domainMax.x, lutResource.domainMax.y, lutResource.domainMax.z, 0)
        ]

        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setFragmentTexture(sourceTexture, index: 0)
        renderEncoder.setFragmentTexture(lutResource.texture, index: 1)
        renderEncoder.setFragmentSamplerState(samplerState, index: 0)
        renderEncoder.setFragmentSamplerState(samplerState, index: 1)
        uniforms.withUnsafeBytes { bytes in
            renderEncoder.setFragmentBytes(bytes.baseAddress!, length: bytes.count, index: 0)
        }
        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        renderEncoder.endEncoding()

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        var outputPixel = [Float](repeating: 0, count: 4)
        outputPixel.withUnsafeMutableBytes { bytes in
            outputTexture.getBytes(
                bytes.baseAddress!,
                bytesPerRow: 4 * MemoryLayout<Float>.stride,
                from: MTLRegionMake2D(0, 0, 1, 1),
                mipmapLevel: 0
            )
        }

        return SIMD3<Float>(outputPixel[0], outputPixel[1], outputPixel[2])
    }

    private func makeTexture2D(
        device: MTLDevice,
        pixelFormat: MTLPixelFormat,
        usage: MTLTextureUsage
    ) -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: 1,
            height: 1,
            mipmapped: false
        )
        descriptor.storageMode = .shared
        descriptor.usage = usage

        guard let texture = device.makeTexture(descriptor: descriptor) else {
            preconditionFailure("Unable to create test texture")
        }

        return texture
    }
}
