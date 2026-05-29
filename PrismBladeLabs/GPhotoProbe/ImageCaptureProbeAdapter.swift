import Foundation

#if canImport(ImageCaptureCore)
import ImageCaptureCore

final class ImageCaptureDiscoveryProbe: NSObject, CameraDiscoveryProbe, ICDeviceBrowserDelegate {
    private let timeoutNanoseconds: UInt64
    private var browser: ICDeviceBrowser?
    private var continuation: CheckedContinuation<CameraDiscoveryOutcome, Never>?
    private var discoveredCameras: [ICCameraDevice] = []

    init(timeoutNanoseconds: UInt64 = 1_500_000_000) {
        self.timeoutNanoseconds = timeoutNanoseconds
    }

    func discover() async -> CameraDiscoveryOutcome {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                self.continuation = continuation
                self.discoveredCameras = []

                let browser = ICDeviceBrowser()
                browser.delegate = self
                browser.browsedDeviceTypeMask = ICDeviceTypeMask(
                    rawValue: ICDeviceTypeMask.camera.rawValue | ICDeviceLocationTypeMask.local.rawValue
                ) ?? .camera
                self.browser = browser
                browser.start()

                Task { [weak self] in
                    try? await Task.sleep(nanoseconds: self?.timeoutNanoseconds ?? 0)
                    await MainActor.run {
                        self?.finishDiscovery()
                    }
                }
            }
        }
    }

    func deviceBrowser(_ browser: ICDeviceBrowser, didAdd device: ICDevice, moreComing: Bool) {
        guard let camera = device as? ICCameraDevice else { return }
        discoveredCameras.append(camera)
        if !moreComing {
            finishDiscovery()
        }
    }

    func deviceBrowser(_ browser: ICDeviceBrowser, didRemove device: ICDevice, moreGoing: Bool) {
        discoveredCameras.removeAll { $0 === device }
    }

    private func finishDiscovery() {
        guard let continuation else { return }
        if discoveredCameras.isEmpty {
            discoveredCameras = browser?.devices?.compactMap { $0 as? ICCameraDevice } ?? []
        }
        browser?.stop()
        browser = nil
        self.continuation = nil

        if discoveredCameras.isEmpty {
            continuation.resume(
                returning: CameraDiscoveryOutcome(
                    result: ProbeResult(
                        command: .discovery,
                        status: .inconclusive,
                        message: "ImageCaptureCore discovery completed without a camera device.",
                        failureLayer: .physical,
                        evidence: ["cameraCount": "0"]
                    ),
                    targetCamera: nil,
                    ptpTransport: nil
                )
            )
            return
        }

        if discoveredCameras.count > 1 {
            continuation.resume(
                returning: CameraDiscoveryOutcome(
                    result: ProbeResult(
                        command: .discovery,
                        status: .inconclusive,
                        message: "Discovered multiple ImageCaptureCore cameras; select one before read-only PTP probing.",
                        requiresUserDecision: true,
                        evidence: ["cameraCount": "\(discoveredCameras.count)"]
                    ),
                    targetCamera: nil,
                    ptpTransport: nil
                )
            )
            return
        }

        let camera = discoveredCameras[0]
        let descriptor = descriptor(for: camera)
        let result = ProbeResult(
            command: .discovery,
            status: .passed,
            message: "Discovered one ImageCaptureCore camera.",
            evidence: [
                "cameraCount": "1",
                "selectedCameraName": descriptor.name,
                "hasPTPCapability": descriptor.capabilities.contains(.canAcceptPTPCommands) ? "true" : "false"
            ]
        )
        continuation.resume(
            returning: CameraDiscoveryOutcome(
                result: result,
                targetCamera: descriptor,
                ptpTransport: ImageCapturePTPTransport(camera: camera)
            )
        )
    }

    private func descriptor(for camera: ICCameraDevice) -> CameraDeviceProbeDescriptor {
        let capabilities = Set(camera.capabilities.compactMap(Self.capability(from:)))
        return CameraDeviceProbeDescriptor(
            id: camera.uuidString ?? camera.name ?? "imagecapture-camera",
            name: camera.name ?? "Unnamed ImageCapture camera",
            manufacturer: nil,
            model: camera.productKind,
            serialNumber: nil,
            connectionRoute: .imageCaptureCore,
            capabilities: capabilities.isEmpty ? [.unknown] : capabilities
        )
    }

    private static func capability(from rawCapability: String) -> CameraProbeCapability? {
        switch rawCapability {
        case ICDeviceCapability.cameraDeviceCanAcceptPTPCommands.rawValue:
            return .canAcceptPTPCommands
        default:
            return nil
        }
    }
}

extension ImageCaptureDiscoveryProbe: @unchecked Sendable {}

final class ImageCapturePTPTransport: PTPHardwareTransport {
    private let camera: ICCameraDevice

    init(camera: ICCameraDevice) {
        self.camera = camera
    }

    var canAcceptPTPCommands: Bool {
        camera.capabilities.contains(ICDeviceCapability.cameraDeviceCanAcceptPTPCommands.rawValue)
    }

    func sendAllowlistedPTPCommand(_ packet: PTPCommandPacket) async throws -> PTPTransportResponse {
        guard canAcceptPTPCommands else {
            throw ProbeSafetyError.missingPTPCapability
        }

        let start = Date()
        return try await withCheckedThrowingContinuation { continuation in
            camera.requestSendPTPCommand(packet.encodedCommand, outData: nil) { payloadData, ptpResponseData, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let duration = Int(Date().timeIntervalSince(start) * 1000)
                continuation.resume(
                    returning: PTPTransportResponse(
                        responseContainer: ptpResponseData,
                        payloadData: payloadData,
                        durationMilliseconds: duration
                    )
                )
            }
        }
    }
}

#else

struct ImageCaptureDiscoveryProbe: CameraDiscoveryProbe {
    func discover() async -> CameraDiscoveryOutcome {
        CameraDiscoveryOutcome(
            result: ProbeResult(
                command: .discovery,
                status: .inconclusive,
                message: "ImageCaptureCore is unavailable in this build.",
                failureLayer: .iOSAPI,
                evidence: ["imageCaptureCoreAvailable": "false"]
            ),
            targetCamera: nil,
            ptpTransport: nil
        )
    }
}

#endif
