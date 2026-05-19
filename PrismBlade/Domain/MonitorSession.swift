import Foundation
import SwiftUI

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
    private let defaults = UserDefaults.standard

    private var frameTask: Task<Void, Never>?
    private var cameraEventTask: Task<Void, Never>?
    private var messageClearTask: Task<Void, Never>?

    init(
        frameSource: FrameSource,
        cameraService: CameraCommandService,
        lutRepository: LUTRepository
    ) {
        self.frameSource = frameSource
        self.cameraService = cameraService
        self.lutRepository = lutRepository
        lutStore = LUTStore(repository: lutRepository)
        restorePersistentState()
    }

    deinit {
        frameTask?.cancel()
        cameraEventTask?.cancel()
        messageClearTask?.cancel()
    }

    func startMonitoring() {
        guard frameTask == nil else { return }

        // 帧源与相机 Mock 分开启动：以后真实 live view 失败时，UI 仍可显示错误状态。
        frameTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await frameSource.start()
                for await frame in frameSource.frames() {
                    await MainActor.run {
                        // 每一帧只替换 latestFrame，图像处理状态仍由 MonitorState 独立控制。
                        self.latestFrame = frame
                    }
                }
            } catch {
                await MainActor.run {
                    self.showUserMessage("帧源启动失败：\(error.localizedDescription)")
                }
            }
        }

        cameraEventTask = Task { [weak self] in
            guard let self else { return }
            // Mock 相机连接不阻塞帧源启动，避免连接失败时监看画面也无法显示。
            await self.connectMockCamera()
        }
    }

    func stopMonitoring() {
        frameTask?.cancel()
        frameTask = nil
        cameraEventTask?.cancel()
        cameraEventTask = nil

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
            return CameraParameterAvailability(isEnabled: false, reason: "Mock 相机未连接")
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
            return
        }

        markCameraParameter(parameter, isSubmitting: true)

        Task {
            do {
                // 真正写入仍通过 CameraCommandService，确保 UI 不直接依赖 Mock transport。
                let updated = try await cameraService.setValue(value, for: parameter)
                state.camera = updated
                if parameter == .exposureMode {
                    // 只持久化 Mock 模式，方便模拟器复现；真实相机接入时必须以相机读取值为准。
                    defaults.set(value, forKey: DefaultsKey.mockExposureMode)
                }
            } catch {
                showUserMessage("相机参数提交失败：\(error.localizedDescription)")
                markCameraParameter(parameter, isSubmitting: false)
            }
        }
    }

    func triggerCameraAction(_ action: CameraAction) {
        Task {
            do {
                // 录制、拍照、对焦统一走 action 通道，避免伪装成普通参数写入。
                let updated = try await cameraService.trigger(action)
                state.camera = updated
                showUserMessage(action.successMessage)
            } catch {
                showUserMessage("相机动作失败：\(error.localizedDescription)")
            }
        }
    }

    func reconnectMockCamera() {
        Task { await connectMockCamera() }
    }

    func simulateMockDisconnect() {
        Task {
            await cameraService.disconnect()
            state.connection = .interrupted("Mock 断开")
        }
    }

    private func connectMockCamera() async {
        state.connection = .connecting

        do {
            var camera = try await cameraService.connect()
            if let mockExposureMode = defaults.string(forKey: DefaultsKey.mockExposureMode),
               camera.exposureMode.options.contains(mockExposureMode) {
                // Mock 持久化只用于模拟器体验；未来真实相机接入后应以相机实际读取值为准。
                // 这里仍走 command service 写入，避免绕过曝光模式能力表和 transport 校验。
                camera = try await cameraService.setValue(mockExposureMode, for: .exposureMode)
            }
            state.camera = camera
            state.connection = .connected
        } catch {
            state.connection = .failed(error.localizedDescription)
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

        if let mockExposureMode = defaults.string(forKey: DefaultsKey.mockExposureMode),
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
