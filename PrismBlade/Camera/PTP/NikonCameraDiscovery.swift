import Foundation

enum CameraAuthorizationState: Equatable {
    case notDetermined
    case authorized
    case denied
    case restricted

    var diagnosticName: String {
        switch self {
        case .notDetermined:
            return "notDetermined"
        case .authorized:
            return "authorized"
        case .denied:
            return "denied"
        case .restricted:
            return "restricted"
        }
    }
}

enum CameraDeviceCapability: String, Equatable {
    case canAcceptPTPCommands
}

struct NikonCameraDescriptor: Equatable {
    var name: String
    var manufacturer: String
    var model: String
    var serialNumber: String?
    var authorization: CameraAuthorizationState
    var capabilities: Set<CameraDeviceCapability>

    private var normalizedIdentity: String {
        "\(manufacturer) \(model) \(name)"
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
    }

    var isNikonCamera: Bool {
        normalizedIdentity.contains("nikon")
    }

    var isNikonZ6III: Bool {
        let normalized = normalizedIdentity
        return isNikonCamera &&
            (normalized.contains("z6iii") || normalized.contains("z63"))
    }

    var canAcceptPTPCommands: Bool {
        capabilities.contains(.canAcceptPTPCommands)
    }

    var hasUsableAuthorization: Bool {
        authorization == .authorized || authorization == .notDetermined
    }

    var isSupportedPTPCamera: Bool {
        hasUsableAuthorization && canAcceptPTPCommands
    }
}

enum NikonCameraDiscoveryError: Error, Equatable, LocalizedError {
    case noCamera
    case unsupportedCamera(model: String)
    case authorizationDenied(CameraAuthorizationState)
    case missingPTPCapability(model: String)

    var diagnosticName: String {
        switch self {
        case .noCamera:
            return "noCamera"
        case .unsupportedCamera:
            return "unsupportedCamera"
        case .authorizationDenied:
            return "authorizationDenied"
        case .missingPTPCapability:
            return "missingPTPCapability"
        }
    }

    var errorDescription: String? {
        switch self {
        case .noCamera:
            return "No camera was discovered."
        case .unsupportedCamera(let model):
            return "\(model) is not a supported PTP camera."
        case .authorizationDenied(let state):
            return "Camera authorization gate failed with state \(state)."
        case .missingPTPCapability(let model):
            return "\(model) cannot accept PTP commands."
        }
    }
}

protocol NikonCameraDiscoveryBridge {
    func discoverCameras() async -> [NikonCameraDescriptor]
    func authorizationState() async -> CameraAuthorizationState?
}

extension NikonCameraDiscoveryBridge {
    func authorizationState() async -> CameraAuthorizationState? {
        nil
    }
}

struct NikonCameraSelector {
    func selectSupportedCamera(from descriptors: [NikonCameraDescriptor]) throws -> NikonCameraDescriptor {
        guard !descriptors.isEmpty else {
            throw NikonCameraDiscoveryError.noCamera
        }

        let authorizedDescriptors = descriptors.filter(\.hasUsableAuthorization)

        guard !authorizedDescriptors.isEmpty else {
            throw NikonCameraDiscoveryError.authorizationDenied(descriptors[0].authorization)
        }

        let ptpDescriptors = authorizedDescriptors.filter(\.canAcceptPTPCommands)
        guard !ptpDescriptors.isEmpty else {
            let model = authorizedDescriptors.first?.model ?? "unknown camera"
            throw NikonCameraDiscoveryError.missingPTPCapability(model: model)
        }

        return ptpDescriptors.first(where: \.isNikonCamera) ?? ptpDescriptors[0]
    }
}

actor NikonCameraDiscoveryService {
    private let bridge: NikonCameraDiscoveryBridge
    private let selector: NikonCameraSelector
    private let diagnostics: PTPDiagnosticsRecorder?

    init(
        bridge: NikonCameraDiscoveryBridge,
        selector: NikonCameraSelector = NikonCameraSelector(),
        diagnostics: PTPDiagnosticsRecorder? = nil
    ) {
        self.bridge = bridge
        self.selector = selector
        self.diagnostics = diagnostics
    }

    func discoverSupportedCamera() async throws -> NikonCameraDescriptor {
        await diagnostics?.record(.discoveryStarted)
        let descriptors = await bridge.discoverCameras()
        await diagnostics?.record(.discoveryFinished(cameraCount: descriptors.count))

        do {
            if descriptors.isEmpty,
               let authorization = await bridge.authorizationState(),
               authorization == .denied || authorization == .restricted {
                throw NikonCameraDiscoveryError.authorizationDenied(authorization)
            }

            let selected = try selector.selectSupportedCamera(from: descriptors)
            await diagnostics?.record(.selectedCamera(
                name: selected.name,
                manufacturer: selected.manufacturer,
                model: selected.model,
                serialNumber: selected.serialNumber
            ))
            return selected
        } catch {
            await diagnostics?.record(.gateFailed(reason: error.localizedDescription))
            throw error
        }
    }
}

struct StaticNikonCameraDiscoveryBridge: NikonCameraDiscoveryBridge {
    var descriptors: [NikonCameraDescriptor]

    func discoverCameras() async -> [NikonCameraDescriptor] {
        descriptors
    }
}

#if canImport(ImageCaptureCore)
@preconcurrency import ImageCaptureCore

final class ImageCaptureCoreDiscoveryBridge: NSObject, NikonCameraDiscoveryBridge, ICDeviceBrowserDelegate {
    private let timeoutNanoseconds: UInt64
    private let diagnostics: PTPDiagnosticsRecorder?
    private var browser: ICDeviceBrowser?
    private var continuation: CheckedContinuation<[NikonCameraDescriptor], Never>?
    private var discoveredCameras: [ICCameraDevice] = []
    private var selectedCamera: ICCameraDevice?
    private var contentsAuthorization: CameraAuthorizationState = .notDetermined
    private var controlAuthorization: CameraAuthorizationState = .notDetermined
    private var discoveryWasCancelled = false
    private var discoveryGeneration = 0
    private var timeoutTask: Task<Void, Never>?

    init(timeoutNanoseconds: UInt64 = 10_000_000_000, diagnostics: PTPDiagnosticsRecorder? = nil) {
        self.timeoutNanoseconds = timeoutNanoseconds
        self.diagnostics = diagnostics
    }

    func discoverCameras() async -> [NikonCameraDescriptor] {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async {
                    guard !self.discoveryWasCancelled else {
                        self.discoveryWasCancelled = false
                        continuation.resume(returning: [])
                        return
                    }

                    self.continuation = continuation
                    self.discoveredCameras = []
                    self.selectedCamera = nil
                    self.contentsAuthorization = .notDetermined
                    self.controlAuthorization = .notDetermined
                    self.timeoutTask?.cancel()
                    self.timeoutTask = nil
                    self.discoveryGeneration += 1

                    let browser = ICDeviceBrowser()
                    browser.delegate = self
                    browser.browsedDeviceTypeMask = ICDeviceTypeMask(
                        rawValue: ICDeviceTypeMask.camera.rawValue | ICDeviceLocationTypeMask.local.rawValue
                    ) ?? .camera
                    self.browser = browser
                    self.recordAuthorizationSnapshot(browser: browser)
                    self.requestAuthorizationAndStart(browser, generation: self.discoveryGeneration)
                }
            }
        } onCancel: {
            DispatchQueue.main.async {
                self.discoveryWasCancelled = true
                self.cancelDiscovery()
            }
        }
    }

    func authorizationState() async -> CameraAuthorizationState? {
        await MainActor.run {
            combinedAuthorizationState()
        }
    }

    func deviceBrowser(_ browser: ICDeviceBrowser, didAdd device: ICDevice, moreComing: Bool) {
        guard self.browser === browser else { return }
        guard let camera = device as? ICCameraDevice else { return }
        discoveredCameras.append(camera)
        if !moreComing {
            finishDiscovery()
        }
    }

    func deviceBrowser(_ browser: ICDeviceBrowser, didRemove device: ICDevice, moreGoing: Bool) {
        guard self.browser === browser else { return }
        discoveredCameras.removeAll { $0 === device }
    }

    private func requestAuthorizationAndStart(_ browser: ICDeviceBrowser, generation: Int) {
        browser.requestContentsAuthorization { [weak self, weak browser] contentsStatus in
            DispatchQueue.main.async {
                guard let self,
                      let browser,
                      self.browser === browser,
                      self.discoveryGeneration == generation else { return }
                self.contentsAuthorization = Self.authorizationState(from: contentsStatus)
                self.recordAuthorizationSnapshot(browser: browser)

                switch self.contentsAuthorization {
                case .denied, .restricted:
                    self.finishDiscovery()
                case .authorized, .notDetermined:
                    self.requestControlAuthorizationAndStart(browser, generation: generation)
                }
            }
        }
    }

    private func requestControlAuthorizationAndStart(_ browser: ICDeviceBrowser, generation: Int) {
        browser.requestControlAuthorization { [weak self, weak browser] controlStatus in
            DispatchQueue.main.async {
                guard let self,
                      let browser,
                      self.browser === browser,
                      self.discoveryGeneration == generation else { return }
                self.controlAuthorization = Self.authorizationState(from: controlStatus)
                self.recordAuthorizationSnapshot(browser: browser)

                switch self.controlAuthorization {
                case .denied, .restricted:
                    self.finishDiscovery()
                case .authorized, .notDetermined:
                    self.startDiscovery(with: browser, generation: generation)
                }
            }
        }
    }

    private func startDiscovery(with browser: ICDeviceBrowser, generation: Int) {
        browser.start()
        let timeoutNanoseconds = timeoutNanoseconds
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self, weak browser] in
            try? await Task.sleep(nanoseconds: timeoutNanoseconds)
            DispatchQueue.main.async {
                guard let self,
                      let browser,
                      self.browser === browser,
                      self.discoveryGeneration == generation else { return }
                self.finishDiscovery()
            }
        }
    }

    private func finishDiscovery() {
        guard let continuation else { return }
        timeoutTask?.cancel()
        timeoutTask = nil
        if discoveredCameras.isEmpty {
            discoveredCameras = browser?.devices?.compactMap { $0 as? ICCameraDevice } ?? []
        }
        recordDiscoverySnapshot()

        let pairs = discoveredCameras.map { camera in
            (
                camera: camera,
                descriptor: ImageCaptureCoreDescriptorMapper.descriptor(for: camera, authorization: combinedAuthorizationState())
            )
        }
        let selectablePairs = pairs.filter { $0.descriptor.isSupportedPTPCamera }
        selectedCamera = selectablePairs.first { $0.descriptor.isNikonCamera }?.camera ?? selectablePairs.first?.camera
        let descriptors = pairs.map(\.descriptor)

        browser?.stop()
        browser = nil
        self.continuation = nil
        continuation.resume(returning: descriptors)
    }

    private func cancelDiscovery() {
        guard let continuation else { return }
        timeoutTask?.cancel()
        timeoutTask = nil
        browser?.stop()
        browser = nil
        self.continuation = nil
        discoveredCameras = []
        selectedCamera = nil
        discoveryWasCancelled = false
        continuation.resume(returning: [])
    }

    @MainActor
    func selectedPTPCamera() -> ICCameraDevice? {
        selectedCamera
    }

    @MainActor
    func clearSelectedPTPCamera() {
        selectedCamera = nil
    }

    private static func authorizationState(from status: ICAuthorizationStatus) -> CameraAuthorizationState {
        let rawValue = status.rawValue.lowercased()
        if rawValue.contains("denied") { return .denied }
        if rawValue.contains("restricted") { return .restricted }
        if rawValue.contains("authorized") { return .authorized }
        return .notDetermined
    }

    private func combinedAuthorizationState() -> CameraAuthorizationState {
        if contentsAuthorization == .denied || controlAuthorization == .denied {
            return .denied
        }
        if contentsAuthorization == .restricted || controlAuthorization == .restricted {
            return .restricted
        }
        if contentsAuthorization == .authorized && controlAuthorization == .authorized {
            return .authorized
        }
        return .notDetermined
    }

    private func recordAuthorizationSnapshot(browser: ICDeviceBrowser) {
        let contents = contentsAuthorization.diagnosticName
        let control = controlAuthorization.diagnosticName
        Task { [diagnostics] in
            await diagnostics?.record(.discoveryAuthorization(contents: contents, control: control))
        }
    }

    private func recordDiscoverySnapshot() {
        let cameraCount = discoveredCameras.count
        let browserDeviceCount = browser?.devices?.count ?? 0
        let isBrowsing = browser?.isBrowsing == true
        let contents = contentsAuthorization.diagnosticName
        let control = controlAuthorization.diagnosticName
        Task { [diagnostics] in
            await diagnostics?.record(.discoveryBrowserSnapshot(
                cameraCount: cameraCount,
                browserDeviceCount: browserDeviceCount,
                isBrowsing: isBrowsing,
                contentsAuthorization: contents,
                controlAuthorization: control
            ))
        }
    }
}

extension ImageCaptureCoreDiscoveryBridge: @unchecked Sendable {}

final class ImageCaptureCoreSelectedCameraPTPTransport: PTPCommandTransport {
    private let discoveryBridge: ImageCaptureCoreDiscoveryBridge

    init(discoveryBridge: ImageCaptureCoreDiscoveryBridge) {
        self.discoveryBridge = discoveryBridge
    }

    func send(_ packet: PTPCommandPacket, outboundData: Data?) async throws -> PTPTransportResponse {
        guard let camera = await discoveryBridge.selectedPTPCamera() else {
            throw NikonCameraDiscoveryError.noCamera
        }

        return try await ImageCaptureCorePTPTransport(camera: camera).send(packet, outboundData: outboundData)
    }
}

extension ImageCaptureCoreSelectedCameraPTPTransport: PTPTransportSessionResetting {
    func resetSessionAfterDisconnect() async {
        await discoveryBridge.clearSelectedPTPCamera()
    }
}

final class ImageCaptureCorePTPTransport: PTPCommandTransport {
    private let camera: ICCameraDevice

    init(camera: ICCameraDevice) {
        self.camera = camera
    }

    func send(_ packet: PTPCommandPacket, outboundData: Data?) async throws -> PTPTransportResponse {
        guard camera.capabilities.contains(ICDeviceCapability.cameraDeviceCanAcceptPTPCommands.rawValue) else {
            throw PTPClientError.missingPTPCapability
        }

        let start = Date()
        return try await withCheckedThrowingContinuation { continuation in
            camera.requestSendPTPCommand(packet.encodedCommand, outData: outboundData) { payloadData, responseData, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                continuation.resume(returning: PTPTransportResponse(
                    responseContainer: responseData,
                    payloadData: payloadData,
                    durationMilliseconds: Int(Date().timeIntervalSince(start) * 1000)
                ))
            }
        }
    }
}

enum ImageCaptureCoreDescriptorMapper {
    static func descriptor(for camera: ICCameraDevice, authorization: CameraAuthorizationState = .notDetermined) -> NikonCameraDescriptor {
        let name = camera.name ?? "Unnamed camera"
        let model = camera.productKind ?? camera.name ?? "ImageCapture camera"
        let manufacturer = "\(name) \(model)".localizedCaseInsensitiveContains("nikon") ? "Nikon" : "ImageCapture"
        let capabilities = Set(camera.capabilities.compactMap { rawCapability -> CameraDeviceCapability? in
            rawCapability == ICDeviceCapability.cameraDeviceCanAcceptPTPCommands.rawValue ? .canAcceptPTPCommands : nil
        })

        return NikonCameraDescriptor(
            name: name,
            manufacturer: manufacturer,
            model: model,
            serialNumber: nil,
            authorization: authorization,
            capabilities: capabilities
        )
    }
}
#endif
