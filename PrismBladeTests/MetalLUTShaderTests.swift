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

    func testPreviewShaderLeavesNLogRawWhenLUTDisabled() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal is not available in this test environment")
        }

        guard let commandQueue = device.makeCommandQueue(),
              let pipelineState = try makePipelineState(device: device) else {
            throw XCTSkip("Unable to create Metal pipeline")
        }

        let lutResource = try LUTPass(device: device).fallbackResource()
        let output = try render(
            device: device,
            commandQueue: commandQueue,
            pipelineState: pipelineState,
            sourceColor: SIMD3<Float>(repeating: 0.36366777),
            lutResource: lutResource,
            intensity: 0,
            colorEncoding: .nLog,
            lutEnabled: false
        )

        XCTAssertEqual(output.x, 0.36366777, accuracy: 0.02)
        XCTAssertEqual(output.y, 0.36366777, accuracy: 0.02)
        XCTAssertEqual(output.z, 0.36366777, accuracy: 0.02)
    }

    func testPreviewShaderSamplesNLogLUTWithRawInput() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal is not available in this test environment")
        }

        guard let commandQueue = device.makeCommandQueue(),
              let pipelineState = try makePipelineState(device: device) else {
            throw XCTSkip("Unable to create Metal pipeline")
        }

        let parsed = try LUTParser().parse(CubeFixtureFactory.redChannelRamp(size: 2))
        let lutResource = try LUTPass(device: device).makeTextureResource(from: parsed)
        let output = try render(
            device: device,
            commandQueue: commandQueue,
            pipelineState: pipelineState,
            sourceColor: SIMD3<Float>(repeating: 0.7),
            lutResource: lutResource,
            intensity: 1,
            colorEncoding: .nLog
        )

        XCTAssertEqual(output.x, 0.7, accuracy: 0.03)
        XCTAssertEqual(output.y, 0, accuracy: 0.02)
        XCTAssertEqual(output.z, 0, accuracy: 0.02)
    }

    func testPreviewShaderMixesNLogRawInputWithLUTOutput() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal is not available in this test environment")
        }

        guard let commandQueue = device.makeCommandQueue(),
              let pipelineState = try makePipelineState(device: device) else {
            throw XCTSkip("Unable to create Metal pipeline")
        }

        let parsed = try LUTParser().parse(CubeFixtureFactory.redChannelRamp(size: 2))
        let lutResource = try LUTPass(device: device).makeTextureResource(from: parsed)
        let output = try render(
            device: device,
            commandQueue: commandQueue,
            pipelineState: pipelineState,
            sourceColor: SIMD3<Float>(repeating: 0.7),
            lutResource: lutResource,
            intensity: 0.5,
            colorEncoding: .nLog
        )

        XCTAssertEqual(output.x, 0.7, accuracy: 0.03)
        XCTAssertEqual(output.y, 0.35, accuracy: 0.03)
        XCTAssertEqual(output.z, 0.35, accuracy: 0.03)
    }

    func testPreviewShaderMapsGeneratedGrayRampToFalseColorBand() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal is not available in this test environment")
        }

        guard let commandQueue = device.makeCommandQueue(),
              let pipelineState = try makePipelineState(device: device) else {
            throw XCTSkip("Unable to create Metal pipeline")
        }

        let lutResource = try LUTPass(device: device).fallbackResource()
        let output = try render(
            device: device,
            commandQueue: commandQueue,
            pipelineState: pipelineState,
            sourceColor: SIMD3<Float>(repeating: 0.5),
            lutResource: lutResource,
            intensity: 0,
            falseColorEnabled: true
        )

        XCTAssertEqual(output.x, 0.10, accuracy: 0.03)
        XCTAssertEqual(output.y, 0.86, accuracy: 0.03)
        XCTAssertEqual(output.z, 0.26, accuracy: 0.03)
    }

    func testPreviewShaderAppliesZebraOnlyAboveThreshold() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal is not available in this test environment")
        }

        guard let commandQueue = device.makeCommandQueue(),
              let pipelineState = try makePipelineState(device: device) else {
            throw XCTSkip("Unable to create Metal pipeline")
        }

        let lutResource = try LUTPass(device: device).fallbackResource()
        let belowThreshold = try render(
            device: device,
            commandQueue: commandQueue,
            pipelineState: pipelineState,
            sourceColor: SIMD3<Float>(repeating: 0.6),
            lutResource: lutResource,
            intensity: 0,
            zebraEnabled: true,
            zebraThreshold: 0.9
        )
        let aboveThreshold = try render(
            device: device,
            commandQueue: commandQueue,
            pipelineState: pipelineState,
            sourceColor: SIMD3<Float>(repeating: 0.95),
            lutResource: lutResource,
            intensity: 0,
            zebraEnabled: true,
            zebraThreshold: 0.9
        )

        XCTAssertEqual(belowThreshold.x, 0.6, accuracy: 0.02)
        XCTAssertEqual(belowThreshold.y, 0.6, accuracy: 0.02)
        XCTAssertEqual(belowThreshold.z, 0.6, accuracy: 0.02)
        XCTAssertGreaterThan(aboveThreshold.x, 0.98)
        XCTAssertGreaterThan(aboveThreshold.y, 0.98)
        XCTAssertGreaterThan(aboveThreshold.z, 0.98)
    }

    func testPreviewShaderZebraUsesRawAnalysisSourceWhenSelected() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal is not available in this test environment")
        }

        guard let commandQueue = device.makeCommandQueue(),
              let pipelineState = try makePipelineState(device: device) else {
            throw XCTSkip("Unable to create Metal pipeline")
        }

        let parsed = try LUTParser().parse(CubeFixtureFactory.redChannelRamp(size: 2))
        let lutResource = try LUTPass(device: device).makeTextureResource(from: parsed)
        let output = try render(
            device: device,
            commandQueue: commandQueue,
            pipelineState: pipelineState,
            sourceColor: SIMD3<Float>(repeating: 0.8),
            lutResource: lutResource,
            intensity: 1,
            zebraEnabled: true,
            zebraThreshold: 0.75,
            analysisSource: .rawSignal
        )

        XCTAssertGreaterThan(output.x, 0.98)
        XCTAssertGreaterThan(output.y, 0.98)
        XCTAssertGreaterThan(output.z, 0.98)
    }

    func testPreviewShaderZebraUsesPreviewAnalysisSourceWhenSelected() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal is not available in this test environment")
        }

        guard let commandQueue = device.makeCommandQueue(),
              let pipelineState = try makePipelineState(device: device) else {
            throw XCTSkip("Unable to create Metal pipeline")
        }

        let parsed = try LUTParser().parse(CubeFixtureFactory.redChannelRamp(size: 2))
        let lutResource = try LUTPass(device: device).makeTextureResource(from: parsed)
        let output = try render(
            device: device,
            commandQueue: commandQueue,
            pipelineState: pipelineState,
            sourceColor: SIMD3<Float>(repeating: 0.8),
            lutResource: lutResource,
            intensity: 1,
            zebraEnabled: true,
            zebraThreshold: 0.75,
            analysisSource: .previewDisplay
        )

        XCTAssertEqual(output.x, 0.8, accuracy: 0.03)
        XCTAssertEqual(output.y, 0, accuracy: 0.02)
        XCTAssertEqual(output.z, 0, accuracy: 0.02)
    }

    func testPreviewShaderFalseColorUsesRawAnalysisSourceWhenSelected() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal is not available in this test environment")
        }

        guard let commandQueue = device.makeCommandQueue(),
              let pipelineState = try makePipelineState(device: device) else {
            throw XCTSkip("Unable to create Metal pipeline")
        }

        let parsed = try LUTParser().parse(CubeFixtureFactory.redChannelRamp(size: 2))
        let lutResource = try LUTPass(device: device).makeTextureResource(from: parsed)
        let output = try render(
            device: device,
            commandQueue: commandQueue,
            pipelineState: pipelineState,
            sourceColor: SIMD3<Float>(repeating: 0.8),
            lutResource: lutResource,
            intensity: 1,
            falseColorEnabled: true,
            analysisSource: .rawSignal
        )

        XCTAssertEqual(output.x, 0.88, accuracy: 0.03)
        XCTAssertEqual(output.y, 0.88, accuracy: 0.03)
        XCTAssertEqual(output.z, 0.22, accuracy: 0.03)
    }

    func testPreviewShaderFalseColorUsesPreviewAnalysisSourceWhenSelected() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal is not available in this test environment")
        }

        guard let commandQueue = device.makeCommandQueue(),
              let pipelineState = try makePipelineState(device: device) else {
            throw XCTSkip("Unable to create Metal pipeline")
        }

        let parsed = try LUTParser().parse(CubeFixtureFactory.redChannelRamp(size: 2))
        let lutResource = try LUTPass(device: device).makeTextureResource(from: parsed)
        let output = try render(
            device: device,
            commandQueue: commandQueue,
            pipelineState: pipelineState,
            sourceColor: SIMD3<Float>(repeating: 0.8),
            lutResource: lutResource,
            intensity: 1,
            falseColorEnabled: true,
            analysisSource: .previewDisplay
        )

        XCTAssertEqual(output.x, 0.48, accuracy: 0.03)
        XCTAssertEqual(output.y, 0.48, accuracy: 0.03)
        XCTAssertEqual(output.z, 0.48, accuracy: 0.03)
    }

    private func render(
        device: MTLDevice,
        commandQueue: MTLCommandQueue,
        pipelineState: MTLRenderPipelineState,
        sourceColor: SIMD3<Float>,
        lutResource: LUTTextureResource,
        intensity: Float,
        colorEncoding: SourceColorEncoding = .rec709,
        lutEnabled: Bool = true,
        falseColorEnabled: Bool = false,
        zebraEnabled: Bool = false,
        zebraThreshold: Float = 0.9,
        zebraMode: Float = 0,
        analysisSource: ExposureAnalysisSource = .rawSignal
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
            SIMD4<Float>(lutEnabled ? 1 : 0, intensity, Float(lutResource.cubeSize), 0),
            SIMD4<Float>(lutResource.domainMin.x, lutResource.domainMin.y, lutResource.domainMin.z, 0),
            SIMD4<Float>(lutResource.domainMax.x, lutResource.domainMax.y, lutResource.domainMax.z, 0)
        ]
        var monitorUniforms = [
            SIMD4<Float>(
                ColorTransformPass.encodingCode(for: colorEncoding),
                falseColorEnabled ? 1 : 0,
                zebraEnabled ? 1 : 0,
                zebraMode
            ),
            SIMD4<Float>(zebraThreshold, 0.4, 0.6, analysisSourceCode(for: analysisSource))
        ]

        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setFragmentTexture(sourceTexture, index: 0)
        renderEncoder.setFragmentTexture(lutResource.texture, index: 1)
        renderEncoder.setFragmentSamplerState(samplerState, index: 0)
        renderEncoder.setFragmentSamplerState(samplerState, index: 1)
        uniforms.withUnsafeBytes { bytes in
            renderEncoder.setFragmentBytes(bytes.baseAddress!, length: bytes.count, index: 0)
        }
        monitorUniforms.withUnsafeBytes { bytes in
            renderEncoder.setFragmentBytes(bytes.baseAddress!, length: bytes.count, index: 1)
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

    private func analysisSourceCode(for source: ExposureAnalysisSource) -> Float {
        switch source {
        case .rawSignal:
            return 0
        case .previewDisplay:
            return 1
        }
    }

    private func makePipelineState(device: MTLDevice) throws -> MTLRenderPipelineState? {
        guard let library = device.makeDefaultLibrary(),
              let vertexFunction = library.makeFunction(name: "previewVertex"),
              let fragmentFunction = library.makeFunction(name: "previewFragment") else {
            return nil
        }

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = .rgba32Float
        return try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
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
