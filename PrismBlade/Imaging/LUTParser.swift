import Foundation

struct LUTParser {
    // v0.1.x 先限制最大 65^3，防止用户导入超大 LUT 阻塞模拟器原型。
    private let maxSupportedSize = 65

    func parse(_ contents: String) throws -> ParsedLUT {
        var title: String?
        var cubeSize: Int?
        var domainMin = SIMD3<Double>(0, 0, 0)
        var domainMax = SIMD3<Double>(1, 1, 1)
        var entries: [SIMD3<Double>] = []
        var warnings: [String] = []

        let lines = contents.components(separatedBy: .newlines)

        for (index, rawLine) in lines.enumerated() {
            let lineNumber = index + 1
            // .cube 使用 # 注释；解析前先移除注释和空白，保证后续分支只处理有效内容。
            let line = rawLine
                .components(separatedBy: "#")
                .first?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            guard !line.isEmpty else { continue }

            if line.uppercased().hasPrefix("TITLE") {
                // TITLE 可选；缺失时 LUTRepository 会使用文件名作为展示名称。
                title = parseTitle(line)
                continue
            }

            if line.uppercased().hasPrefix("LUT_3D_SIZE") {
                // LUT_3D_SIZE 是首版唯一强制尺寸声明，用它校验数据行数量。
                cubeSize = try parseCubeSize(line)
                continue
            }

            if line.uppercased().hasPrefix("DOMAIN_MIN") {
                domainMin = try parseDomain(line, lineNumber: lineNumber)
                continue
            }

            if line.uppercased().hasPrefix("DOMAIN_MAX") {
                domainMax = try parseDomain(line, lineNumber: lineNumber)
                continue
            }

            let rgb = try parseRGBLine(line, lineNumber: lineNumber)
            // 首版显示链路按 0...1 处理，超出范围先 clamp 并记录 warning。
            let clamped = SIMD3<Double>(
                min(max(rgb.x, 0), 1),
                min(max(rgb.y, 0), 1),
                min(max(rgb.z, 0), 1)
            )

            if clamped != rgb {
                // v0.1.1 先 clamp 非 0-1 数据，同时把风险反馈给 LUT 管理界面。
                warnings.append("第 \(lineNumber) 行存在 0-1 范围外数据，已 clamp")
            }

            entries.append(clamped)
        }

        guard let size = cubeSize else {
            // 没有尺寸就无法判断 entries 是否完整，因此直接作为导入失败处理。
            throw LUTImportError.missingCubeSize
        }

        guard size <= maxSupportedSize else {
            throw LUTImportError.sizeTooLarge(size)
        }

        let expectedCount = size * size * size
        guard entries.count == expectedCount else {
            // 数据行数必须精确匹配，防止后续生成 3D texture 时出现错位采样。
            throw LUTImportError.dataCountMismatch(expected: expectedCount, actual: entries.count)
        }

        return ParsedLUT(
            title: title,
            cubeSize: size,
            domainMin: domainMin,
            domainMax: domainMax,
            entries: entries,
            warnings: warnings
        )
    }

    private func parseTitle(_ line: String) -> String? {
        let value = line.dropFirst("TITLE".count)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))

        return value.isEmpty ? nil : value
    }

    private func parseCubeSize(_ line: String) throws -> Int {
        let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard parts.count == 2, let size = Int(parts[1]), size > 1 else {
            throw LUTImportError.invalidCubeSize(line)
        }

        return size
    }

    private func parseDomain(_ line: String, lineNumber: Int) throws -> SIMD3<Double> {
        let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard parts.count == 4,
              let red = Double(parts[1]),
              let green = Double(parts[2]),
              let blue = Double(parts[3]) else {
            throw LUTImportError.invalidRGBLine(line: lineNumber, value: line)
        }

        return SIMD3<Double>(red, green, blue)
    }

    private func parseRGBLine(_ line: String, lineNumber: Int) throws -> SIMD3<Double> {
        let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard parts.count == 3,
              let red = Double(parts[0]),
              let green = Double(parts[1]),
              let blue = Double(parts[2]) else {
            throw LUTImportError.invalidRGBLine(line: lineNumber, value: line)
        }

        return SIMD3<Double>(red, green, blue)
    }
}
