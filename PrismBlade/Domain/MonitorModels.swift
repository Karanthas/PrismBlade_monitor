import Foundation

struct MonitorSessionState: Equatable {
    var connection: ConnectionState = .disconnected
    var camera: CameraState = .mockInitial
    var monitor: MonitorState = .initial
    var orientation: OrientationState = .initial
    var lut: LUTState = .initial
}

struct ScopeData: Equatable {
    var lumaBins: [Float]
    var redBins: [Float]
    var greenBins: [Float]
    var blueBins: [Float]
    var binWidth: Int
    var binHeight: Int
    var sourceSequence: Int

    var isValid: Bool {
        let expectedCount = binWidth * binHeight
        return binWidth > 0 &&
            binHeight > 0 &&
            lumaBins.count == expectedCount &&
            redBins.count == expectedCount &&
            greenBins.count == expectedCount &&
            blueBins.count == expectedCount
    }
}

enum ConnectionState: Equatable {
    case disconnected
    case noCamera
    case searching
    case connecting
    case reconnecting(attempt: Int)
    case connected
    case permissionDenied(String)
    case unsupported(String)
    case interrupted(String)
    case failed(String)

    var title: String {
        switch self {
        case .disconnected:
            return "未连接"
        case .noCamera:
            return "等待相机"
        case .searching:
            return "搜索中"
        case .connecting:
            return "连接中"
        case .reconnecting:
            return "重连中"
        case .connected:
            return "已连接"
        case .permissionDenied:
            return "相机权限受限"
        case .unsupported:
            return "相机不支持"
        case .interrupted:
            return "连接中断"
        case .failed:
            return "连接错误"
        }
    }

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    var diagnosticName: String {
        switch self {
        case .disconnected:
            return "disconnected"
        case .noCamera:
            return "noCamera"
        case .searching:
            return "searching"
        case .connecting:
            return "connecting"
        case .reconnecting:
            return "reconnecting"
        case .connected:
            return "connected"
        case .permissionDenied:
            return "permissionDenied"
        case .unsupported:
            return "unsupported"
        case .interrupted:
            return "interrupted"
        case .failed:
            return "failed"
        }
    }

    var previewPrompt: (title: String, message: String)? {
        switch self {
        case .noCamera:
            return ("连接 Nikon Z6III", "请连接已验证的 Nikon Z6III USB/PTP 相机。")
        case .permissionDenied(let message):
            return ("允许相机权限", message)
        case .unsupported(let message):
            return ("相机不可用", message)
        case .failed(let message):
            return ("连接失败", message)
        case .interrupted(let message):
            return ("连接中断", message)
        case .searching:
            return ("正在搜索相机", "正在等待 Nikon Z6III 出现。")
        case .reconnecting(let attempt):
            return ("正在重连相机", "正在尝试恢复 Nikon Z6III 连接（第 \(attempt) 次）。")
        default:
            return nil
        }
    }
}

struct MonitorState: Equatable {
    var falseColorEnabled: Bool
    var falseColorDefaultEnabled: Bool
    var zebraEnabled: Bool
    var zebraDefaultEnabled: Bool
    var zebraMode: ZebraMode
    var zebraThreshold: Double
    var scopeMode: ScopeMode
    var scopeOpacity: Double
    var scopeDockPosition: ScopeDockPosition
    var exposureAnalysisSource: ExposureAnalysisSource
    var zoomMode: ZoomMode
    var previewFitMode: PreviewFitMode

    static let initial = MonitorState(
        falseColorEnabled: false,
        falseColorDefaultEnabled: false,
        zebraEnabled: false,
        zebraDefaultEnabled: false,
        zebraMode: .high,
        zebraThreshold: 90,
        scopeMode: .lumaWaveform,
        scopeOpacity: 0.72,
        scopeDockPosition: .bottomLeft,
        exposureAnalysisSource: .rawSignal,
        zoomMode: .fit,
        previewFitMode: .fit
    )
}

enum ZebraMode: String, CaseIterable, Identifiable, Equatable {
    case high
    case range

    var id: String { rawValue }

    var title: String {
        switch self {
        case .high: return "High"
        case .range: return "Range"
        }
    }
}

enum ScopeMode: String, CaseIterable, Identifiable, Equatable {
    case off
    case lumaWaveform
    case rgbParade

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "Off"
        case .lumaWaveform: return "Waveform"
        case .rgbParade: return "RGB Parade"
        }
    }
}

enum ScopeDockPosition: String, CaseIterable, Identifiable, Equatable {
    case bottomLeft
    case bottomRight
    case topLeft
    case topRight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bottomLeft: return "Bottom Left"
        case .bottomRight: return "Bottom Right"
        case .topLeft: return "Top Left"
        case .topRight: return "Top Right"
        }
    }

    var isTop: Bool {
        self == .topLeft || self == .topRight
    }

    var isLeading: Bool {
        self == .bottomLeft || self == .topLeft
    }
}

enum ExposureAnalysisSource: String, CaseIterable, Identifiable, Equatable {
    case rawSignal
    case previewDisplay

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rawSignal: return "Raw Signal"
        case .previewDisplay: return "Preview Display"
        }
    }

    var compactTitle: String {
        switch self {
        case .rawSignal: return "Raw"
        case .previewDisplay: return "LUT"
        }
    }
}

enum ZoomMode: String, CaseIterable, Identifiable, Equatable {
    case fit
    case fill
    case oneX
    case twoX

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fit: return "Fit"
        case .fill: return "Fill"
        case .oneX: return "1x"
        case .twoX: return "2x"
        }
    }
}

enum PreviewFitMode: String, CaseIterable, Identifiable, Equatable {
    case fit
    case fill

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct OrientationState: Equatable {
    var allowsPortraitMonitoring: Bool
    var currentOrientation: AppOrientation
    var previewFitMode: PreviewFitMode

    static let initial = OrientationState(
        allowsPortraitMonitoring: false,
        currentOrientation: .landscape,
        previewFitMode: .fit
    )
}

enum AppOrientation: String, Equatable {
    case landscape
    case portrait
}
