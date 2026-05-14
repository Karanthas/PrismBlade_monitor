import SwiftUI

struct MonitorScreen: View {
    @ObservedObject var session: MonitorSession
    @State private var activeSheet: MonitorSheet?
    // v0.1.3 将参数浮层状态上移到父级，便于预览区点击关闭和 Scope 动态避让共享状态。
    @State private var selectedCameraParameter: CameraParameter?

    var body: some View {
        GeometryReader { proxy in
            let isPortrait = proxy.size.height > proxy.size.width
            let usePortraitLayout = isPortrait && session.state.orientation.allowsPortraitMonitoring
            // v0.1.2 要求 Scope 不再大面积遮挡画面，宽度固定为当前画面宽度的 40%。
            let scopeWidth = proxy.size.width * 0.4
            let hasParameterAdjuster = selectedCameraParameter != nil
            let controlsAvoidance = MonitorLayoutMetrics.controlStackAvoidance(hasAdjuster: hasParameterAdjuster)

            ZStack(alignment: .bottom) {
                Color.black.ignoresSafeArea()

                MetalPreviewSurface(
                    frame: session.latestFrame,
                    monitor: session.state.monitor,
                    lut: session.state.lut,
                    lutStore: session.lutStore
                )
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    // 点击监看画面空白处只负责收起参数浮层，不改变任何相机状态。
                    selectedCameraParameter = nil
                }

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
                        // Scope 根据底部控制条和调整浮层动态避让，避免 v0.1.2 中可能出现的重叠。
                        .padding(.bottom, controlsAvoidance)
                    }
                }

                toolRails(usePortraitLayout: usePortraitLayout)

                if let message = session.lastUserMessage {
                    UserMessageBanner(message: message)
                        .padding(.horizontal, usePortraitLayout ? 12 : 80)
                        // 短提示脱离调整浮层独立展示，禁用项点击时也能被用户看到。
                        .padding(.bottom, controlsAvoidance + MonitorLayoutMetrics.messageGap)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // 相机控制从 v0.1.1 的右侧面板改为 v0.1.2 的底部常驻控制条。
                CameraControlPanel(session: session, selectedParameter: $selectedCameraParameter)
                    .padding(.horizontal, usePortraitLayout ? 8 : 12)
                    .padding(.bottom, MonitorLayoutMetrics.controlBarBottomPadding)
            }
            .animation(.easeInOut(duration: 0.18), value: selectedCameraParameter)
            .animation(.easeInOut(duration: 0.18), value: session.lastUserMessage)
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

enum MonitorLayoutMetrics {
    static let controlBarBottomPadding: CGFloat = 8
    static let controlBarHeight: CGFloat = 60
    static let controlPanelSpacing: CGFloat = 8
    static let parameterAdjusterHeight: CGFloat = 118
    static let scopeToControlsGap: CGFloat = 10
    static let messageGap: CGFloat = 8

    static func controlStackAvoidance(hasAdjuster: Bool) -> CGFloat {
        // 这里用稳定估算值约束 overlay 避让；调整浮层本身也设置最小高度来减少布局抖动。
        controlBarBottomPadding +
            controlBarHeight +
            scopeToControlsGap +
            (hasAdjuster ? controlPanelSpacing + parameterAdjusterHeight : 0)
    }
}

private struct UserMessageBanner: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.yellow)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.black.opacity(0.74))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityLabel(message)
    }
}
