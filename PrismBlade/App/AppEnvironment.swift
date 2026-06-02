import Foundation

final class AppDiagnosticsLog: @unchecked Sendable {
    private let lock = NSLock()
    private let maximumEntryCount: Int
    private var entries: [[String: String]] = []

    init(maximumEntryCount: Int = 500) {
        self.maximumEntryCount = maximumEntryCount
    }

    func record(_ event: String, fields: [String: String] = [:]) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        var entry = fields
        entry["event"] = event
        entry["timestamp"] = timestamp

        lock.lock()
        entries.append(entry)
        if entries.count > maximumEntryCount {
            entries.removeFirst(entries.count - maximumEntryCount)
        }
        lock.unlock()
    }

    func exportText() -> String {
        lock.lock()
        let snapshot = entries
        lock.unlock()

        guard !snapshot.isEmpty else {
            return #"{"event":"diagnostics.empty"}"#
        }

        return snapshot
            .map { entry in
                guard let data = try? JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys]),
                      let line = String(data: data, encoding: .utf8) else {
                    return "\(entry)"
                }
                return line
            }
            .joined(separator: "\n")
    }

    func clear() {
        lock.lock()
        entries.removeAll()
        lock.unlock()
        record("diagnostics.cleared")
    }
}

enum AppEnvironment {
    static let realCameraPreferenceKey = "PrismBlade.useRealCameraMode"

    static func isRealCameraPreferenceEnabled() -> Bool {
        UserDefaults.standard.bool(forKey: realCameraPreferenceKey)
    }

    static func setRealCameraPreferenceEnabled(_ isEnabled: Bool) {
        UserDefaults.standard.set(isEnabled, forKey: realCameraPreferenceKey)
    }

    @MainActor
    static func makeMonitorSession() -> MonitorSession {
        makeMonitorSession(arguments: ProcessInfo.processInfo.arguments)
    }

    @MainActor
    static func makeMonitorSession(arguments: [String]) -> MonitorSession {
        let lutRepository = LUTRepository()
        let diagnosticsLog = AppDiagnosticsLog()
        let preferenceUsesRealCamera = isRealCameraPreferenceEnabled()
        let launchArgumentUsesRealCamera = arguments.contains("-PBUseRealCamera")
        let launchArgumentUsesMockCamera = arguments.contains("-PBUseMockCamera")
        let usesRealCamera = launchArgumentUsesRealCamera || (!launchArgumentUsesMockCamera && preferenceUsesRealCamera)
        diagnosticsLog.record("app.environment.start", fields: [
            "hasLocalVideoPath": launchArgumentValue(for: "-PBLocalVideoPath", in: arguments) == nil ? "false" : "true",
            "usesMockCameraArgument": launchArgumentUsesMockCamera ? "true" : "false",
            "usesRealCamera": usesRealCamera ? "true" : "false",
            "usesRealCameraArgument": launchArgumentUsesRealCamera ? "true" : "false",
            "usesRealCameraPreference": preferenceUsesRealCamera ? "true" : "false"
        ])

        if let localVideoPath = launchArgumentValue(for: "-PBLocalVideoPath", in: arguments) {
            diagnosticsLog.record("app.environment.mode", fields: ["mode": "localVideo"])
            return MonitorSession(
                frameSource: VideoFileFrameSource(url: URL(fileURLWithPath: localVideoPath)),
                cameraService: CameraCommandService(transport: MockCameraTransport()),
                lutRepository: lutRepository,
                cameraMode: .mock,
                diagnosticsLog: diagnosticsLog
            )
        }

        if usesRealCamera {
        #if canImport(ImageCaptureCore)
            diagnosticsLog.record("app.environment.mode", fields: ["mode": "realCamera"])
            let diagnostics = PTPDiagnosticsRecorder(appLog: diagnosticsLog)
            let bridge = ImageCaptureCoreDiscoveryBridge(diagnostics: diagnostics)
            let discovery = NikonCameraDiscoveryService(bridge: bridge, diagnostics: diagnostics)
            let ptpTransport = ImageCaptureCoreSelectedCameraPTPTransport(discoveryBridge: bridge)
            let ptpClient = PTPClient(transport: ptpTransport, diagnostics: diagnostics)
            let runtime = NikonCameraRuntime(discovery: discovery, ptp: ptpClient)

            // Real-camera mode is explicit while the iOS USB/PTP path is still hardware-validated.
            return MonitorSession(
                frameSource: NikonLiveViewFrameSource(runtime: runtime),
                cameraService: CameraCommandService(transport: NikonPTPCameraTransport(runtime: runtime)),
                lutRepository: lutRepository,
                cameraMode: .realCamera,
                diagnosticsLog: diagnosticsLog
            )
        #endif
        }

        diagnosticsLog.record("app.environment.mode", fields: ["mode": "mock"])
        return MonitorSession(
            frameSource: SimulatedFrameSource(),
            cameraService: CameraCommandService(transport: MockCameraTransport()),
            lutRepository: lutRepository,
            cameraMode: .mock,
            diagnosticsLog: diagnosticsLog
        )
    }

    private static func launchArgumentValue(for name: String, in arguments: [String]) -> String? {
        for index in arguments.indices {
            let argument = arguments[index]

            if argument == name, arguments.indices.contains(index + 1) {
                return arguments[index + 1]
            }

            let prefix = "\(name) "
            if argument.hasPrefix(prefix) {
                return String(argument.dropFirst(prefix.count))
            }
        }

        return nil
    }
}
