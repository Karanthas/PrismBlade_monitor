import Foundation
import SwiftUI

struct LUTState: Equatable {
    var selectedLUT: LUTDescriptor?
    var importedLUTs: [LUTDescriptor]
    var builtInLUTs: [LUTDescriptor]
    var intensity: Double
    var isEnabled: Bool
    var lastImportError: LUTImportError?

    static let initial = LUTState(
        selectedLUT: nil,
        importedLUTs: [],
        builtInLUTs: [],
        intensity: 1,
        isEnabled: false,
        lastImportError: nil
    )
}

struct LUTDescriptor: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var source: LUTSource
    var fileName: String?
    var cubeSize: Int
    var previewTintHex: String
    var warnings: [String]

    var tintColor: Color {
        Color(hex: previewTintHex)
    }
}

enum LUTSource: String, Codable, Hashable {
    case builtIn
    case imported
}

struct ParsedLUT: Equatable {
    var title: String?
    var cubeSize: Int
    var domainMin: SIMD3<Double>
    var domainMax: SIMD3<Double>
    var entries: [SIMD3<Double>]
    var warnings: [String]
}

enum LUTImportError: Error, Equatable, LocalizedError {
    case unreadableFile(String)
    case unsupportedExtension
    case missingCubeSize
    case invalidCubeSize(String)
    case invalidRGBLine(line: Int, value: String)
    case dataCountMismatch(expected: Int, actual: Int)
    case sizeTooLarge(Int)
    case missingLUTFile(String)

    var errorDescription: String? {
        switch self {
        case .unreadableFile(let message):
            return "无法读取文件：\(message)"
        case .unsupportedExtension:
            return "请选择 .cube LUT 文件"
        case .missingCubeSize:
            return "缺少 LUT_3D_SIZE"
        case .invalidCubeSize(let value):
            return "LUT_3D_SIZE 无效：\(value)"
        case .invalidRGBLine(let line, let value):
            return "第 \(line) 行 RGB 数据无效：\(value)"
        case .dataCountMismatch(let expected, let actual):
            return "LUT 数据数量不匹配，需要 \(expected) 行，实际 \(actual) 行"
        case .sizeTooLarge(let size):
            return "LUT 尺寸过大：\(size)"
        case .missingLUTFile(let fileName):
            return "找不到 LUT 文件：\(fileName)"
        }
    }
}

extension Color {
    init(hex: String) {
        let value = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var rgb: UInt64 = 0
        Scanner(string: value).scanHexInt64(&rgb)

        let red = Double((rgb >> 16) & 0xFF) / 255
        let green = Double((rgb >> 8) & 0xFF) / 255
        let blue = Double(rgb & 0xFF) / 255
        self.init(red: red, green: green, blue: blue)
    }
}
