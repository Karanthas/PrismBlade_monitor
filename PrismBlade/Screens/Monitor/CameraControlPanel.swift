import SwiftUI

struct CameraControlPanel: View {
    @ObservedObject var session: MonitorSession
    // 记录当前正在调整的参数；nil 表示只显示底部常驻参数条。
    @State private var selectedParameter: CameraParameter?

    // v0.1.2 要求底部直接暴露这些核心相机参数，顺序贴近相机监看常用读取顺序。
    private let visibleParameters: [CameraParameter] = [
        .exposureMode,
        .aperture,
        .shutter,
        .iso,
        .whiteBalance,
        .focusMode
    ]

    var body: some View {
        VStack(spacing: 8) {
            if let selectedParameter {
                // 调整浮层只在用户点击可用参数后出现，避免长期遮挡监看画面。
                parameterAdjuster(for: selectedParameter)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            HStack(spacing: 8) {
                ForEach(visibleParameters) { parameter in
                    parameterCell(parameter)
                }

                Divider()
                    .overlay(.white.opacity(0.18))
                    .frame(height: 38)

                actionButton(
                    title: session.state.camera.isRecording ? "停止" : "REC",
                    systemImage: "record.circle",
                    tint: session.state.camera.isRecording ? .red : .white
                ) {
                    session.triggerCameraAction(.toggleRecord)
                }

                actionButton(title: "拍照", systemImage: "camera.circle", tint: .white) {
                    session.triggerCameraAction(.capture)
                }

                actionButton(title: "AF", systemImage: "scope", tint: .white) {
                    session.triggerCameraAction(.focus)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.black.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .foregroundStyle(.white)
        .font(.caption)
        .animation(.easeInOut(duration: 0.18), value: selectedParameter)
    }

    private func parameterCell(_ parameter: CameraParameter) -> some View {
        // value 和 availability 分开读取，便于同时表达“当前值”和“当前模式是否允许调整”。
        let value = session.cameraValue(for: parameter)
        let availability = session.availability(for: parameter)
        let isSelected = selectedParameter == parameter

        return Button {
            if availability.isEnabled {
                // 再次点击同一个参数会收起浮层，便于单手快速回到纯监看状态。
                selectedParameter = isSelected ? nil : parameter
            } else {
                // 禁用项不打开调整器，只显示原因，例如 A 档下快门由相机控制。
                selectedParameter = nil
                session.showDisabledParameterReason(for: parameter)
            }
        } label: {
            VStack(spacing: 3) {
                HStack(spacing: 4) {
                    Text(parameter.title)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(availability.isEnabled ? .white.opacity(0.62) : .white.opacity(0.32))

                    if value.isSubmitting {
                        // 提交中状态贴在参数 label 旁边，避免用户误以为滑块没有生效。
                        ProgressView()
                            .controlSize(.mini)
                            .tint(.white)
                    }
                }

                Text(displayValue(for: parameter, value: value.current))
                    .font(.callout.monospacedDigit().weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
            }
            .frame(minWidth: parameter == .exposureMode ? 56 : 76, maxWidth: .infinity, minHeight: 44)
            .foregroundStyle(availability.isEnabled ? .white : .white.opacity(0.34))
            .background(isSelected ? .white.opacity(0.18) : .black.opacity(0.38))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(parameter.title) \(value.current)")
    }

    private func parameterAdjuster(for parameter: CameraParameter) -> some View {
        let value = session.cameraValue(for: parameter)
        // options 来自 Mock/真实能力表，滑块只在这些离散档位之间跳转。
        let options = value.options

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(parameter.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.66))
                    Text(displayValue(for: parameter, value: value.current))
                        .font(.title3.monospacedDigit().weight(.bold))
                }

                Spacer()

                if parameter == .focusMode {
                    // 对焦更像动作而非连续数值，因此在模式滑块旁额外提供 AF 触发按钮。
                    Button {
                        session.triggerCameraAction(.focus)
                    } label: {
                        Label("AF", systemImage: "scope")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.white.opacity(0.22))
                }

                Button {
                    selectedParameter = nil
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
            }

            if options.count > 1 {
                // Slider 使用 step: 1，把连续拖动映射到相机离散档位。
                Slider(
                    value: sliderBinding(for: parameter, value: value),
                    in: 0...Double(options.count - 1),
                    step: 1
                )
                .tint(.yellow)

                HStack {
                    Text(displayValue(for: parameter, value: options.first ?? value.current))
                    Spacer()
                    Text(displayValue(for: parameter, value: value.current))
                        .foregroundStyle(.yellow)
                    Spacer()
                    Text(displayValue(for: parameter, value: options.last ?? value.current))
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.white.opacity(0.62))
            } else {
                Text("当前参数没有可选项")
                    .foregroundStyle(.white.opacity(0.62))
            }

            if let message = session.lastUserMessage {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.yellow)
                    .lineLimit(1)
            }
        }
        .padding(12)
        .background(.black.opacity(0.76))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func actionButton(title: String, systemImage: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))
                Text(title)
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(tint)
            .frame(width: 52, height: 44)
            .background(.black.opacity(0.38))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        // 未连接时禁用动作按钮，避免向 Mock transport 发送一定会失败的动作命令。
        .disabled(!session.state.connection.isConnected)
    }

    private func sliderBinding(for parameter: CameraParameter, value: CameraValue) -> Binding<Double> {
        Binding(
            get: {
                // 当前字符串值反查到 options 下标，作为离散 slider 的当前位置。
                Double(value.options.firstIndex(of: value.current) ?? 0)
            },
            set: { newIndex in
                // round + clamp 确保拖动过程中不会访问 options 越界。
                let index = min(max(Int(newIndex.rounded()), 0), value.options.count - 1)
                let option = value.options[index]

                // 值没有变化时不重复提交，减少 Mock 延迟和 UI loading 抖动。
                guard option != value.current else { return }
                session.setCameraParameter(parameter, to: option)
            }
        )
    }

    private func displayValue(for parameter: CameraParameter, value: String) -> String {
        switch parameter {
        case .iso:
            // ISO 在底部条中补上前缀，避免和其他纯数字参数混淆。
            return "ISO \(value)"
        default:
            return value
        }
    }
}
