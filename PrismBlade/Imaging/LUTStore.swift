import Foundation

final class LUTStore {
    private let repository: LUTRepository
    private let cacheLock = NSLock()
    private var parsedCache: [UUID: ParsedLUT] = [:]

    init(repository: LUTRepository = LUTRepository()) {
        self.repository = repository
    }

    func loadBuiltInDescriptors() -> [LUTDescriptor] {
        repository.loadBuiltInDescriptors()
    }

    func parsedLUT(for descriptor: LUTDescriptor) throws -> ParsedLUT {
        cacheLock.lock()
        if let cached = parsedCache[descriptor.id] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        let parsed = try repository.loadParsedLUT(for: descriptor)

        cacheLock.lock()
        parsedCache[descriptor.id] = parsed
        cacheLock.unlock()

        return parsed
    }

    func removeCachedLUT(for descriptor: LUTDescriptor) {
        cacheLock.lock()
        parsedCache.removeValue(forKey: descriptor.id)
        cacheLock.unlock()
    }
}
