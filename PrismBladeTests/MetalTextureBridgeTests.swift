import CoreVideo
import Metal
import XCTest
@testable import PrismBlade

final class MetalTextureBridgeTests: XCTestCase {
    func testBGRApixelBufferBridgesToMetalTexture() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal is not available in this test environment")
        }

        let format = FrameFormat(
            resolution: CGSize(width: 16, height: 8),
            frameRate: 30,
            colorEncoding: .rec709
        )
        let pixelBuffer = try SimulatedPixelBufferFactory.makeFrame(sequence: 1, format: format)
        let bridge = try MetalTextureBridge(device: device)

        let texture = try bridge.makeTexture(from: pixelBuffer)

        XCTAssertEqual(texture.width, 16)
        XCTAssertEqual(texture.height, 8)
        XCTAssertEqual(texture.pixelFormat, .bgra8Unorm)
    }
}
