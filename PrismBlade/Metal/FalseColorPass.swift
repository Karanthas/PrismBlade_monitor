enum FalseColorPass {
    static func enabledFlag(for monitor: MonitorState) -> Float {
        monitor.falseColorEnabled ? 1 : 0
    }
}
