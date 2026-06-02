import SwiftUI

@MainActor
final class AppSessionStore: ObservableObject {
    @Published private(set) var session: MonitorSession

    init() {
        session = AppEnvironment.makeMonitorSession()
    }

    func startMonitoring() {
        session.startMonitoring()
    }

    func setRealCameraModeEnabled(_ isEnabled: Bool) {
        guard AppEnvironment.isRealCameraPreferenceEnabled() != isEnabled ||
              session.isRealCameraMode != isEnabled else { return }

        AppEnvironment.setRealCameraPreferenceEnabled(isEnabled)
        session.stopMonitoring()
        session = AppEnvironment.makeMonitorSession()
        session.startMonitoring()
    }
}

@main
@MainActor
struct PrismBladeApp: App {
    @StateObject private var sessionStore = AppSessionStore()

    var body: some Scene {
        WindowGroup {
            MonitorScreen(
                session: sessionStore.session,
                onRealCameraModeChange: { isEnabled in
                    sessionStore.setRealCameraModeEnabled(isEnabled)
                }
            )
                .task {
                    // App 启动后立即进入监看状态，符合“第一屏就是画面”的原型要求。
                    sessionStore.startMonitoring()
                }
        }
    }
}
