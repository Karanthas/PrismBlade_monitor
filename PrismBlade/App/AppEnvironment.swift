import Foundation

enum AppEnvironment {
    @MainActor
    static func makeMonitorSession() -> MonitorSession {
        let frameSource = makeFrameSource()
        let transport = MockCameraTransport()
        let commandService = CameraCommandService(transport: transport)
        let lutRepository = LUTRepository()

        // 所有依赖从这里注入，后续接入真实相机或视频文件时只替换对应实现。
        return MonitorSession(
            frameSource: frameSource,
            cameraService: commandService,
            lutRepository: lutRepository
        )
    }

    private static func makeFrameSource() -> FrameSource {
        if let localVideoPath = launchArgumentValue(for: "-PBLocalVideoPath") {
            return VideoFileFrameSource(url: URL(fileURLWithPath: localVideoPath))
        }

        return SimulatedFrameSource()
    }

    private static func launchArgumentValue(for name: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments

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
