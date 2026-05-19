import Foundation

final class LUTRepository {
    private let parser = LUTParser()
    private let fileManager: FileManager
    private let documentsURLOverride: URL?
    private let builtInLUTDirectoryURLOverride: URL?
    private let bundle: Bundle
    // 单独保存 metadata index，避免每次启动都重新解析全部 .cube 文件。
    private let indexFileName = "lut-index.json"

    init(
        fileManager: FileManager = .default,
        documentsURL: URL? = nil,
        builtInLUTDirectoryURL: URL? = nil,
        bundle: Bundle = .main
    ) {
        self.fileManager = fileManager
        documentsURLOverride = documentsURL
        builtInLUTDirectoryURLOverride = builtInLUTDirectoryURL
        self.bundle = bundle
    }

    func loadImportedDescriptors() -> [LUTDescriptor] {
        // index 缺失或损坏时返回空数组，让 App 仍可进入监看界面。
        guard let data = try? Data(contentsOf: indexURL) else { return [] }
        return (try? JSONDecoder().decode([LUTDescriptor].self, from: data)) ?? []
    }

    func loadBuiltInDescriptors() -> [LUTDescriptor] {
        guard let directoryURL = builtInLUTDirectoryURL else { return [] }

        let urls = (try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        return urls
            .filter { $0.pathExtension.lowercased() == "cube" }
            .compactMap { url -> LUTDescriptor? in
                guard let parsed = try? parser.parse(String(contentsOf: url, encoding: .utf8)) else {
                    return nil
                }

                let fileName = url.lastPathComponent
                return LUTDescriptor(
                    id: deterministicID(for: fileName),
                    title: builtInTitle(fileName: fileName, parsed: parsed),
                    source: .builtIn,
                    fileName: fileName,
                    cubeSize: parsed.cubeSize,
                    previewTintHex: previewTintHex(from: parsed),
                    warnings: parsed.warnings
                )
            }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    func loadParsedLUT(for descriptor: LUTDescriptor) throws -> ParsedLUT {
        let url: URL

        switch descriptor.source {
        case .builtIn:
            guard let fileName = descriptor.fileName,
                  let directoryURL = builtInLUTDirectoryURL else {
                throw LUTImportError.missingLUTFile(descriptor.fileName ?? descriptor.title)
            }
            url = directoryURL.appendingPathComponent(fileName)
        case .imported:
            guard let fileName = descriptor.fileName else {
                throw LUTImportError.missingLUTFile(descriptor.title)
            }
            url = lutDirectoryURL.appendingPathComponent(fileName)
        }

        guard fileManager.fileExists(atPath: url.path) else {
            throw LUTImportError.missingLUTFile(url.lastPathComponent)
        }

        do {
            return try parser.parse(String(contentsOf: url, encoding: .utf8))
        } catch let error as LUTImportError {
            throw error
        } catch {
            throw LUTImportError.unreadableFile(error.localizedDescription)
        }
    }

    func importLUT(from url: URL) async throws -> LUTDescriptor {
        guard url.pathExtension.lowercased() == "cube" else {
            // fileImporter 可能被系统或用户绕过扩展名过滤，因此 repository 仍要再次校验。
            throw LUTImportError.unsupportedExtension
        }

        // 支持从 Files app 选择沙盒外文件；访问结束后必须释放 security-scoped resource。
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess { url.stopAccessingSecurityScopedResource() }
        }

        let contents: String
        do {
            contents = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw LUTImportError.unreadableFile(error.localizedDescription)
        }

        // 先完整解析再写入 documents，避免保存无法使用的 LUT 副本。
        let parsed = try parser.parse(contents)
        try fileManager.createDirectory(at: lutDirectoryURL, withIntermediateDirectories: true)

        let id = UUID()
        // 使用 UUID 文件名避免不同来源的同名 LUT 互相覆盖。
        let targetFileName = "\(id.uuidString).cube"
        let targetURL = lutDirectoryURL.appendingPathComponent(targetFileName)
        try contents.write(to: targetURL, atomically: true, encoding: .utf8)

        let descriptor = LUTDescriptor(
            id: id,
            title: parsed.title ?? url.deletingPathExtension().lastPathComponent,
            source: .imported,
            fileName: targetFileName,
            cubeSize: parsed.cubeSize,
            previewTintHex: previewTintHex(from: parsed),
            warnings: parsed.warnings
        )

        var descriptors = loadImportedDescriptors()
        descriptors.append(descriptor)
        // index 原子写入，降低导入过程中 App 被杀导致 metadata 半写入的风险。
        let data = try JSONEncoder().encode(descriptors)
        try data.write(to: indexURL, options: .atomic)

        return descriptor
    }

    private var documentsURL: URL {
        documentsURLOverride ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private var lutDirectoryURL: URL {
        documentsURL.appendingPathComponent("ImportedLUTs", isDirectory: true)
    }

    private var indexURL: URL {
        documentsURL.appendingPathComponent(indexFileName)
    }

    private var builtInLUTDirectoryURL: URL? {
        if let builtInLUTDirectoryURLOverride {
            return builtInLUTDirectoryURLOverride
        }

        if let resourceURL = bundle.resourceURL {
            let folderURL = resourceURL.appendingPathComponent("LUTs", isDirectory: true)
            if fileManager.fileExists(atPath: folderURL.path) {
                return folderURL
            }
        }

        return bundle.url(forResource: "LUTs", withExtension: nil)
    }

    private func previewTintHex(from lut: ParsedLUT) -> String {
        guard !lut.entries.isEmpty else { return "#FFFFFF" }

        // 只抽样最多 128 个点，避免为了一个 UI 色块遍历大型 LUT 全量数据。
        let sampleCount = min(lut.entries.count, 128)
        let stride = max(lut.entries.count / sampleCount, 1)
        var red = 0.0
        var green = 0.0
        var blue = 0.0
        var count = 0.0

        for index in Swift.stride(from: 0, to: lut.entries.count, by: stride) {
            red += lut.entries[index].x
            green += lut.entries[index].y
            blue += lut.entries[index].z
            count += 1
        }

        // 使用平均色作为首版 UI 预览色；真正的 3D LUT 采样后续在 renderer 中实现。
        let r = Int(min(max(red / count, 0), 1) * 255)
        let g = Int(min(max(green / count, 0), 1) * 255)
        let b = Int(min(max(blue / count, 0), 1) * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    private func builtInTitle(fileName: String, parsed: ParsedLUT) -> String {
        if fileName.localizedCaseInsensitiveContains("N-Log"),
           fileName.localizedCaseInsensitiveContains("REC709") {
            return "Nikon N-Log to Rec.709 (Local)"
        }

        return parsed.title ?? URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
    }

    private func deterministicID(for fileName: String) -> UUID {
        var bytes = [UInt8](repeating: 0, count: 16)
        let seed = Array("PrismBlade.LocalLUT.\(fileName)".utf8)

        for (index, value) in seed.enumerated() {
            let byteIndex = index % bytes.count
            bytes[byteIndex] = bytes[byteIndex] &* 31 &+ value &+ UInt8(index & 0xFF)
        }

        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80

        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
