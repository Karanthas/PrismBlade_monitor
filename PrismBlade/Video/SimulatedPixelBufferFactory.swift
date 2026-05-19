import CoreVideo
import Foundation

enum SimulatedPixelBufferFactory {
    enum FactoryError: Error, LocalizedError, Equatable {
        case invalidResolution
        case creationFailed
        case missingBaseAddress

        var errorDescription: String? {
            switch self {
            case .invalidResolution:
                return "模拟帧分辨率无效"
            case .creationFailed:
                return "无法创建模拟 CVPixelBuffer"
            case .missingBaseAddress:
                return "无法访问模拟 CVPixelBuffer 内存"
            }
        }
    }

    static func makePlaceholderBuffer(format: FrameFormat) -> CVPixelBuffer {
        do {
            return try makeFrame(sequence: 0, format: format)
        } catch {
            // Placeholder 是 App 启动前的兜底帧。若这里失败，说明 CoreVideo 环境不可用，
            // 继续运行也无法建立阶段 2 的媒体帧边界，因此让问题尽早暴露。
            preconditionFailure(error.localizedDescription)
        }
    }

    static func makeFrame(sequence: Int, format: FrameFormat) throws -> CVPixelBuffer {
        let width = Int(format.resolution.width.rounded())
        let height = Int(format.resolution.height.rounded())

        guard width > 0, height > 0 else {
            throw FactoryError.invalidResolution
        }

        let pixelBuffer = try makeEmptyBGRA(width: width, height: height)
        // 填充步骤和创建步骤分开，方便后续复用 CVPixelBufferPool 时只替换分配策略，
        // 保留同一套确定性的测试图案生成逻辑。
        try fill(pixelBuffer, width: width, height: height, sequence: sequence)
        return pixelBuffer
    }

    private static func makeEmptyBGRA(width: Int, height: Int) throws -> CVPixelBuffer {
        // BGRA 是阶段 2 的最低风险格式：AVAssetReader 可以输出，CVMetalTextureCache
        // 后续也能直接桥接为 .bgra8Unorm，避免在 Metal 预览闭环前就引入 YCbCr shader。
        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferMetalCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:]
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
            throw FactoryError.creationFailed
        }

        return pixelBuffer
    }

    private static func fill(
        _ pixelBuffer: CVPixelBuffer,
        width: Int,
        height: Int,
        sequence: Int
    ) throws {
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw FactoryError.missingBaseAddress
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let destination = baseAddress.assumingMemoryBound(to: UInt8.self)
        let phase = Double(sequence % 240) / 240

        // 使用 bytesPerRow 而不是 width * 4：CoreVideo 可以为行对齐插入 padding，
        // 如果忽略 stride，某些设备或未来 pixel buffer pool 下会写错内存位置。
        for y in 0..<height {
            let vertical = height > 1 ? Double(y) / Double(height - 1) : 0

            for x in 0..<width {
                let horizontal = width > 1 ? Double(x) / Double(width - 1) : 0
                let offset = y * bytesPerRow + x * 4
                let pixel = pixelColor(x: x, y: y, width: width, height: height, horizontal: horizontal, vertical: vertical, phase: phase)

                destination[offset] = pixel.blue
                destination[offset + 1] = pixel.green
                destination[offset + 2] = pixel.red
                destination[offset + 3] = 255
            }
        }
    }

    private static func pixelColor(
        x: Int,
        y: Int,
        width: Int,
        height: Int,
        horizontal: Double,
        vertical: Double,
        phase: Double
    ) -> SimulatedPixel {
        // 底图是水平亮度 ramp + 轻微纵向色彩变化。这样后续 LUT、伪色、斑马纹和
        // waveform 都能拿到稳定的暗部、中灰和高光区域，而不是只能看到纯色块。
        var red = UInt8((horizontal * 255).rounded())
        var green = UInt8(((0.18 + 0.72 * horizontal) * 255).rounded())
        var blue = UInt8(((0.22 + 0.48 * vertical) * 255).rounded())

        let blockSize = max(min(width, height) / 6, 32)
        let redX = Int(phase * Double(width + blockSize)) - blockSize
        let greenX = width - redX - blockSize
        let cyanY = Int((0.24 + 0.18 * sin(phase * Double.pi * 2)) * Double(height))

        if contains(x: x, y: y, originX: redX, originY: Int(Double(height) * 0.22), width: blockSize, height: blockSize) {
            red = 235
            green = 48
            blue = 38
        } else if contains(x: x, y: y, originX: greenX, originY: Int(Double(height) * 0.48), width: blockSize * 3 / 4, height: blockSize * 3 / 4) {
            red = 42
            green = 216
            blue = 88
        } else if contains(x: x, y: y, originX: Int(Double(width) * 0.42), originY: cyanY, width: blockSize * 6 / 5, height: blockSize / 2) {
            red = 48
            green = 206
            blue = 226
        }

        return SimulatedPixel(red: red, green: green, blue: blue)
    }

    private static func contains(
        x: Int,
        y: Int,
        originX: Int,
        originY: Int,
        width: Int,
        height: Int
    ) -> Bool {
        x >= originX && x < originX + width && y >= originY && y < originY + height
    }
}

private struct SimulatedPixel {
    var red: UInt8
    var green: UInt8
    var blue: UInt8
}
