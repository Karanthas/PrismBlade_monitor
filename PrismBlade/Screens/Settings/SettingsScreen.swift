import SwiftUI
import UIKit

struct SettingsScreen: View {
    @ObservedObject var session: MonitorSession
    var onRealCameraModeChange: (Bool) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss
    @State private var diagnosticsCopyStatus: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("方向") {
                    Toggle("允许竖屏拍摄/监看", isOn: Binding(
                        get: { session.state.orientation.allowsPortraitMonitoring },
                        set: { session.setPortraitMonitoringAllowed($0) }
                    ))
                }

                Section("相机模式") {
                    Toggle("真实相机模式", isOn: Binding(
                        get: { session.isRealCameraMode },
                        set: { onRealCameraModeChange($0) }
                    ))

                    Text(session.isRealCameraMode ? "当前使用 ImageCaptureCore / Nikon PTP 连接。" : "当前使用 Mock 相机和模拟画面。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("曝光辅助") {
                    Toggle("默认开启伪色", isOn: Binding(
                        get: { session.state.monitor.falseColorDefaultEnabled },
                        set: { session.setFalseColorDefaultEnabled($0) }
                    ))

                    Toggle("默认开启斑马纹", isOn: Binding(
                        get: { session.state.monitor.zebraDefaultEnabled },
                        set: { session.setZebraDefaultEnabled($0) }
                    ))

                    Picker("斑马纹模式", selection: Binding(
                        get: { session.state.monitor.zebraMode },
                        set: { session.setZebraMode($0) }
                    )) {
                        ForEach(ZebraMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }

                    VStack(alignment: .leading) {
                        Text("斑马纹阈值 \(Int(session.state.monitor.zebraThreshold))%")
                        Slider(
                            value: Binding(
                                get: { session.state.monitor.zebraThreshold },
                                set: { session.setZebraThreshold($0) }
                            ),
                            in: 50...100,
                            step: 1
                        )
                    }
                }

                Section("Scope") {
                    Picker("模式", selection: Binding(
                        get: { session.state.monitor.scopeMode },
                        set: { session.setScopeMode($0) }
                    )) {
                        ForEach(ScopeMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }

                    Picker("曝光分析源", selection: Binding(
                        get: { session.state.monitor.exposureAnalysisSource },
                        set: { session.setExposureAnalysisSource($0) }
                    )) {
                        ForEach(ExposureAnalysisSource.allCases) { source in
                            Text(source.title).tag(source)
                        }
                    }

                    Picker("位置", selection: Binding(
                        get: { session.state.monitor.scopeDockPosition },
                        set: { session.setScopeDockPosition($0) }
                    )) {
                        ForEach(ScopeDockPosition.allCases) { position in
                            Text(position.title).tag(position)
                        }
                    }

                    VStack(alignment: .leading) {
                        Text("透明度 \(Int(session.state.monitor.scopeOpacity * 100))%")
                        Slider(
                            value: Binding(
                                get: { session.state.monitor.scopeOpacity },
                                set: { session.setScopeOpacity($0) }
                            ),
                            in: 0.35...0.9,
                            step: 0.01
                        )
                    }
                }

                Section(session.isRealCameraMode ? "相机连接" : "Mock 调试") {
                    Button(session.isRealCameraMode ? "重新连接相机" : "重新连接 Mock 相机") {
                        session.reconnectCamera()
                    }

                    if !session.isRealCameraMode {
                        Button("模拟断开") {
                            session.simulateMockDisconnect()
                        }
                        .foregroundStyle(.red)
                    }
                }

                Section("诊断日志") {
                    Button("复制日志") {
                        UIPasteboard.general.string = session.diagnosticLogText()
                        diagnosticsCopyStatus = "已复制到剪贴板"
                        session.showUserMessage("诊断日志已复制")
                    }

                    Button("清空日志") {
                        session.clearDiagnosticLog()
                        diagnosticsCopyStatus = "已清空"
                    }
                    .foregroundStyle(.red)

                    if let diagnosticsCopyStatus {
                        Text(diagnosticsCopyStatus)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("设置")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
