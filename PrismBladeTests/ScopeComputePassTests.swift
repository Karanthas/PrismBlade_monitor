@testable import PrismBlade
import CoreMedia
import Metal
import XCTest

final class ScopeComputePassTests: XCTestCase {
    func testGrayRampProducesWaveformBinsByColumn() throws {
        let environment = try makeEnvironment()
        let texture = try makeTexture(
            device: environment.device,
            width: 4,
            height: 2,
            pixels: [
                SIMD4<Float>(0, 0, 0, 1),
                SIMD4<Float>(1.0 / 3.0, 1.0 / 3.0, 1.0 / 3.0, 1),
                SIMD4<Float>(2.0 / 3.0, 2.0 / 3.0, 2.0 / 3.0, 1),
                SIMD4<Float>(1, 1, 1, 1),
                SIMD4<Float>(0, 0, 0, 1),
                SIMD4<Float>(1.0 / 3.0, 1.0 / 3.0, 1.0 / 3.0, 1),
                SIMD4<Float>(2.0 / 3.0, 2.0 / 3.0, 2.0 / 3.0, 1),
                SIMD4<Float>(1, 1, 1, 1)
            ]
        )
        let pass = try ScopeComputePass(
            device: environment.device,
            library: environment.library,
            configuration: ScopeComputePass.Configuration(binWidth: 4, binHeight: 4, frameInterval: 1)
        )
        let data = try encodeScope(
            pass: pass,
            texture: texture,
            frame: try makeFrame(sequence: 1),
            monitor: makeMonitor(scopeMode: .lumaWaveform),
            commandQueue: environment.commandQueue
        )

        XCTAssertEqual(data.binWidth, 4)
        XCTAssertEqual(data.binHeight, 4)
        XCTAssertGreaterThan(data.lumaBins[index(column: 0, row: 0, binHeight: 4)], 0.9)
        XCTAssertGreaterThan(data.lumaBins[index(column: 1, row: 1, binHeight: 4)], 0.9)
        XCTAssertGreaterThan(data.lumaBins[index(column: 2, row: 2, binHeight: 4)], 0.9)
        XCTAssertGreaterThan(data.lumaBins[index(column: 3, row: 3, binHeight: 4)], 0.9)
    }

    func testRGBParadeKeepsChannelBinsSeparate() throws {
        let environment = try makeEnvironment()
        let texture = try makeTexture(
            device: environment.device,
            width: 2,
            height: 1,
            pixels: [
                SIMD4<Float>(1, 0, 0, 1),
                SIMD4<Float>(0, 1, 0, 1)
            ]
        )
        let pass = try ScopeComputePass(
            device: environment.device,
            library: environment.library,
            configuration: ScopeComputePass.Configuration(binWidth: 2, binHeight: 4, frameInterval: 1)
        )
        let data = try encodeScope(
            pass: pass,
            texture: texture,
            frame: try makeFrame(sequence: 2),
            monitor: makeMonitor(scopeMode: .rgbParade),
            commandQueue: environment.commandQueue
        )

        XCTAssertGreaterThan(data.redBins[index(column: 0, row: 3, binHeight: 4)], 0.9)
        XCTAssertGreaterThan(data.redBins[index(column: 1, row: 0, binHeight: 4)], 0.9)
        XCTAssertGreaterThan(data.greenBins[index(column: 0, row: 0, binHeight: 4)], 0.9)
        XCTAssertGreaterThan(data.greenBins[index(column: 1, row: 3, binHeight: 4)], 0.9)
        XCTAssertGreaterThan(data.blueBins[index(column: 0, row: 0, binHeight: 4)], 0.9)
        XCTAssertGreaterThan(data.blueBins[index(column: 1, row: 0, binHeight: 4)], 0.9)
    }

    func testScopeOffDoesNotEncodeCompute() throws {
        let environment = try makeEnvironment()
        let texture = try makeTexture(
            device: environment.device,
            width: 1,
            height: 1,
            pixels: [SIMD4<Float>(1, 1, 1, 1)]
        )
        let pass = try ScopeComputePass(
            device: environment.device,
            library: environment.library,
            configuration: ScopeComputePass.Configuration(binWidth: 2, binHeight: 2, frameInterval: 1)
        )
        guard let commandBuffer = environment.commandQueue.makeCommandBuffer() else {
            XCTFail("Unable to create command buffer")
            return
        }
        let lutResource = try LUTPass(device: environment.device).fallbackResource()
        let samplerState = try makeLUTSampler(device: environment.device)

        let didEncode = pass.encodeIfNeeded(
            sourceTexture: texture,
            lutTexture: lutResource.texture,
            lutSamplerState: samplerState,
            lutUniforms: makeLUTUniforms(resource: lutResource, enabled: false),
            frame: try makeFrame(sequence: 3),
            monitor: makeMonitor(scopeMode: .off),
            commandBuffer: commandBuffer
        ) { _ in
            XCTFail("Scope off should not produce data")
        }

        XCTAssertFalse(didEncode)
        XCTAssertEqual(pass.encodedPassCount, 0)
    }

    func testPendingReadbackSkipsNewEncode() throws {
        let environment = try makeEnvironment()
        let texture = try makeTexture(
            device: environment.device,
            width: 1,
            height: 1,
            pixels: [SIMD4<Float>(1, 1, 1, 1)]
        )
        let pass = try ScopeComputePass(
            device: environment.device,
            library: environment.library,
            configuration: ScopeComputePass.Configuration(binWidth: 2, binHeight: 2, frameInterval: 1)
        )
        guard let firstCommandBuffer = environment.commandQueue.makeCommandBuffer(),
              let secondCommandBuffer = environment.commandQueue.makeCommandBuffer() else {
            XCTFail("Unable to create command buffers")
            return
        }
        let lutResource = try LUTPass(device: environment.device).fallbackResource()
        let samplerState = try makeLUTSampler(device: environment.device)
        let expectation = expectation(description: "First readback completes")

        let firstDidEncode = pass.encodeIfNeeded(
            sourceTexture: texture,
            lutTexture: lutResource.texture,
            lutSamplerState: samplerState,
            lutUniforms: makeLUTUniforms(resource: lutResource, enabled: false),
            frame: try makeFrame(sequence: 4),
            monitor: makeMonitor(scopeMode: .lumaWaveform),
            commandBuffer: firstCommandBuffer
        ) { _ in
            expectation.fulfill()
        }
        let secondDidEncode = pass.encodeIfNeeded(
            sourceTexture: texture,
            lutTexture: lutResource.texture,
            lutSamplerState: samplerState,
            lutUniforms: makeLUTUniforms(resource: lutResource, enabled: false),
            frame: try makeFrame(sequence: 5),
            monitor: makeMonitor(scopeMode: .lumaWaveform),
            commandBuffer: secondCommandBuffer
        ) { _ in
            XCTFail("Pending readback should keep the previous scope data")
        }

        XCTAssertTrue(firstDidEncode)
        XCTAssertFalse(secondDidEncode)
        XCTAssertEqual(pass.encodedPassCount, 1)

        firstCommandBuffer.commit()
        wait(for: [expectation], timeout: 2)
    }

    func testScopeSamplesLUTPreviewResultWhenEnabled() throws {
        let environment = try makeEnvironment()
        let texture = try makeTexture(
            device: environment.device,
            width: 1,
            height: 1,
            pixels: [SIMD4<Float>(0.5, 0.5, 0.5, 1)]
        )
        let pass = try ScopeComputePass(
            device: environment.device,
            library: environment.library,
            configuration: ScopeComputePass.Configuration(binWidth: 1, binHeight: 4, frameInterval: 1)
        )
        let parsed = try LUTParser().parse(CubeFixtureFactory.redChannelRamp(size: 2))
        let lutResource = try LUTPass(device: environment.device).makeTextureResource(from: parsed)
        let data = try encodeScope(
            pass: pass,
            texture: texture,
            frame: try makeFrame(sequence: 6),
            monitor: makeMonitor(scopeMode: .lumaWaveform),
            commandQueue: environment.commandQueue,
            lutResource: lutResource,
            lutEnabled: true
        )

        XCTAssertGreaterThan(data.lumaBins[index(column: 0, row: 0, binHeight: 4)], 0.9)
        XCTAssertEqual(data.lumaBins[index(column: 0, row: 2, binHeight: 4)], 0, accuracy: 0.01)
    }

    private func makeEnvironment() throws -> MetalEnvironment {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal is not available in this test environment")
        }

        guard let commandQueue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary() else {
            throw XCTSkip("Metal scope test environment is not available")
        }

        return MetalEnvironment(device: device, commandQueue: commandQueue, library: library)
    }

    private func encodeScope(
        pass: ScopeComputePass,
        texture: MTLTexture,
        frame: VideoFrame,
        monitor: MonitorState,
        commandQueue: MTLCommandQueue,
        lutResource: LUTTextureResource? = nil,
        lutEnabled: Bool = false
    ) throws -> ScopeData {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            throw XCTSkip("Unable to create command buffer")
        }

        let resolvedLUTResource: LUTTextureResource
        if let lutResource {
            resolvedLUTResource = lutResource
        } else {
            resolvedLUTResource = try LUTPass(device: commandQueue.device).fallbackResource()
        }
        let samplerState = try makeLUTSampler(device: commandQueue.device)
        let expectation = expectation(description: "Scope data is read back")
        var scopeData: ScopeData?
        let didEncode = pass.encodeIfNeeded(
            sourceTexture: texture,
            lutTexture: resolvedLUTResource.texture,
            lutSamplerState: samplerState,
            lutUniforms: makeLUTUniforms(resource: resolvedLUTResource, enabled: lutEnabled),
            frame: frame,
            monitor: monitor,
            commandBuffer: commandBuffer
        ) { data in
            scopeData = data
            expectation.fulfill()
        }

        XCTAssertTrue(didEncode)
        commandBuffer.commit()
        wait(for: [expectation], timeout: 2)

        guard let scopeData else {
            XCTFail("Scope data was not produced")
            return ScopeData(lumaBins: [], redBins: [], greenBins: [], blueBins: [], binWidth: 0, binHeight: 0, sourceSequence: -1)
        }

        return scopeData
    }

    private func makeLUTSampler(device: MTLDevice) throws -> MTLSamplerState {
        let descriptor = MTLSamplerDescriptor()
        descriptor.minFilter = .linear
        descriptor.magFilter = .linear
        descriptor.sAddressMode = .clampToEdge
        descriptor.tAddressMode = .clampToEdge
        descriptor.rAddressMode = .clampToEdge

        guard let sampler = device.makeSamplerState(descriptor: descriptor) else {
            throw XCTSkip("Unable to create LUT sampler")
        }

        return sampler
    }

    private func makeLUTUniforms(resource: LUTTextureResource, enabled: Bool) -> [SIMD4<Float>] {
        [
            SIMD4<Float>(enabled ? 1 : 0, 1, Float(resource.cubeSize), 0),
            SIMD4<Float>(resource.domainMin.x, resource.domainMin.y, resource.domainMin.z, 0),
            SIMD4<Float>(resource.domainMax.x, resource.domainMax.y, resource.domainMax.z, 0)
        ]
    }

    private func makeTexture(
        device: MTLDevice,
        width: Int,
        height: Int,
        pixels: [SIMD4<Float>]
    ) throws -> MTLTexture {
        XCTAssertEqual(pixels.count, width * height)

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .shared

        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw XCTSkip("Unable to create float scope texture")
        }

        pixels.withUnsafeBytes { bytes in
            texture.replace(
                region: MTLRegionMake2D(0, 0, width, height),
                mipmapLevel: 0,
                withBytes: bytes.baseAddress!,
                bytesPerRow: width * MemoryLayout<SIMD4<Float>>.stride
            )
        }

        return texture
    }

    private func makeFrame(sequence: Int) throws -> VideoFrame {
        let format = FrameFormat(
            resolution: CGSize(width: 1, height: 1),
            frameRate: 30,
            colorEncoding: .rec709
        )

        return VideoFrame(
            sequence: sequence,
            timestamp: CMTime(value: CMTimeValue(sequence), timescale: 30),
            format: format,
            pixelBuffer: try PixelBufferFixtureFactory.makeSolid(
                width: 1,
                height: 1,
                color: PixelRGBA(red: 0, green: 0, blue: 0)
            ),
            metadata: FrameCameraMetadata(iso: "400", shutter: "1/50", aperture: "f/2.8", whiteBalance: "5600K")
        )
    }

    private func makeMonitor(scopeMode: ScopeMode) -> MonitorState {
        var monitor = MonitorState.initial
        monitor.scopeMode = scopeMode
        return monitor
    }

    private func index(column: Int, row: Int, binHeight: Int) -> Int {
        column * binHeight + row
    }
}

private struct MetalEnvironment {
    var device: MTLDevice
    var commandQueue: MTLCommandQueue
    var library: MTLLibrary
}
