import Foundation
import SwiftUI

enum MonitorCameraMode: Equatable {
    case mock
    case realCamera

    var diagnosticName: String {
        switch self {
        case .mock:
            return "mock"
        case .realCamera:
            return "realCamera"
        }
    }
}

@MainActor
final class MonitorSession: ObservableObject {
    // MonitorSession 是主 UI 状态容器；所有 @Published 更新固定在 MainActor，避免 SwiftUI 跨线程刷新。
    @Published private(set) var state = MonitorSessionState()
    @Published private(set) var latestFrame = VideoFrame.placeholder
    @Published private(set) var scopeData: ScopeData?
    @Published private(set) var lastUserMessage: String?
    let lutStore: LUTStore

    private let frameSource: FrameSource
    private let cameraService: CameraCommandService
    private let lutRepository: LUTRepository
    private let cameraMode: MonitorCameraMode
    private let diagnosticsLog: AppDiagnosticsLog
    private let defaults = UserDefaults.standard

    private var frameTask: Task<Void, Never>?
    private var cameraEventTask: Task<Void, Never>?
    private var messageClearTask: Task<Void, Never>?
    private var reconnectAttemptCount = 0
    private let maximumReconnectAttempts = 2
    private var monitoringGeneration = 0

    init(
        frameSource: FrameSource,
        cameraService: CameraCommandService,
        lutRepository: LUTRepository,
        cameraMode: MonitorCameraMode = .mock,
        diagnosticsLog: AppDiagnosticsLog = AppDiagnosticsLog()
    ) {
        self.frameSource = frameSource
        self.cameraService = cameraService
        self.lutRepository = lutRepository
        self.cameraMode = cameraMode
        self.diagnosticsLog = diagnosticsLog
        lutStore = LUTStore(repository: lutRepository)
        restorePersistentState()
        diagnosticsLog.record("monitor.session.created", fields: [
            "cameraMode": cameraMode.diagnosticName
        ])
    }

    var isRealCameraMode: Bool {
        cameraMode == .realCamera
    }

    func diagnosticLogText() -> String {
        diagnosticsLog.exportText()
    }

    func clearDiagnosticLog() {
        diagnosticsLog.clear()
        showUserMessage("诊断日志已清空")
    }

    deinit {
        frameTask?.cancel()
        cameraEventTask?.cancel()
        messageClearTask?.cancel()
    }

    func startMonitoring() {
        guard frameTask == nil, cameraEventTask == nil else { return }
        reconnectAttemptCount = 0
        monitoringGeneration += 1
        let generation = monitoringGeneration
        diagnosticsLog.record("monitor.start", fields: [
            "cameraMode": cameraMode.diagnosticName,
            "generation": "\(generation)"
        ])

        switch cameraMode {
        case .mock:
            startMockMonitoring(generation: generation)
        case .realCamera:
            cameraEventTask = Task { [weak self] in
                await self?.startRealCameraMonitoring(generation: generation)
            }
        }
    }

    func stopMonitoring() {
        frameTask?.cancel()
        frameTask = nil
        cameraEventTask?.cancel()
        cameraEventTask = nil
        reconnectAttemptCount = 0
        monitoringGeneration += 1
        diagnosticsLog.record("monitor.stop", fields: [
            "generation": "\(monitoringGeneration)"
        ])

        Task {
            await frameSource.stop()
            await cameraService.disconnect()
        }
    }

    func toggleFalseColor() {
        state.monitor.falseColorEnabled.toggle()
    }

    func setFalseColorDefaultEnabled(_ isEnabled: Bool) {
        state.monitor.falseColorDefaultEnabled = isEnabled
        state.monitor.falseColorEnabled = isEnabled
        defaults.set(isEnabled, forKey: DefaultsKey.falseColorDefaultEnabled)
    }

    func toggleZebra() {
        state.monitor.zebraEnabled.toggle()
    }

    func setZebraDefaultEnabled(_ isEnabled: Bool) {
        state.monitor.zebraDefaultEnabled = isEnabled
        state.monitor.zebraEnabled = isEnabled
        defaults.set(isEnabled, forKey: DefaultsKey.zebraDefaultEnabled)
    }

    func setZebraMode(_ mode: ZebraMode) {
        state.monitor.zebraMode = mode
    }

    func setZebraThreshold(_ threshold: Double) {
        state.monitor.zebraThreshold = threshold
        // 阈值属于用户偏好，立即持久化，下一次启动保持相同监看习惯。
        defaults.set(threshold, forKey: DefaultsKey.zebraThreshold)
    }

    func setScopeMode(_ mode: ScopeMode) {
        state.monitor.scopeMode = mode
        if mode == .off {
            scopeData = nil
        }
        defaults.set(mode.rawValue, forKey: DefaultsKey.scopeMode)
    }

    func setScopeOpacity(_ opacity: Double) {
        state.monitor.scopeOpacity = opacity
        defaults.set(opacity, forKey: DefaultsKey.scopeOpacity)
    }

    func setScopeDockPosition(_ position: ScopeDockPosition) {
        state.monitor.scopeDockPosition = position
        defaults.set(position.rawValue, forKey: DefaultsKey.scopeDockPosition)
    }

    func setExposureAnalysisSource(_ source: ExposureAnalysisSource) {
        state.monitor.exposureAnalysisSource = source
        defaults.set(source.rawValue, forKey: DefaultsKey.exposureAnalysisSource)
    }

    func setZoomMode(_ mode: ZoomMode) {
        state.monitor.zoomMode = mode
    }

    func setPortraitMonitoringAllowed(_ isAllowed: Bool) {
        state.orientation.allowsPortraitMonitoring = isAllowed
        defaults.set(isAllowed, forKey: DefaultsKey.allowsPortraitMonitoring)
    }

    func setLUTEnabled(_ isEnabled: Bool) {
        state.lut.isEnabled = isEnabled
        defaults.set(isEnabled, forKey: DefaultsKey.lutEnabled)
    }

    func toggleLUTPreview() {
        setLUTEnabled(!state.lut.isEnabled)
    }

    func setLUTIntensity(_ intensity: Double) {
        state.lut.intensity = intensity
        defaults.set(intensity, forKey: DefaultsKey.lutIntensity)
    }

    func selectLUT(_ descriptor: LUTDescriptor?) {
        state.lut.selectedLUT = descriptor
        defaults.set(descriptor?.id.uuidString, forKey: DefaultsKey.selectedLUTID)
    }

    func cameraValue(for parameter: CameraParameter) -> CameraValue {
        // 统一参数读取入口，底部控制条无需知道 CameraState 的具体字段布局。
        switch parameter {
        case .exposureMode:
            return state.camera.exposureMode
        case .iso:
            return state.camera.iso
        case .shutter:
            return state.camera.shutter
        case .aperture:
            return state.camera.aperture
        case .whiteBalance:
            return state.camera.whiteBalance
        case .focusMode:
            return state.camera.focusMode
        }
    }

    func availability(for parameter: CameraParameter) -> CameraParameterAvailability {
        guard state.connection.isConnected else {
            // 未连接时所有参数禁用，但保留原因用于点击置灰项后的短提示。
            return CameraParameterAvailability(isEnabled: false, reason: "相机未连接")
        }

        let value = cameraValue(for: parameter)
        guard value.isWritable else {
            // 基础能力不可写优先级高于曝光模式规则；真实机身能力表会主要走这里。
            return CameraParameterAvailability(isEnabled: false, reason: "\(parameter.title) 当前不可写")
        }

        // 当前曝光模式是第二层限制，例如 A 档锁快门、S 档锁光圈。
        let exposureMode = ExposureMode(rawValue: state.camera.exposureMode.current) ?? .manual
        return CameraExposureRules.availability(for: parameter, in: exposureMode)
    }

    func availability(for action: CameraAction) -> CameraActionAvailability {
        guard state.connection.isConnected else {
            return CameraActionAvailability(isEnabled: false, reason: "相机未连接")
        }

        guard cameraMode == .mock else {
            switch action {
            case .toggleRecord, .capture:
                return CameraActionAvailability(isEnabled: false, reason: "真实相机模式暂不启用 REC/拍照")
            case .halfPress, .focus:
                return CameraActionAvailability(isEnabled: false, reason: "真实相机对焦动作等待验证")
            }
        }

        return .enabled
    }

    func showDisabledParameterReason(for parameter: CameraParameter) {
        // UI 点击禁用项时只展示提示，不提交命令，也不打开调整浮层。
        showUserMessage(availability(for: parameter).reason)
    }

    func showUserMessage(_ message: String?) {
        // 所有短提示都走同一个入口，方便统一做自动消失、后续分级和可访问性处理。
        messageClearTask?.cancel()

        guard let message, !message.isEmpty else {
            lastUserMessage = nil
            return
        }

        lastUserMessage = message
        diagnosticsLog.record("ui.message", fields: ["message": message])
        let messageSnapshot = message

        messageClearTask = Task { [weak self] in
            // 短提示给用户足够时间读完，但不长期占用监看画面。
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard self?.lastUserMessage == messageSnapshot else { return }
                self?.lastUserMessage = nil
            }
        }
    }

    func updateScopeData(_ data: ScopeData) {
        guard state.monitor.scopeMode != .off, data.isValid else { return }
        scopeData = data
    }

    func importLUT(from url: URL) async {
        do {
            // LUTRepository 负责文件读取、解析和保存；Session 只接收可展示的 descriptor。
            let descriptor = try await lutRepository.importLUT(from: url)
            state.lut.importedLUTs.append(descriptor)
            state.lut.selectedLUT = descriptor
            state.lut.isEnabled = true
            state.lut.lastImportError = nil
            persistSelectedLUT(descriptor)
        } catch let error as LUTImportError {
            state.lut.lastImportError = error
        } catch {
            state.lut.lastImportError = .unreadableFile(error.localizedDescription)
        }
    }

    func setCameraParameter(_ parameter: CameraParameter, to value: String) {
        let availability = availability(for: parameter)
        guard availability.isEnabled else {
            // UI 层提交前先拦一次，降低无效 async 命令和错误噪音。
            showUserMessage(availability.reason)
            diagnosticsLog.record("camera.parameter.blocked", fields: [
                "parameter": parameter.rawValue,
                "reason": availability.reason ?? ""
            ])
            return
        }

        markCameraParameter(parameter, isSubmitting: true)
        diagnosticsLog.record("camera.parameter.submit", fields: [
            "parameter": parameter.rawValue,
            "value": value
        ])

        Task {
            do {
                // 真正写入仍通过 CameraCommandService，确保 UI 不直接依赖 Mock transport。
                let updated = try await cameraService.setValue(value, for: parameter)
                state.camera = updated
                diagnosticsLog.record("camera.parameter.succeeded", fields: [
                    "parameter": parameter.rawValue,
                    "value": value
                ])
                if cameraMode == .mock, parameter == .exposureMode {
                    // 只持久化 Mock 模式，方便模拟器复现；真实相机接入时必须以相机读取值为准。
                    defaults.set(value, forKey: DefaultsKey.mockExposureMode)
                }
            } catch {
                showUserMessage("相机参数提交失败：\(error.localizedDescription)")
                diagnosticsLog.record("camera.parameter.failed", fields: [
                    "parameter": parameter.rawValue,
                    "value": value,
                    "errorType": String(describing: type(of: error)),
                    "error": error.localizedDescription
                ])
                markCameraParameter(parameter, isSubmitting: false)
            }
        }
    }

    func triggerCameraAction(_ action: CameraAction) {
        let availability = availability(for: action)
        guard availability.isEnabled else {
            showUserMessage(availability.reason)
            diagnosticsLog.record("camera.action.blocked", fields: [
                "action": action.diagnosticName,
                "reason": availability.reason ?? ""
            ])
            return
        }

        Task {
            do {
                // 录制、拍照、对焦统一走 action 通道，避免伪装成普通参数写入。
                let updated = try await cameraService.trigger(action)
                state.camera = updated
                showUserMessage(action.successMessage)
                diagnosticsLog.record("camera.action.succeeded", fields: [
                    "action": action.diagnosticName
                ])
            } catch {
                showUserMessage("相机动作失败：\(error.localizedDescription)")
                diagnosticsLog.record("camera.action.failed", fields: [
                    "action": action.diagnosticName,
                    "errorType": String(describing: type(of: error)),
                    "error": error.localizedDescription
                ])
            }
        }
    }

    func reconnectMockCamera() {
        reconnectCamera()
    }

    func reconnectCamera() {
        switch cameraMode {
        case .mock:
            let generation = monitoringGeneration
            Task { await connectCameraForCurrentMode(generation: generation) }
        case .realCamera:
            cameraEventTask?.cancel()
            cameraEventTask = nil
            reconnectAttemptCount = 0
            monitoringGeneration += 1
            let generation = monitoringGeneration
            diagnosticsLog.record("camera.reconnect.manual", fields: [
                "cameraMode": cameraMode.diagnosticName,
                "generation": "\(generation)"
            ])
            cameraEventTask = Task { [weak self] in
                guard let self else { return }
                await self.frameSource.stop()
                await self.cameraService.disconnect()
                await self.startRealCameraMonitoring(generation: generation)
            }
        }
    }

    func simulateMockDisconnect() {
        Task {
            await cameraService.disconnect()
            setConnection(.interrupted("Mock 断开"), reason: "simulateMockDisconnect")
        }
    }

    private func startMockMonitoring(generation: Int) {
        frameTask = Task { [weak self] in
            guard let self else { return }
            await self.startFrameSource(reconnectOnFailure: false, generation: generation)
        }

        cameraEventTask = Task { [weak self] in
            await self?.connectCameraForCurrentMode(generation: generation)
        }
    }

    private func startRealCameraMonitoring(generation: Int) async {
        diagnosticsLog.record("camera.real.start", fields: ["generation": "\(generation)"])
        await connectCameraForCurrentMode(generation: generation)
        guard isCurrentMonitoringGeneration(generation), state.connection.isConnected else { return }
        await startFrameSource(reconnectOnFailure: true, generation: generation)
    }

    private func startFrameSource(reconnectOnFailure: Bool, generation: Int) async {
        guard isCurrentMonitoringGeneration(generation) else { return }
        let stream = frameSource.frames()
        diagnosticsLog.record("frameSource.starting", fields: [
            "reconnectOnFailure": reconnectOnFailure ? "true" : "false",
            "generation": "\(generation)"
        ])
        do {
            try await frameSource.start()
            guard isCurrentMonitoringGeneration(generation) else {
                await frameSource.stop()
                return
            }
            diagnosticsLog.record("frameSource.started", fields: [
                "status": frameSource.status.diagnosticName,
                "generation": "\(generation)"
            ])

            for await frame in stream {
                guard isCurrentMonitoringGeneration(generation) else { break }
                // 每一帧只替换 latestFrame，图像处理状态仍由 MonitorState 独立控制。
                latestFrame = frame
            }

            guard isCurrentMonitoringGeneration(generation) else { return }
            if case .failed(let reason) = frameSource.status {
                if reconnectOnFailure, frameSourceFailureIsConnectionLoss() {
                    await handleRealCameraInterruption(reason: reason, generation: generation)
                } else {
                    showUserMessage("实时取景失败：\(reason)")
                    diagnosticsLog.record("frameSource.failed", fields: [
                        "reason": reason,
                        "connectionLoss": frameSourceFailureIsConnectionLoss() ? "true" : "false"
                    ])
                }
            }
        } catch {
            guard isCurrentMonitoringGeneration(generation) else { return }
            if reconnectOnFailure, isConnectionLoss(error) {
                await handleRealCameraInterruption(reason: error.localizedDescription, generation: generation)
            } else {
                showUserMessage("帧源启动失败：\(error.localizedDescription)")
                diagnosticsLog.record("frameSource.start.failed", fields: [
                    "errorType": String(describing: type(of: error)),
                    "error": error.localizedDescription
                ])
            }
        }
    }

    private func connectCameraForCurrentMode(generation: Int) async {
        guard isCurrentMonitoringGeneration(generation) else { return }
        setConnection(cameraMode == .realCamera ? .searching : .connecting, reason: "connect.start")
        diagnosticsLog.record("camera.connect.start", fields: [
            "cameraMode": cameraMode.diagnosticName,
            "generation": "\(generation)"
        ])

        do {
            var camera = try await cameraService.connect()
            guard isCurrentMonitoringGeneration(generation) else { return }
            if cameraMode == .mock,
               let mockExposureMode = defaults.string(forKey: DefaultsKey.mockExposureMode),
               camera.exposureMode.options.contains(mockExposureMode) {
                // Mock 持久化只用于模拟器体验；未来真实相机接入后应以相机实际读取值为准。
                // 这里仍走 command service 写入，避免绕过曝光模式能力表和 transport 校验。
                camera = try await cameraService.setValue(mockExposureMode, for: .exposureMode)
                guard isCurrentMonitoringGeneration(generation) else { return }
            }
            state.camera = camera
            setConnection(.connected, reason: "connect.succeeded")
            diagnosticsLog.record("camera.connect.succeeded", fields: [
                "cameraMode": cameraMode.diagnosticName,
                "exposureMode": camera.exposureMode.current
            ])
        } catch {
            guard isCurrentMonitoringGeneration(generation) else { return }
            let newState = connectionState(for: error)
            setConnection(newState, reason: "connect.failed")
            var fields = [
                "cameraMode": cameraMode.diagnosticName,
                "connectionState": newState.diagnosticName,
                "errorType": String(describing: type(of: error)),
                "error": error.localizedDescription
            ]
            if let discoveryError = error as? NikonCameraDiscoveryError {
                fields["errorCase"] = discoveryError.diagnosticName
            }
            diagnosticsLog.record("camera.connect.failed", fields: fields)
        }
    }

    private func handleRealCameraInterruption(reason: String, generation: Int) async {
        guard cameraMode == .realCamera, isCurrentMonitoringGeneration(generation) else { return }
        setConnection(.interrupted(reason), reason: "realCamera.interrupted")
        diagnosticsLog.record("camera.real.interrupted", fields: [
            "reason": reason,
            "generation": "\(generation)"
        ])
        await frameSource.stop()
        await cameraService.disconnect()

        reconnectAttemptCount = 0
        while reconnectAttemptCount < maximumReconnectAttempts {
            reconnectAttemptCount += 1
            setConnection(.reconnecting(attempt: reconnectAttemptCount), reason: "realCamera.reconnect")
            do {
                try await Task.sleep(nanoseconds: UInt64(reconnectAttemptCount) * 700_000_000)
            } catch {
                return
            }
            guard isCurrentMonitoringGeneration(generation) else { return }

            await connectCameraForCurrentMode(generation: generation)
            guard isCurrentMonitoringGeneration(generation) else { return }
            guard state.connection.isConnected else { continue }

            reconnectAttemptCount = 0
            await startFrameSource(reconnectOnFailure: true, generation: generation)
            return
        }
    }

    private func setConnection(_ connection: ConnectionState, reason: String) {
        let previous = state.connection
        state.connection = connection
        diagnosticsLog.record("camera.connection.changed", fields: [
            "from": previous.diagnosticName,
            "to": connection.diagnosticName,
            "reason": reason
        ])
    }

    private func isCurrentMonitoringGeneration(_ generation: Int) -> Bool {
        generation == monitoringGeneration && !Task.isCancelled
    }

    private func frameSourceFailureIsConnectionLoss() -> Bool {
        (frameSource as? FrameSourceConnectionLossReporting)?.didFailFromConnectionLoss ?? false
    }

    private func isConnectionLoss(_ error: Error) -> Bool {
        if let discoveryError = error as? NikonCameraDiscoveryError {
            switch discoveryError {
            case .noCamera, .missingPTPCapability:
                return true
            case .authorizationDenied, .unsupportedCamera:
                return false
            }
        }

        if let runtimeError = error as? NikonCameraRuntimeError {
            if case .notConnected = runtimeError {
                return true
            }
        }

        if let clientError = error as? PTPClientError {
            switch clientError {
            case .missingPTPCapability, .timeout, .timedOutOperationStillInFlight, .transactionMismatch:
                return true
            case .responseError:
                return false
            }
        }

        return false
    }

    private func connectionState(for error: Error) -> ConnectionState {
        guard cameraMode == .realCamera else {
            return .failed(error.localizedDescription)
        }

        if let discoveryError = error as? NikonCameraDiscoveryError {
            switch discoveryError {
            case .noCamera:
                return .noCamera
            case .authorizationDenied:
                return .permissionDenied(realCameraMessage(for: discoveryError))
            case .unsupportedCamera, .missingPTPCapability:
                return .unsupported(realCameraMessage(for: discoveryError))
            }
        }

        return .failed(error.localizedDescription)
    }

    private func realCameraMessage(for error: NikonCameraDiscoveryError) -> String {
        switch error {
        case .noCamera:
            return "未发现可连接的 Nikon Z6III。请连接相机后重试。"
        case .unsupportedCamera(let model):
            return "已发现 \(model)，当前真实相机模式只支持 Nikon Z6III。"
        case .authorizationDenied:
            return "iOS 未授权相机控制。请在系统权限弹窗或设置中允许访问后重试。"
        case .missingPTPCapability(let model):
            return "\(model) 已被发现，但 iOS 未报告 PTP 命令能力。请确认相机 USB 模式和数据线连接；需要定位时先运行 GPhotoProbe 导出诊断。"
        }
    }

    private func restorePersistentState() {
        // restore 只恢复本地 UI 偏好；真正相机参数会在 connectMockCamera 后再次从 transport 对齐。
        state.lut.builtInLUTs = lutStore.loadBuiltInDescriptors()
        state.lut.importedLUTs = lutRepository.loadImportedDescriptors()
        state.orientation.allowsPortraitMonitoring = defaults.bool(forKey: DefaultsKey.allowsPortraitMonitoring)

        if let threshold = defaults.object(forKey: DefaultsKey.zebraThreshold) as? Double {
            state.monitor.zebraThreshold = threshold
        }

        if defaults.object(forKey: DefaultsKey.falseColorDefaultEnabled) != nil {
            let defaultEnabled = defaults.bool(forKey: DefaultsKey.falseColorDefaultEnabled)
            state.monitor.falseColorDefaultEnabled = defaultEnabled
            state.monitor.falseColorEnabled = defaultEnabled
        }

        if defaults.object(forKey: DefaultsKey.zebraDefaultEnabled) != nil {
            let defaultEnabled = defaults.bool(forKey: DefaultsKey.zebraDefaultEnabled)
            state.monitor.zebraDefaultEnabled = defaultEnabled
            state.monitor.zebraEnabled = defaultEnabled
        }

        if let rawScope = defaults.string(forKey: DefaultsKey.scopeMode),
           let scopeMode = ScopeMode(rawValue: rawScope) {
            state.monitor.scopeMode = scopeMode
        }

        if let opacity = defaults.object(forKey: DefaultsKey.scopeOpacity) as? Double {
            state.monitor.scopeOpacity = opacity
        }

        if let rawScopeDockPosition = defaults.string(forKey: DefaultsKey.scopeDockPosition),
           let position = ScopeDockPosition(rawValue: rawScopeDockPosition) {
            state.monitor.scopeDockPosition = position
        }

        if let rawAnalysisSource = defaults.string(forKey: DefaultsKey.exposureAnalysisSource),
           let source = ExposureAnalysisSource(rawValue: rawAnalysisSource) {
            state.monitor.exposureAnalysisSource = source
        }

        if let intensity = defaults.object(forKey: DefaultsKey.lutIntensity) as? Double {
            state.lut.intensity = intensity
        }

        if defaults.object(forKey: DefaultsKey.lutEnabled) != nil {
            state.lut.isEnabled = defaults.bool(forKey: DefaultsKey.lutEnabled)
        }

        if let selectedID = defaults.string(forKey: DefaultsKey.selectedLUTID),
           let uuid = UUID(uuidString: selectedID) {
            let allLUTs = state.lut.builtInLUTs + state.lut.importedLUTs
            // 如果用户删除了导入文件或 index 损坏，找不到时保持 nil，不阻塞 App 启动。
            state.lut.selectedLUT = allLUTs.first { $0.id == uuid }
        }

        if cameraMode == .mock,
           let mockExposureMode = defaults.string(forKey: DefaultsKey.mockExposureMode),
           state.camera.exposureMode.options.contains(mockExposureMode) {
            state.camera.exposureMode.current = mockExposureMode
        }
    }

    private func persistSelectedLUT(_ descriptor: LUTDescriptor) {
        defaults.set(descriptor.id.uuidString, forKey: DefaultsKey.selectedLUTID)
    }

    private func markCameraParameter(_ parameter: CameraParameter, isSubmitting: Bool) {
        // 提交中状态只存在于 UI 模型，真实 transport 不需要知道按钮 loading 细节。
        switch parameter {
        case .exposureMode:
            state.camera.exposureMode.isSubmitting = isSubmitting
        case .iso:
            state.camera.iso.isSubmitting = isSubmitting
        case .shutter:
            state.camera.shutter.isSubmitting = isSubmitting
        case .aperture:
            state.camera.aperture.isSubmitting = isSubmitting
        case .whiteBalance:
            state.camera.whiteBalance.isSubmitting = isSubmitting
        case .focusMode:
            state.camera.focusMode.isSubmitting = isSubmitting
        }
    }
}

private enum DefaultsKey {
    static let allowsPortraitMonitoring = "PrismBlade.allowsPortraitMonitoring"
    static let falseColorDefaultEnabled = "PrismBlade.falseColorDefaultEnabled"
    static let zebraDefaultEnabled = "PrismBlade.zebraDefaultEnabled"
    static let zebraThreshold = "PrismBlade.zebraThreshold"
    static let scopeMode = "PrismBlade.scopeMode"
    static let scopeOpacity = "PrismBlade.scopeOpacity"
    static let scopeDockPosition = "PrismBlade.scopeDockPosition"
    static let exposureAnalysisSource = "PrismBlade.exposureAnalysisSource"
    static let selectedLUTID = "PrismBlade.selectedLUTID"
    static let lutIntensity = "PrismBlade.lutIntensity"
    static let lutEnabled = "PrismBlade.lutEnabled"
    static let mockExposureMode = "PrismBlade.mockExposureMode"
}
