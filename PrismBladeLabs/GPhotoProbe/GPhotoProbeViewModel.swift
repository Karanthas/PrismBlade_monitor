import Foundation

@MainActor
final class GPhotoProbeViewModel: ObservableObject {
    @Published private(set) var results: [ProbeResult] = []
    @Published private(set) var isRunning = false
    @Published private(set) var jsonlPreview = ""

    private let logStore = ProbeLogStore()
    private let suite = ReadOnlyProbeSuite()

    var allowedCommands: [ProbeCommand] {
        ReadOnlyProbeSuite.orderedCommands
    }

    func runReadOnlySuite() async {
        isRunning = true
        defer { isRunning = false }
        results = await suite.runReadOnlySuite(logStore: logStore)
        jsonlPreview = (try? logStore.jsonl()) ?? ""
    }

    func clearLogs() {
        logStore.clear()
        results = []
        jsonlPreview = ""
    }
}
