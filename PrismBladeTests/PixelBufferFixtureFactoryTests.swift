import CoreVideo
import XCTest

final class PixelBufferFixtureFactoryTests: XCTestCase {
    func testSolidPixelBufferUsesBGRAFormatAndExpectedPixels() throws {
        let buffer = try PixelBufferFixtureFactory.makeSolid(
            width: 2,
            height: 2,
            color: PixelRGBA(red: 46, green: 46, blue: 46)
        )

        XCTAssertEqual(CVPixelBufferGetWidth(buffer), 2)
        XCTAssertEqual(CVPixelBufferGetHeight(buffer), 2)
        XCTAssertEqual(CVPixelBufferGetPixelFormatType(buffer), kCVPixelFormatType_32BGRA)
        XCTAssertEqual(
            try PixelBufferFixtureFactory.readPixel(buffer, x: 1, y: 1),
            PixelRGBA(red: 46, green: 46, blue: 46)
        )
    }

    func testHorizontalGrayRampProducesStableEndpoints() throws {
        let buffer = try PixelBufferFixtureFactory.makeHorizontalGrayRamp(width: 4, height: 2)

        XCTAssertEqual(
            try PixelBufferFixtureFactory.readPixel(buffer, x: 0, y: 0),
            PixelRGBA(red: 0, green: 0, blue: 0)
        )
        XCTAssertEqual(
            try PixelBufferFixtureFactory.readPixel(buffer, x: 3, y: 0),
            PixelRGBA(red: 255, green: 255, blue: 255)
        )
    }

    func testCheckerboardAlternatesTiles() throws {
        let buffer = try PixelBufferFixtureFactory.makeCheckerboard(width: 4, height: 4, tileSize: 1)

        XCTAssertEqual(
            try PixelBufferFixtureFactory.readPixel(buffer, x: 0, y: 0),
            PixelRGBA(red: 0, green: 0, blue: 0)
        )
        XCTAssertEqual(
            try PixelBufferFixtureFactory.readPixel(buffer, x: 1, y: 0),
            PixelRGBA(red: 255, green: 255, blue: 255)
        )
    }

    func testRejectsInvalidPixelCount() {
        XCTAssertThrowsError(
            try PixelBufferFixtureFactory.makeBGRA(
                width: 2,
                height: 2,
                pixels: [PixelRGBA(red: 0, green: 0, blue: 0)]
            )
        ) { error in
            XCTAssertEqual(
                error as? PixelBufferFixtureError,
                .invalidPixelCount(expected: 4, actual: 1)
            )
        }
    }
}
