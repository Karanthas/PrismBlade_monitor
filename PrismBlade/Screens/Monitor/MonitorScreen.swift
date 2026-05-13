import SwiftUI

struct MonitorScreen: View {
    @ObservedObject var session: MonitorSession
    @State private var activeSheet: MonitorSheet?

    var body: some View {
        GeometryReader { proxy in
            let isPortrait = proxy.size.height > proxy.size.width
            let usePortraitLayout = isPortrait && session.state.orientation.allowsPortraitMonitoring
            // v0.1.2 要求 Scope 不再大面积遮挡画面，宽度固定为当前画面宽度的 40%。
            let scopeWidth = proxy.size.width * 0.4

            ZStack(alignment: .bottom) {
                Color.black.ignoresSafeArea()

                SyntheticPreviewView(
                    frame: session.latestFrame,
                    monitor: session.state.monitor,
                    lut: session.state.lut,
                    isPortraitLayout: usePortraitLayout
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    statusBar
                    Spacer()
                    if session.state.monitor.scopeMode != .off {
                        HStack {
                            // Scope 放在底部左侧，并预留底部控制条高度，避免和相机参数条重叠。
                            ScopePanel(
                                mode: session.state.monitor.scopeMode,
                                opacity: session.state.monitor.scopeOpacity,
                                frame: session.latestFrame
                            )
                            .frame(width: scopeWidth, height: usePortraitLayout ? 118 : 132)
                            .padding(.leading, usePortraitLayout ? 12 : 72)
                            Spacer()
                        }
                        .padding(.bottom, usePortraitLayout ? 86 : 82)
                    }
                }

                toolRails(usePortraitLayout: usePortraitLayout)

                // 相机控制从 v0.1.1 的右侧面板改为 v0.1.2 的底部常驻控制条。
                CameraControlPanel(session: session)
                    .padding(.horizontal, usePortraitLayout ? 8 : 12)
                    .padding(.bottom, 8)
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .settings:
                    SettingsScreen(session: session)
                case .lutManager:
                    LUTManagerScreen(session: session)
                }
            }
        }
    }

    private var statusBar: some View {
        HStack(spacing: 14) {
            Label(session.state.connection.title, systemImage: session.state.connection.isConnected ? "cable.connector" : "cable.connector.slash")
            Text("\(Int(session.latestFrame.format.resolution.width))x\(Int(session.latestFrame.format.resolution.height))")
            Text("\(Int(session.latestFrame.format.frameRate))fps")
            Text(session.latestFrame.format.colorEncoding.rawValue)

            if session.state.lut.isEnabled {
                Text("LUT \(session.state.lut.selectedLUT?.title ?? "On")")
            }

            if session.state.monitor.falseColorEnabled { Text("FC") }
            if session.state.monitor.zebraEnabled { Text("Zebra \(Int(session.state.monitor.zebraThreshold))%") }

            Spacer()

            Text("BAT \(session.state.camera.batteryLevel ?? 0)%")
            Text(session.state.camera.storageRemaining.map { "\($0.cardLabel) \($0.minutes)m" } ?? "Card --")
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.white)
        .lineLimit(1)
        .minimumScaleFactor(0.72)
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(.black.opacity(0.44))
    }

    private func toolRails(usePortraitLayout: Bool) -> some View {
        HStack {
            VStack(spacing: 12) {
                toolButton("False Color", systemImage: "camera.filters", isActive: session.state.monitor.falseColorEnabled) {
                    session.toggleFalseColor()
                }
                toolButton("Zebra", systemImage: "line.diagonal", isActive: session.state.monitor.zebraEnabled) {
                    session.toggleZebra()
                }
                toolButton("Scope", systemImage: "waveform.path.ecg", isActive: session.state.monitor.scopeMode != .off) {
                    cycleScopeMode()
                }
                toolButton("LUT", systemImage: "slider.horizontal.3", isActive: session.state.lut.isEnabled) {
                    activeSheet = .lutManager
                }
                Spacer()
            }
            .padding(.leading, usePortraitLayout ? 10 : 16)
            .padding(.top, 62)

            Spacer()

            VStack(spacing: 12) {
                toolButton("Zoom", systemImage: "plus.magnifyingglass", isActive: session.state.monitor.zoomMode != .fit) {
                    cycleZoomMode()
                }
                toolButton("Settings", systemImage: "gearshape", isActive: false) {
                    activeSheet = .settings
                }
                Spacer()
            }
            .padding(.trailing, usePortraitLayout ? 10 : 16)
            .padding(.top, 62)
        }
    }

    private func toolButton(_ title: String, systemImage: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(isActive ? .black : .white)
                .frame(width: 44, height: 44)
                .background(isActive ? .yellow : .black.opacity(0.52))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .accessibilityLabel(title)
    }

    private func cycleScopeMode() {
        let modes = ScopeMode.allCases
        let currentIndex = modes.firstIndex(of: session.state.monitor.scopeMode) ?? 0
        // 工具按钮按 off -> waveform -> RGB parade 循环，避免再增加一个占屏菜单。
        session.setScopeMode(modes[(currentIndex + 1) % modes.count])
    }

    private func cycleZoomMode() {
        let modes = ZoomMode.allCases
        let currentIndex = modes.firstIndex(of: session.state.monitor.zoomMode) ?? 0
        session.setZoomMode(modes[(currentIndex + 1) % modes.count])
    }
}

private enum MonitorSheet: String, Identifiable {
    case settings
    case lutManager

    var id: String { rawValue }
}
