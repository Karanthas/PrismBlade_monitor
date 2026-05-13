import SwiftUI

@main
@MainActor
struct PrismBladeApp: App {
    @StateObject private var session = AppEnvironment.makeMonitorSession()

    var body: some Scene {
        WindowGroup {
            MonitorScreen(session: session)
                .task {
                    // App 启动后立即进入监看状态，符合“第一屏就是画面”的原型要求。
                    session.startMonitoring()
                }
        }
    }
}
