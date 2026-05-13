import Foundation

protocol CameraTransport {
    // Transport 只表达“相机命令边界”，不暴露 USB/PTP/libgphoto2 类型，方便后续替换实现。
    func connect() async throws
    func disconnect() async
    func currentState() async throws -> CameraState
    func setValue(_ value: String, for parameter: CameraParameter) async throws -> CameraState
    func trigger(_ action: CameraAction) async throws -> CameraState
}

final class CameraCommandService {
    private let transport: CameraTransport

    init(transport: CameraTransport) {
        self.transport = transport
    }

    func connect() async throws -> CameraState {
        // 连接成功后立即读取状态，确保 UI 不需要猜测 Mock 或真实相机的初始参数。
        try await transport.connect()
        return try await transport.currentState()
    }

    func disconnect() async {
        await transport.disconnect()
    }

    func setValue(_ value: String, for parameter: CameraParameter) async throws -> CameraState {
        // 先读取最新状态再判断曝光模式，避免 UI 缓存状态和 transport 实际状态不一致。
        let state = try await transport.currentState()
        let mode = ExposureMode(rawValue: state.exposureMode.current) ?? .manual
        let availability = CameraExposureRules.availability(for: parameter, in: mode)
        guard availability.isEnabled else {
            throw CameraTransportError.parameterLockedByExposureMode(parameter: parameter, mode: mode)
        }

        // Command service 是 UI 之外的第一道业务边界，防止禁用参数绕过按钮状态直接提交。
        return try await transport.setValue(value, for: parameter)
    }

    func trigger(_ action: CameraAction) async throws -> CameraState {
        try await transport.trigger(action)
    }
}

actor MockCameraTransport: CameraTransport {
    // actor 隔离 Mock 状态，模拟未来真实相机 transport 的异步串行访问。
    private var isConnected = false
    private var state = CameraState.mockInitial

    func connect() async throws {
        // 人为延迟让 UI 能验证 connecting/loading 状态，而不是瞬间跳到 connected。
        try await Task.sleep(nanoseconds: 350_000_000)
        isConnected = true
    }

    func disconnect() async {
        isConnected = false
    }

    func currentState() async throws -> CameraState {
        guard isConnected else { throw CameraTransportError.notConnected }
        return state
    }

    func setValue(_ value: String, for parameter: CameraParameter) async throws -> CameraState {
        guard isConnected else { throw CameraTransportError.notConnected }
        // 参数写入延迟用于模拟 USB/PTP 往返耗时，也让提交中状态可被看到。
        try await Task.sleep(nanoseconds: 220_000_000)
        let mode = ExposureMode(rawValue: state.exposureMode.current) ?? .manual
        let availability = CameraExposureRules.availability(for: parameter, in: mode)
        guard availability.isEnabled else {
            // Mock transport 是最后防线，即使 UI 或 service 漏判也不能写入被曝光模式锁定的参数。
            throw CameraTransportError.parameterLockedByExposureMode(parameter: parameter, mode: mode)
        }

        // Mock 层也校验能力表，确保 UI 不会绕过 command service 写入非法值。
        switch parameter {
        case .exposureMode:
            // 曝光模式本身也走能力表校验，保证只能切到 M/A/S/P/Auto 这些已声明档位。
            try update(&state.exposureMode, value: value, parameter: parameter)
        case .iso:
            try update(&state.iso, value: value, parameter: parameter)
        case .shutter:
            try update(&state.shutter, value: value, parameter: parameter)
        case .aperture:
            try update(&state.aperture, value: value, parameter: parameter)
        case .whiteBalance:
            try update(&state.whiteBalance, value: value, parameter: parameter)
        case .focusMode:
            try update(&state.focusMode, value: value, parameter: parameter)
        }

        return state
    }

    func trigger(_ action: CameraAction) async throws -> CameraState {
        guard isConnected else { throw CameraTransportError.notConnected }
        // 动作类命令也保留短延迟，用于模拟拍照/对焦/录制控制的反馈时间。
        try await Task.sleep(nanoseconds: 180_000_000)

        switch action {
        case .toggleRecord:
            state.isRecording.toggle()
            state.lastActionStatus = state.isRecording ? "REC" : "REC 停止"
        case .capture:
            state.lastActionStatus = "拍照完成"
        case .halfPress:
            state.lastActionStatus = "半按测光"
        case .focus:
            state.lastActionStatus = "对焦成功"
        }

        return state
    }

    private func update(_ cameraValue: inout CameraValue, value: String, parameter: CameraParameter) throws {
        guard cameraValue.options.contains(value) else {
            // 所有参数写入都必须命中 options；这让底部离散滑块和 transport 能力表保持一致。
            throw CameraTransportError.unsupportedValue(parameter: parameter, value: value)
        }

        cameraValue.current = value
        cameraValue.isSubmitting = false
    }
}
