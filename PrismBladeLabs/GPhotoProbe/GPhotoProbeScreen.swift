import SwiftUI

struct GPhotoProbeScreen: View {
    @StateObject private var viewModel = GPhotoProbeViewModel()

    var body: some View {
        NavigationStack {
            List {
                Section("Setup") {
                    LabeledContent("Target", value: "iPhone 12 Pro + Nikon Z6III")
                    LabeledContent("Connection", value: "USB to Lightning")
                    LabeledContent("Mode", value: "Strict read-only")
                }

                Section("Read-only Suite") {
                    Button {
                        Task { await viewModel.runReadOnlySuite() }
                    } label: {
                        Label(viewModel.isRunning ? "Running" : "Run suite", systemImage: "play.circle")
                    }
                    .disabled(viewModel.isRunning)

                    ForEach(viewModel.allowedCommands) { command in
                        Label(command.rawValue, systemImage: command.isFirstPassAllowed ? "checkmark.shield" : "xmark.octagon")
                    }
                }

                Section("Results") {
                    if viewModel.results.isEmpty {
                        Text("No probe run yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(viewModel.results) { result in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(result.command.rawValue)
                                        .font(.headline)
                                    Spacer()
                                    Text(result.status.rawValue)
                                        .font(.caption)
                                        .foregroundStyle(color(for: result.status))
                                }
                                Text(result.message)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("Diagnostics") {
                    Button {
                        viewModel.clearLogs()
                    } label: {
                        Label("Clear", systemImage: "trash")
                    }
                    .disabled(viewModel.isRunning)

                    if !viewModel.jsonlPreview.isEmpty {
                        Text(viewModel.jsonlPreview)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            }
            .navigationTitle("GPhotoProbe")
        }
    }

    private func color(for status: ProbeStatus) -> Color {
        switch status {
        case .idle:
            return .secondary
        case .running:
            return .blue
        case .passed:
            return .green
        case .failed:
            return .red
        case .inconclusive:
            return .orange
        }
    }
}

