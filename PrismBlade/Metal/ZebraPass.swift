enum ZebraPass {
    static func enabledFlag(for monitor: MonitorState) -> Float {
        monitor.zebraEnabled ? 1 : 0
    }

    static func modeCode(for mode: ZebraMode) -> Float {
        switch mode {
        case .high:
            return 0
        case .range:
            return 1
        }
    }

    static func thresholdFraction(for monitor: MonitorState) -> Float {
        min(max(Float(monitor.zebraThreshold / 100), 0), 1)
    }
}
