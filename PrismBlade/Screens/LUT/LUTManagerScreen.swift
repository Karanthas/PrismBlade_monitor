import SwiftUI
import UniformTypeIdentifiers

struct LUTManagerScreen: View {
    @ObservedObject var session: MonitorSession
    @Environment(\.dismiss) private var dismiss
    @State private var isImporterPresented = false

    private var cubeType: UTType {
        UTType(filenameExtension: "cube") ?? .data
    }

    var body: some View {
        NavigationStack {
            List {
                Section("启用") {
                    Toggle("N-Log LUT 预览", isOn: Binding(
                        get: { session.state.lut.isEnabled },
                        set: { session.setLUTEnabled($0) }
                    ))

                    VStack(alignment: .leading) {
                        Text("强度 \(Int(session.state.lut.intensity * 100))%")
                        Slider(
                            value: Binding(
                                get: { session.state.lut.intensity },
                                set: { session.setLUTIntensity($0) }
                            ),
                            in: 0...1,
                            step: 0.01
                        )
                    }
                }

                lutSection("内置 LUT", descriptors: session.state.lut.builtInLUTs)
                lutSection("导入 LUT", descriptors: session.state.lut.importedLUTs)

                if let error = session.state.lut.lastImportError {
                    Section("导入错误") {
                        Text(error.localizedDescription)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("LUT")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("导入 .cube") {
                        isImporterPresented = true
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .fileImporter(isPresented: $isImporterPresented, allowedContentTypes: [cubeType]) { result in
                guard case .success(let url) = result else { return }
                Task {
                    await session.importLUT(from: url)
                }
            }
        }
    }

    private func lutSection(_ title: String, descriptors: [LUTDescriptor]) -> some View {
        Section(title) {
            if descriptors.isEmpty {
                Text("暂无")
                    .foregroundStyle(.secondary)
            }

            ForEach(descriptors) { descriptor in
                Button {
                    session.selectLUT(descriptor)
                    session.setLUTEnabled(true)
                } label: {
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(descriptor.tintColor)
                            .frame(width: 26, height: 26)

                        VStack(alignment: .leading) {
                            Text(descriptor.title)
                            Text("\(descriptor.cubeSize)^3 · \(descriptor.source.rawValue)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if session.state.lut.selectedLUT?.id == descriptor.id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                .foregroundStyle(.primary)
            }
        }
    }
}
