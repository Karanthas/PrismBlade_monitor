import CoreGraphics
import CoreVideo
import Foundation
import ImageIO

struct JPEGPixelBufferDecoder: Sendable {
    func decode(_ jpegData: Data) throws -> CVPixelBuffer {
        guard let imageSource = CGImageSourceCreateWithData(jpegData as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(imageSource, 0, [kCGImageSourceShouldCache: true] as CFDictionary) else {
            throw JPEGPixelBufferDecoderError.invalidJPEG
        }

        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else {
            throw JPEGPixelBufferDecoderError.invalidDimensions(width: width, height: height)
        }

        var pixelBuffer: CVPixelBuffer?
        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferMetalCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer else {
            throw JPEGPixelBufferDecoderError.pixelBufferCreationFailed(status)
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw JPEGPixelBufferDecoderError.missingBaseAddress
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        guard let context = CGContext(
            data: baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            throw JPEGPixelBufferDecoderError.contextCreationFailed
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixelBuffer
    }
}

enum JPEGPixelBufferDecoderError: Error, Equatable, LocalizedError {
    case invalidJPEG
    case invalidDimensions(width: Int, height: Int)
    case pixelBufferCreationFailed(CVReturn)
    case missingBaseAddress
    case contextCreationFailed

    var errorDescription: String? {
        switch self {
        case .invalidJPEG:
            return "Live-view payload did not decode as JPEG."
        case .invalidDimensions(let width, let height):
            return "Decoded JPEG dimensions are invalid: \(width)x\(height)."
        case .pixelBufferCreationFailed(let status):
            return "Failed to create live-view CVPixelBuffer: \(status)."
        case .missingBaseAddress:
            return "Decoded live-view CVPixelBuffer has no writable base address."
        case .contextCreationFailed:
            return "Failed to create bitmap context for decoded live-view frame."
        }
    }
}
