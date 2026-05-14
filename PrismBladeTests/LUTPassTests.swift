@testable import PrismBlade
import Metal
import XCTest

final class LUTPassTests: XCTestCase {
    func testIdentityLUTUploadsInCubeOrder() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal is not available in this test environment")
        }

        let parsed = try LUTParser().parse(CubeFixtureFactory.identity(size: 2))
        let texture = try LUTPass(device: device).makeTexture(from: parsed)
        let values = readRGBAValues(from: texture, size: 2)

        XCTAssertEqual(rgb(at: index(red: 0, green: 0, blue: 0, size: 2), in: values), SIMD3<Float>(0, 0, 0))
        XCTAssertEqual(rgb(at: index(red: 1, green: 0, blue: 0, size: 2), in: values), SIMD3<Float>(1, 0, 0))
        XCTAssertEqual(rgb(at: index(red: 0, green: 1, blue: 0, size: 2), in: values), SIMD3<Float>(0, 1, 0))
        XCTAssertEqual(rgb(at: index(red: 0, green: 0, blue: 1, size: 2), in: values), SIMD3<Float>(0, 0, 1))
        XCTAssertEqual(rgb(at: index(red: 1, green: 1, blue: 1, size: 2), in: values), SIMD3<Float>(1, 1, 1))
    }

    func testRedChannelRampUploadsInCubeOrder() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal is not available in this test environment")
        }

        let parsed = try LUTParser().parse(CubeFixtureFactory.redChannelRamp(size: 2))
        let texture = try LUTPass(device: device).makeTexture(from: parsed)
        let values = readRGBAValues(from: texture, size: 2)

        XCTAssertEqual(rgb(at: index(red: 0, green: 0, blue: 0, size: 2), in: values), SIMD3<Float>(0, 0, 0))
        XCTAssertEqual(rgb(at: index(red: 1, green: 0, blue: 0, size: 2), in: values), SIMD3<Float>(1, 0, 0))
        XCTAssertEqual(rgb(at: index(red: 0, green: 1, blue: 1, size: 2), in: values), SIMD3<Float>(0, 0, 0))
        XCTAssertEqual(rgb(at: index(red: 1, green: 1, blue: 1, size: 2), in: values), SIMD3<Float>(1, 0, 0))
    }

    func testTextureResourcePreservesDomain() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal is not available in this test environment")
        }

        let parsed = try LUTParser().parse(CubeFixtureFactory.outOfRangeDomainAndData())
        let resource = try LUTPass(device: device).makeTextureResource(from: parsed)

        XCTAssertEqual(resource.domainMin, SIMD3<Float>(-0.1, 0, 0))
        XCTAssertEqual(resource.domainMax, SIMD3<Float>(1.1, 1, 1))
        XCTAssertEqual(resource.texture.pixelFormat, .rgba32Float)
    }

    private func readRGBAValues(from texture: MTLTexture, size: Int) -> [Float] {
        var values = [Float](repeating: 0, count: size * size * size * 4)
        values.withUnsafeMutableBytes { bytes in
            texture.getBytes(
                bytes.baseAddress!,
                bytesPerRow: size * 4 * MemoryLayout<Float>.stride,
                bytesPerImage: size * size * 4 * MemoryLayout<Float>.stride,
                from: MTLRegionMake3D(0, 0, 0, size, size, size),
                mipmapLevel: 0,
                slice: 0
            )
        }
        return values
    }

    private func rgb(at entryIndex: Int, in values: [Float]) -> SIMD3<Float> {
        let offset = entryIndex * 4
        return SIMD3<Float>(values[offset], values[offset + 1], values[offset + 2])
    }

    private func index(red: Int, green: Int, blue: Int, size: Int) -> Int {
        blue * size * size + green * size + red
    }
}
