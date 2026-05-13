import Foundation

enum AppEnvironment {
    @MainActor
    static func makeMonitorSession() -> MonitorSession {
        let frameSource = SimulatedFrameSource()
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
}
