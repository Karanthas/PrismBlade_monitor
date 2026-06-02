import CoreGraphics
import CoreVideo
import ImageIO
import UIKit
import XCTest
@testable import PrismBlade

final class JPEGPixelBufferDecoderTests: XCTestCase {
    func testDecodesJPEGIntoBGRAFrameBuffer() throws {
        let pixelBuffer = try JPEGPixelBufferDecoder().decode(Self.makeJPEG(width: 3, height: 2))

        XCTAssertEqual(CVPixelBufferGetWidth(pixelBuffer), 3)
        XCTAssertEqual(CVPixelBufferGetHeight(pixelBuffer), 2)
        XCTAssertEqual(CVPixelBufferGetPixelFormatType(pixelBuffer), kCVPixelFormatType_32BGRA)
    }

    func testRejectsInvalidJPEG() {
        XCTAssertThrowsError(try JPEGPixelBufferDecoder().decode(Data([0xFF, 0xD8, 0x00])))
    }

    static func makeJPEG(width: Int = 2, height: Int = 2) throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
        let image = renderer.image { context in
            UIColor(red: 0.9, green: 0.1, blue: 0.2, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }

        guard let data = image.jpegData(compressionQuality: 1) else {
            throw JPEGFixtureError.encodingFailed
        }
        return data
    }
}

private enum JPEGFixtureError: Error {
    case encodingFailed
}
