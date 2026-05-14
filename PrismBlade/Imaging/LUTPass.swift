import Foundation
import Metal

struct LUTTextureResource {
    var texture: MTLTexture
    var cubeSize: Int
    var domainMin: SIMD3<Float>
    var domainMax: SIMD3<Float>
}

final class LUTPass {
    enum LUTPassError: Error, LocalizedError {
        case invalidEntryCount(expected: Int, actual: Int)
        case textureCreationFailed

        var errorDescription: String? {
            switch self {
            case let .invalidEntryCount(expected, actual):
                return "LUT 数据数量不匹配，需要 \(expected) 个，实际 \(actual) 个"
            case .textureCreationFailed:
                return "无法创建 3D LUT texture"
            }
        }
    }

    private let device: MTLDevice
    private let cacheLock = NSLock()
    private var textureCache: [UUID: LUTTextureResource] = [:]
    private var fallbackTexture: MTLTexture?

    init(device: MTLDevice) {
        self.device = device
    }

    func textureResource(for descriptor: LUTDescriptor, store: LUTStore) throws -> LUTTextureResource {
        cacheLock.lock()
        if let cached = textureCache[descriptor.id] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        let parsed = try store.parsedLUT(for: descriptor)
        let resource = try makeTextureResource(from: parsed)

        cacheLock.lock()
        textureCache[descriptor.id] = resource
        cacheLock.unlock()

        return resource
    }

    func fallbackResource() throws -> LUTTextureResource {
        cacheLock.lock()
        if let fallbackTexture {
            cacheLock.unlock()
            return LUTTextureResource(
                texture: fallbackTexture,
                cubeSize: 2,
                domainMin: SIMD3<Float>(0, 0, 0),
                domainMax: SIMD3<Float>(1, 1, 1)
            )
        }
        cacheLock.unlock()

        let parsed = ParsedLUT(
            title: "Identity",
            cubeSize: 2,
            domainMin: SIMD3<Double>(0, 0, 0),
            domainMax: SIMD3<Double>(1, 1, 1),
            entries: [
                SIMD3<Double>(0, 0, 0),
                SIMD3<Double>(1, 0, 0),
                SIMD3<Double>(0, 1, 0),
                SIMD3<Double>(1, 1, 0),
                SIMD3<Double>(0, 0, 1),
                SIMD3<Double>(1, 0, 1),
                SIMD3<Double>(0, 1, 1),
                SIMD3<Double>(1, 1, 1)
            ],
            warnings: []
        )
        let resource = try makeTextureResource(from: parsed)

        cacheLock.lock()
        fallbackTexture = resource.texture
        cacheLock.unlock()

        return resource
    }

    func makeTextureResource(from parsed: ParsedLUT) throws -> LUTTextureResource {
        let texture = try makeTexture(from: parsed)
        return LUTTextureResource(
            texture: texture,
            cubeSize: parsed.cubeSize,
            domainMin: SIMD3<Float>(
                Float(parsed.domainMin.x),
                Float(parsed.domainMin.y),
                Float(parsed.domainMin.z)
            ),
            domainMax: SIMD3<Float>(
                Float(parsed.domainMax.x),
                Float(parsed.domainMax.y),
                Float(parsed.domainMax.z)
            )
        )
    }

    func makeTexture(from parsed: ParsedLUT) throws -> MTLTexture {
        let size = parsed.cubeSize
        let expectedCount = size * size * size

        guard parsed.entries.count == expectedCount else {
            throw LUTPassError.invalidEntryCount(expected: expectedCount, actual: parsed.entries.count)
        }

        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type3D
        descriptor.pixelFormat = .rgba32Float
        descriptor.width = size
        descriptor.height = size
        descriptor.depth = size
        descriptor.mipmapLevelCount = 1
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .shared

        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw LUTPassError.textureCreationFailed
        }

        var rgbaValues: [Float] = []
        rgbaValues.reserveCapacity(expectedCount * 4)

        for entry in parsed.entries {
            rgbaValues.append(Float(entry.x))
            rgbaValues.append(Float(entry.y))
            rgbaValues.append(Float(entry.z))
            rgbaValues.append(1)
        }

        rgbaValues.withUnsafeBytes { bytes in
            texture.replace(
                region: MTLRegionMake3D(0, 0, 0, size, size, size),
                mipmapLevel: 0,
                slice: 0,
                withBytes: bytes.baseAddress!,
                bytesPerRow: size * 4 * MemoryLayout<Float>.stride,
                bytesPerImage: size * size * 4 * MemoryLayout<Float>.stride
            )
        }

        return texture
    }
}
