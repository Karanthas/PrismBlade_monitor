import Foundation

struct ProbeLogEvent: Codable, Equatable, Identifiable {
    var id: UUID
    var timestamp: Date
    var runID: UUID
    var probeID: String
    var phase: String
    var route: ProbeAPIroute
    var requestSummary: String
    var responseSummary: String?
    var durationMilliseconds: Int?
    var status: ProbeStatus
    var failureLayer: ProbeFailureLayer?
    var correlationID: String
    var redactionStatus: String
    var evidence: [String: String]

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        runID: UUID,
        probeID: String,
        phase: String,
        route: ProbeAPIroute,
        requestSummary: String,
        responseSummary: String? = nil,
        durationMilliseconds: Int? = nil,
        status: ProbeStatus,
        failureLayer: ProbeFailureLayer? = nil,
        correlationID: String = UUID().uuidString,
        redactionStatus: String = "not_needed",
        evidence: [String: String] = [:]
    ) {
        self.id = id
        self.timestamp = timestamp
        self.runID = runID
        self.probeID = probeID
        self.phase = phase
        self.route = route
        self.requestSummary = requestSummary
        self.responseSummary = responseSummary
        self.durationMilliseconds = durationMilliseconds
        self.status = status
        self.failureLayer = failureLayer
        self.correlationID = correlationID
        self.redactionStatus = redactionStatus
        self.evidence = evidence
    }
}

final class ProbeLogStore {
    private(set) var events: [ProbeLogEvent] = []
    private let encoder: JSONEncoder

    init() {
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
    }

    func append(_ event: ProbeLogEvent) {
        events.append(redacted(event))
    }

    func clear() {
        events.removeAll()
    }

    func jsonl() throws -> String {
        try events
            .map { event in
                let data = try encoder.encode(event)
                return String(decoding: data, as: UTF8.self)
            }
            .joined(separator: "\n")
    }

    private func redacted(_ event: ProbeLogEvent) -> ProbeLogEvent {
        var copy = event
        copy.evidence = event.evidence.reduce(into: [:]) { result, pair in
            if pair.key.localizedCaseInsensitiveContains("serial") {
                result[pair.key] = "REDACTED"
            } else {
                result[pair.key] = pair.value
            }
        }
        if copy.evidence != event.evidence {
            copy.redactionStatus = "redacted"
        }
        return copy
    }
}

enum ProbeLogExporter {
    static func makeBundle(
        runID: UUID,
        appBuild: String,
        iOSVersion: String,
        deviceModel: String,
        targetCamera: CameraDeviceProbeDescriptor?,
        setupNotes: [String],
        store: ProbeLogStore
    ) throws -> ProbeExportBundle {
        var redactedCamera: CameraDeviceProbeDescriptor?
        if var camera = targetCamera {
            if camera.serialNumber != nil {
                camera.serialNumber = "REDACTED"
            }
            redactedCamera = camera
        }

        return ProbeExportBundle(
            runID: runID,
            createdAt: Date(),
            appBuild: appBuild,
            iOSVersion: iOSVersion,
            deviceModel: deviceModel,
            targetCamera: redactedCamera,
            setupNotes: setupNotes,
            jsonl: try store.jsonl()
        )
    }
}
