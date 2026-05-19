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
    case searching
    case connecting
    case connected
    case interrupted(String)
    case failed(String)

    var title: String {
        switch self {
        case .disconnected:
            return "未连接"
        case .searching:
            return "搜索中"
        case .connecting:
            return "连接中"
        case .connected:
            return "Mock 已连接"
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
