import Foundation

struct CameraState: Equatable {
    // 曝光模式必须进入相机状态，而不是 UI 状态；真实相机接入后这里会来自机身当前模式。
    var exposureMode: CameraValue
    // 以下 CameraValue 均保留 options/isWritable/isSubmitting，方便 UI、命令层和真实能力表共享同一表达。
    var iso: CameraValue
    var shutter: CameraValue
    var aperture: CameraValue
    var whiteBalance: CameraValue
    var focusMode: CameraValue
    var isRecording: Bool
    var batteryLevel: Int?
    var storageRemaining: StorageInfo?
    var lastActionStatus: String?

    static let mockInitial = CameraState(
        // Mock 默认从 M 档启动，便于首屏验证光圈、快门、ISO 都可以调整。
        exposureMode: CameraValue(current: ExposureMode.manual.rawValue, options: ExposureMode.allCases.map(\.rawValue), isWritable: true),
        // 这里的档位使用离散字符串，刻意贴近相机拨盘式调整，避免 UI 生成相机不支持的任意值。
        iso: CameraValue(current: "400", options: ["100", "200", "400", "800", "1600", "3200", "6400"], isWritable: true),
        shutter: CameraValue(current: "1/50", options: ["1/25", "1/50", "1/60", "1/100", "1/125", "1/250"], isWritable: true),
        aperture: CameraValue(current: "f/2.8", options: ["f/1.8", "f/2.0", "f/2.8", "f/4.0", "f/5.6", "f/8.0"], isWritable: true),
        whiteBalance: CameraValue(current: "5600K", options: ["Auto", "3200K", "4300K", "5600K", "6500K"], isWritable: true),
        focusMode: CameraValue(current: "AF-S", options: ["AF-S", "AF-C", "MF", "Touch Focus"], isWritable: true),
        isRecording: false,
        batteryLevel: 82,
        storageRemaining: StorageInfo(minutes: 73, cardLabel: "Card A"),
        lastActionStatus: nil
    )
}

struct CameraValue: Equatable {
    // current/options 先使用 String，方便 Mock 和 UI 快速迭代；真实相机接入后可再升级为强类型值。
    var current: String
    var options: [String]
    // isWritable 表示“相机能力上是否可写”，不等于当前曝光模式下是否允许用户调整。
    var isWritable: Bool
    // isSubmitting 只服务 UI loading 状态，不应泄漏到真实 transport 协议里。
    var isSubmitting: Bool = false
}

enum ExposureMode: String, CaseIterable, Identifiable, Equatable {
    // 这些 rawValue 直接用于底部控制条显示，保持和相机模式拨盘一致。
    case manual = "M"
    case aperturePriority = "A"
    case shutterPriority = "S"
    case program = "P"
    case auto = "Auto"

    var id: String { rawValue }

    var title: String { rawValue }

    var longTitle: String {
        switch self {
        case .manual:
            return "Manual"
        case .aperturePriority:
            return "Aperture Priority"
        case .shutterPriority:
            return "Shutter Priority"
        case .program:
            return "Program"
        case .auto:
            return "Auto"
        }
    }
}

struct CameraParameterAvailability: Equatable {
    // isEnabled 由“连接状态 + 基础可写能力 + 当前曝光模式规则”共同决定。
    var isEnabled: Bool
    // reason 给 UI 展示短提示，避免用户点击置灰项后没有反馈。
    var reason: String?

    static let enabled = CameraParameterAvailability(isEnabled: true, reason: nil)
}

struct StorageInfo: Equatable {
    var minutes: Int
    var cardLabel: String
}

enum CameraParameter: String, CaseIterable, Identifiable {
    // exposureMode 作为普通参数进入 command flow，确保切换模式也走同一套 Mock/真实 transport 边界。
    case exposureMode
    case iso
    case shutter
    case aperture
    case whiteBalance
    case focusMode

    var id: String { rawValue }

    var title: String {
        switch self {
        case .exposureMode: return "模式"
        case .iso: return "ISO"
        case .shutter: return "快门"
        case .aperture: return "光圈"
        case .whiteBalance: return "白平衡"
        case .focusMode: return "对焦"
        }
    }
}

enum CameraExposureRules {
    static func availability(for parameter: CameraParameter, in mode: ExposureMode) -> CameraParameterAvailability {
        switch parameter {
        case .exposureMode, .focusMode:
            // v0.1.2 先允许随时改曝光模式和对焦模式；真实机身可在 capabilities 中继续收紧。
            return .enabled
        case .whiteBalance:
            if mode == .auto {
                // Auto 档模拟“全自动接管”，因此白平衡也在 Mock 中锁定。
                return CameraParameterAvailability(isEnabled: false, reason: "Auto 模式下白平衡由相机控制")
            }
            return .enabled
        case .iso:
            if mode == .auto {
                // A/S/P 下 v0.1.2 先允许 ISO 手动；Auto 档才锁定 ISO。
                return CameraParameterAvailability(isEnabled: false, reason: "Auto 模式下 ISO 由相机控制")
            }
            return .enabled
        case .aperture:
            switch mode {
            case .manual, .aperturePriority:
                // M/A 是用户主动选择光圈的模式，因此光圈可调。
                return .enabled
            case .shutterPriority:
                // S 档由相机根据快门自动决定光圈，UI 和 transport 都要锁定。
                return CameraParameterAvailability(isEnabled: false, reason: "当前 S 模式下光圈由相机控制")
            case .program:
                return CameraParameterAvailability(isEnabled: false, reason: "当前 P 模式下光圈由相机控制")
            case .auto:
                return CameraParameterAvailability(isEnabled: false, reason: "Auto 模式下曝光参数由相机控制")
            }
        case .shutter:
            switch mode {
            case .manual, .shutterPriority:
                // M/S 是用户主动选择快门的模式，因此快门可调。
                return .enabled
            case .aperturePriority:
                // A 档由相机根据光圈自动决定快门，UI 和 transport 都要锁定。
                return CameraParameterAvailability(isEnabled: false, reason: "当前 A 模式下快门由相机控制")
            case .program:
                return CameraParameterAvailability(isEnabled: false, reason: "当前 P 模式下快门由相机控制")
            case .auto:
                return CameraParameterAvailability(isEnabled: false, reason: "Auto 模式下曝光参数由相机控制")
            }
        }
    }
}

enum CameraAction {
    case toggleRecord
    case capture
    case halfPress
    case focus

    var successMessage: String {
        switch self {
        case .toggleRecord: return "录制状态已切换"
        case .capture: return "Mock 拍照完成"
        case .halfPress: return "Mock 半按完成"
        case .focus: return "Mock 对焦成功"
        }
    }
}

enum CameraTransportError: Error, LocalizedError {
    case notConnected
    case unsupportedValue(parameter: CameraParameter, value: String)
    // 这个错误专门区分“能力表不支持”和“当前模式临时锁定”，便于 UI 给出更准确提示。
    case parameterLockedByExposureMode(parameter: CameraParameter, mode: ExposureMode)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Mock 相机未连接"
        case .unsupportedValue(let parameter, let value):
            return "\(parameter.title) 不支持 \(value)"
        case .parameterLockedByExposureMode(let parameter, let mode):
            // 复用规则表生成提示，避免 UI、service、transport 三处维护不同文案。
            let availability = CameraExposureRules.availability(for: parameter, in: mode)
            return availability.reason ?? "\(mode.title) 模式下无法调整 \(parameter.title)"
        }
    }
}
