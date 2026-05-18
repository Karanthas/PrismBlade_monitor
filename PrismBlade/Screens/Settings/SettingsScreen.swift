import SwiftUI

struct SettingsScreen: View {
    @ObservedObject var session: MonitorSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("方向") {
                    Toggle("允许竖屏拍摄/监看", isOn: Binding(
                        get: { session.state.orientation.allowsPortraitMonitoring },
                        set: { session.setPortraitMonitoringAllowed($0) }
                    ))
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

                Section("Mock 调试") {
                    Button("重新连接 Mock 相机") {
                        session.reconnectMockCamera()
                    }

                    Button("模拟断开") {
                        session.simulateMockDisconnect()
                    }
                    .foregroundStyle(.red)
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
