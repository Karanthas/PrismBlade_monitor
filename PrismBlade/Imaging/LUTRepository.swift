import Foundation

final class LUTRepository {
    private let parser = LUTParser()
    private let fileManager = FileManager.default
    // 单独保存 metadata index，避免每次启动都重新解析全部 .cube 文件。
    private let indexFileName = "lut-index.json"

    func loadImportedDescriptors() -> [LUTDescriptor] {
        // index 缺失或损坏时返回空数组，让 App 仍可进入监看界面。
        guard let data = try? Data(contentsOf: indexURL) else { return [] }
        return (try? JSONDecoder().decode([LUTDescriptor].self, from: data)) ?? []
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
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private var lutDirectoryURL: URL {
        documentsURL.appendingPathComponent("ImportedLUTs", isDirectory: true)
    }

    private var indexURL: URL {
        documentsURL.appendingPathComponent(indexFileName)
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
}
