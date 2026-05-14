import CoreVideo
import Foundation

struct PixelRGBA: Equatable {
    var red: UInt8
    var green: UInt8
    var blue: UInt8
    var alpha: UInt8 = 255
}

enum PixelBufferFixtureError: Error, Equatable {
    case creationFailed
    case unsupportedFormat
    case outOfBounds
    case invalidPixelCount(expected: Int, actual: Int)
}

enum PixelBufferFixtureFactory {
    static func makeSolid(
        width: Int,
        height: Int,
        color: PixelRGBA
    ) throws -> CVPixelBuffer {
        try makeBGRA(width: width, height: height, pixels: Array(repeating: color, count: width * height))
    }

    static func makeHorizontalGrayRamp(width: Int, height: Int) throws -> CVPixelBuffer {
        let pixels = (0..<height).flatMap { _ in
            (0..<width).map { x -> PixelRGBA in
                let value = rampValue(index: x, count: width)
                return PixelRGBA(red: value, green: value, blue: value)
            }
        }

        return try makeBGRA(width: width, height: height, pixels: pixels)
    }

    static func makeRGBRamp(width: Int, height: Int) throws -> CVPixelBuffer {
        let pixels = (0..<height).flatMap { y in
            (0..<width).map { x -> PixelRGBA in
                PixelRGBA(
                    red: rampValue(index: x, count: width),
                    green: rampValue(index: y, count: height),
                    blue: rampValue(index: x + y, count: max(width + height - 1, 1))
                )
            }
        }

        return try makeBGRA(width: width, height: height, pixels: pixels)
    }

    static func makeCheckerboard(
        width: Int,
        height: Int,
        tileSize: Int = 2,
        first: PixelRGBA = PixelRGBA(red: 0, green: 0, blue: 0),
        second: PixelRGBA = PixelRGBA(red: 255, green: 255, blue: 255)
    ) throws -> CVPixelBuffer {
        let safeTileSize = max(tileSize, 1)
        let pixels = (0..<height).flatMap { y in
            (0..<width).map { x -> PixelRGBA in
                let tileX = x / safeTileSize
                let tileY = y / safeTileSize
                return (tileX + tileY).isMultiple(of: 2) ? first : second
            }
        }

        return try makeBGRA(width: width, height: height, pixels: pixels)
    }

    static func makeSingleChannel(
        width: Int,
        height: Int,
        channel: RGBChannel
    ) throws -> CVPixelBuffer {
        let color: PixelRGBA
        switch channel {
        case .red:
            color = PixelRGBA(red: 255, green: 0, blue: 0)
        case .green:
            color = PixelRGBA(red: 0, green: 255, blue: 0)
        case .blue:
            color = PixelRGBA(red: 0, green: 0, blue: 255)
        }

        return try makeSolid(width: width, height: height, color: color)
    }

    static func makeClippingPattern(width: Int, height: Int) throws -> CVPixelBuffer {
        let pixels = (0..<height).flatMap { y in
            (0..<width).map { x -> PixelRGBA in
                if x >= width / 2 && y >= height / 2 {
                    return PixelRGBA(red: 255, green: 255, blue: 255)
                }

                let value = UInt8(46)
                return PixelRGBA(red: value, green: value, blue: value)
            }
        }

        return try makeBGRA(width: width, height: height, pixels: pixels)
    }

    static func makeBGRA(width: Int, height: Int, pixels: [PixelRGBA]) throws -> CVPixelBuffer {
        let expectedCount = width * height
        guard pixels.count == expectedCount else {
            throw PixelBufferFixtureError.invalidPixelCount(expected: expectedCount, actual: pixels.count)
        }

        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferMetalCompatibilityKey: true
        ]

        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &pixelBuffer
        )

        guard status == kCVReturnSuccess, let pixelBuffer else {
            throw PixelBufferFixtureError.creationFailed
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw PixelBufferFixtureError.creationFailed
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let destination = baseAddress.assumingMemoryBound(to: UInt8.self)

        for y in 0..<height {
            for x in 0..<width {
                let pixel = pixels[y * width + x]
                let offset = y * bytesPerRow + x * 4
                destination[offset] = pixel.blue
                destination[offset + 1] = pixel.green
                destination[offset + 2] = pixel.red
                destination[offset + 3] = pixel.alpha
            }
        }

        return pixelBuffer
    }

    static func readPixel(_ pixelBuffer: CVPixelBuffer, x: Int, y: Int) throws -> PixelRGBA {
        guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA else {
            throw PixelBufferFixtureError.unsupportedFormat
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard x >= 0, x < width, y >= 0, y < height else {
            throw PixelBufferFixtureError.outOfBounds
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw PixelBufferFixtureError.creationFailed
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let source = baseAddress.assumingMemoryBound(to: UInt8.self)
        let offset = y * bytesPerRow + x * 4

        return PixelRGBA(
            red: source[offset + 2],
            green: source[offset + 1],
            blue: source[offset],
            alpha: source[offset + 3]
        )
    }

    private static func rampValue(index: Int, count: Int) -> UInt8 {
        guard count > 1 else { return 0 }
        let normalized = Double(index) / Double(count - 1)
        return UInt8((normalized * 255).rounded())
    }
}

enum RGBChannel {
    case red
    case green
    case blue
}
