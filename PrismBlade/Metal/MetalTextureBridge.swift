import CoreVideo
import Foundation
import Metal

final class MetalTextureBridge {
    enum BridgeError: Error, LocalizedError, Equatable {
        case cacheCreationFailed(CVReturn)
        case invalidDimensions
        case unsupportedPixelFormat(OSType)
        case textureCreationFailed(CVReturn)
        case missingTexture

        var errorDescription: String? {
            switch self {
            case let .cacheCreationFailed(status):
                return "无法创建 Metal texture cache：\(status)"
            case .invalidDimensions:
                return "CVPixelBuffer 尺寸无效"
            case let .unsupportedPixelFormat(pixelFormat):
                return "暂不支持的 CVPixelBuffer pixel format：\(pixelFormat)"
            case let .textureCreationFailed(status):
                return "CVPixelBuffer 桥接 Metal texture 失败：\(status)"
            case .missingTexture:
                return "CVMetalTexture 未返回 MTLTexture"
            }
        }
    }

    private let textureCache: CVMetalTextureCache

    init(device: MTLDevice) throws {
        var cache: CVMetalTextureCache?
        let status = CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache)

        guard status == kCVReturnSuccess, let cache else {
            throw BridgeError.cacheCreationFailed(status)
        }

        textureCache = cache
    }

    func makeTexture(from pixelBuffer: CVPixelBuffer) throws -> MTLTexture {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        guard width > 0, height > 0 else {
            throw BridgeError.invalidDimensions
        }

        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        guard pixelFormat == kCVPixelFormatType_32BGRA else {
            throw BridgeError.unsupportedPixelFormat(pixelFormat)
        }

        var textureRef: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            pixelBuffer,
            nil,
            .bgra8Unorm,
            width,
            height,
            0,
            &textureRef
        )

        guard status == kCVReturnSuccess else {
            throw BridgeError.textureCreationFailed(status)
        }

        guard let textureRef, let texture = CVMetalTextureGetTexture(textureRef) else {
            throw BridgeError.missingTexture
        }

        return texture
    }

    func flush() {
        CVMetalTextureCacheFlush(textureCache, 0)
    }
}
