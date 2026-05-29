import Foundation

enum ProbeStatus: String, Codable, CaseIterable, Equatable, Identifiable {
    case idle
    case running
    case passed
    case failed
    case inconclusive

    var id: String { rawValue }
}

enum ProbeFailureLayer: String, Codable, CaseIterable, Equatable {
    case physical
    case permission
    case iOSAPI
    case cameraMode
    case ptpTransport
    case ptpResponse
    case configMapping
    case videoPath
    case safetyGate
    case unknown
}

enum ProbeAPIroute: String, Codable, CaseIterable, Equatable {
    case internalFake
    case imageCaptureCore
    case ptp
    case avFoundation
}

enum ProbeCommand: String, Codable, CaseIterable, Equatable, Identifiable {
    case discovery
    case summary
    case abilities
    case listConfig
    case getConfig
    case statusObservation
    case eventObservation
    case videoPathExistence
    case exportDiagnostics

    case setConfig
    case capture
    case focus
    case halfPress
    case record
    case deleteFile
    case formatStorage
    case fileDownload
    case upload
    case syncClock
    case metadataWrite

    var id: String { rawValue }

    var isFirstPassAllowed: Bool {
        switch self {
        case .discovery, .summary, .abilities, .listConfig, .getConfig,
             .statusObservation, .eventObservation, .videoPathExistence, .exportDiagnostics:
            return true
        case .setConfig, .capture, .focus, .halfPress, .record, .deleteFile,
             .formatStorage, .fileDownload, .upload, .syncClock, .metadataWrite:
            return false
        }
    }
}

enum ProbeCommandMatrix {
    static let firstPassAllowed = Set(ProbeCommand.allCases.filter(\.isFirstPassAllowed))

    static func validateFirstPass(_ command: ProbeCommand) throws {
        guard command.isFirstPassAllowed else {
            throw ProbeSafetyError.forbiddenCommand(command)
        }
    }
}

enum ProbeSafetyError: Error, Equatable, LocalizedError {
    case forbiddenCommand(ProbeCommand)
    case unallowlistedPTPOperation(UInt16)
    case missingPTPCapability
    case rawPTPBypassUnavailable
    case outboundPTPDataForbidden(ReadOnlyPTPCommand)

    var errorDescription: String? {
        switch self {
        case .forbiddenCommand(let command):
            return "Forbidden first-pass command: \(command.rawValue)"
        case .unallowlistedPTPOperation(let opcode):
            return "PTP operation 0x\(String(opcode, radix: 16, uppercase: true)) is not in the read-only allowlist"
        case .missingPTPCapability:
            return "The selected device does not report PTP command capability"
        case .rawPTPBypassUnavailable:
            return "Raw PTP Data send is unavailable; use typed read-only commands"
        case .outboundPTPDataForbidden(let command):
            return "Outbound PTP data is forbidden for first-pass command: \(command.rawValue)"
        }
    }
}

struct ProbeRunState: Codable, Equatable, Identifiable {
    var id: UUID
    var command: ProbeCommand
    var status: ProbeStatus
    var startedAt: Date?
    var finishedAt: Date?
    var latestResult: ProbeResult?

    init(
        id: UUID = UUID(),
        command: ProbeCommand,
        status: ProbeStatus = .idle,
        startedAt: Date? = nil,
        finishedAt: Date? = nil,
        latestResult: ProbeResult? = nil
    ) {
        self.id = id
        self.command = command
        self.status = status
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.latestResult = latestResult
    }
}

struct ProbeResult: Codable, Equatable, Identifiable {
    var id: UUID
    var command: ProbeCommand
    var status: ProbeStatus
    var message: String
    var failureLayer: ProbeFailureLayer?
    var requiresUserDecision: Bool
    var evidence: [String: String]

    init(
        id: UUID = UUID(),
        command: ProbeCommand,
        status: ProbeStatus,
        message: String,
        failureLayer: ProbeFailureLayer? = nil,
        requiresUserDecision: Bool = false,
        evidence: [String: String] = [:]
    ) {
        self.id = id
        self.command = command
        self.status = status
        self.message = message
        self.failureLayer = failureLayer
        self.requiresUserDecision = requiresUserDecision
        self.evidence = evidence
    }
}

struct CameraDeviceProbeDescriptor: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var manufacturer: String?
    var model: String?
    var serialNumber: String?
    var connectionRoute: ProbeAPIroute
    var capabilities: Set<CameraProbeCapability>
}

enum CameraProbeCapability: String, Codable, CaseIterable, Equatable {
    case canAcceptPTPCommands
    case canReportBattery
    case canReportStorage
    case canEmitPTPEvents
    case canExposeExternalVideoDevice
    case unknown
}

struct ProbeExportBundle: Codable, Equatable {
    var runID: UUID
    var createdAt: Date
    var appBuild: String
    var iOSVersion: String
    var deviceModel: String
    var targetCamera: CameraDeviceProbeDescriptor?
    var setupNotes: [String]
    var jsonl: String
}
