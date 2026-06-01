import Foundation

#if canImport(AVFoundation)
import AVFoundation
#endif

protocol CameraDiscoveryProbe {
    func discover() async -> CameraDiscoveryOutcome
}

protocol EventStatusProbe {
    func observeStatus() async -> ProbeResult
}

protocol VideoPathProbe {
    func checkPathExistence() async -> ProbeResult
}

struct CameraDiscoveryOutcome {
    var result: ProbeResult
    var targetCamera: CameraDeviceProbeDescriptor?
    var ptpTransport: (any PTPHardwareTransport)?
}

struct BoundedEventStatusProbe: EventStatusProbe {
    func observeStatus() async -> ProbeResult {
        ProbeResult(
            command: .statusObservation,
            status: .inconclusive,
            message: "No non-mutating event/status signal was observed during the bounded check.",
            failureLayer: .iOSAPI
        )
    }
}

struct AVFoundationVideoPathProbe: VideoPathProbe {
    func checkPathExistence() async -> ProbeResult {
        #if canImport(AVFoundation)
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external],
            mediaType: .video,
            position: .unspecified
        )
        let count = session.devices.count
        return ProbeResult(
            command: .videoPathExistence,
            status: count > 0 ? .passed : .inconclusive,
            message: count > 0 ? "AVFoundation external video device path is present." : "No AVFoundation external video device path is present.",
            failureLayer: count > 0 ? nil : .videoPath,
            evidence: ["externalVideoDeviceCount": "\(count)"]
        )
        #else
        ProbeResult(
            command: .videoPathExistence,
            status: .inconclusive,
            message: "AVFoundation is unavailable in this build.",
            failureLayer: .videoPath,
            evidence: ["avFoundationAvailable": "false"]
        )
        #endif
    }
}

struct ReadOnlyProbeSuite {
    var discovery: CameraDiscoveryProbe
    var eventStatus: EventStatusProbe
    var videoPath: VideoPathProbe

    init(
        discovery: CameraDiscoveryProbe = ImageCaptureDiscoveryProbe(),
        eventStatus: EventStatusProbe = BoundedEventStatusProbe(),
        videoPath: VideoPathProbe = AVFoundationVideoPathProbe()
    ) {
        self.discovery = discovery
        self.eventStatus = eventStatus
        self.videoPath = videoPath
    }

    static let orderedCommands: [ProbeCommand] = [
        .discovery,
        .abilities,
        .summary,
        .listConfig,
        .getConfig,
        .statusObservation,
        .eventObservation,
        .videoPathExistence,
        .exportDiagnostics
    ]

    func validateSuite() throws {
        try Self.orderedCommands.forEach(ProbeCommandMatrix.validateFirstPass)
    }

    func runReadOnlySuite(logStore: ProbeLogStore) async -> [ProbeResult] {
        let runID = UUID()
        do {
            try validateSuite()
        } catch {
            let result = ProbeResult(
                command: .discovery,
                status: .failed,
                message: error.localizedDescription,
                failureLayer: .safetyGate
            )
            appendLog(for: result, runID: runID, logStore: logStore)
            return [result]
        }

        var results: [ProbeResult] = []
        func record(_ result: ProbeResult) {
            results.append(result)
            appendLog(for: result, runID: runID, logStore: logStore)
        }

        let discoveryOutcome = await discovery.discover()
        record(discoveryOutcome.result)

        if discoveryOutcome.result.requiresUserDecision {
            record(exportResult(message: "Diagnostics are exportable after discovery requires user selection."))
            return results
        }

        guard discoveryOutcome.targetCamera != nil else {
            record(exportResult(message: "Diagnostics are exportable after discovery without a selected camera."))
            return results
        }

        guard let transport = discoveryOutcome.ptpTransport else {
            record(criticalPauseResult(message: "No PTP hardware transport is available for the selected camera."))
            record(exportResult(message: "Diagnostics are exportable after the PTP critical pause."))
            return results
        }

        var ptpClient = PTPProbeClient()
        let abilitiesOutcome = await ptpClient.sendDetailed(.getDeviceInfo, probeCommand: .abilities, transport: transport)
        var abilities = abilitiesOutcome.result
        let deviceInfo = parseDeviceInfo(from: abilitiesOutcome.response)
        if let deviceInfo {
            abilities.message = "PTP DeviceInfo parsed from read-only round-trip."
            abilities.evidence.merge(deviceInfo.evidence) { _, new in new }
            abilities.evidence["probedDeviceProperties"] = deviceInfo
                .probePropertyCodes()
                .map { "\(PTPDeviceInfoParser.hex($0)):\(PTPDevicePropertyCatalog.name(for: $0))" }
                .joined(separator: ",")
        } else if abilities.status == .passed {
            abilities.evidence["deviceInfoParse"] = "unavailable"
        }
        record(abilities)

        if abilities.requiresUserDecision {
            record(exportResult(message: "Diagnostics are exportable after the PTP critical pause."))
            return results
        }

        record(await ptpClient.send(.getDeviceInfo, probeCommand: .summary, transport: transport))
        let propertyCodes = deviceInfo?.probePropertyCodes() ?? [0x5001]
        for propertyCode in propertyCodes {
            let parameter = UInt32(propertyCode)
            let descOutcome = await ptpClient.sendDetailed(.getDevicePropDesc, probeCommand: .listConfig, parameters: [parameter], transport: transport)
            var descResult = descOutcome.result
            let propDesc = parseDevicePropDesc(from: descOutcome.response, propertyCode: propertyCode)
            if let propDesc {
                descResult.message = "PTP property descriptor parsed from read-only round-trip."
                descResult.evidence.merge(propDesc.evidence(propertyCode: propertyCode)) { _, new in new }
            } else if descResult.status == .passed {
                descResult.evidence["devicePropDescParse"] = "unavailable"
            }
            record(descResult)

            let valueOutcome = await ptpClient.sendDetailed(.getDevicePropValue, probeCommand: .getConfig, parameters: [parameter], transport: transport)
            var valueResult = valueOutcome.result
            if let propDesc, let value = parseDevicePropValue(from: valueOutcome.response, propDesc: propDesc) {
                valueResult.message = "PTP property value parsed from read-only round-trip."
                valueResult.evidence["propertyDataType"] = PTPDeviceInfoParser.hex(propDesc.dataType)
                valueResult.evidence["propertyDataTypeName"] = PTPDevicePropertyDataType.name(for: propDesc.dataType)
                valueResult.evidence["valueRaw"] = value.raw
                valueResult.evidence["valueDisplay"] = value.display
            } else if valueResult.status == .passed {
                valueResult.evidence["devicePropValueParse"] = "unavailable"
            }
            record(valueResult)
        }
        record(await eventStatus.observeStatus())
        record(ProbeResult(command: .eventObservation, status: .inconclusive, message: "PTP event observation is bounded and does not enable tethering.", failureLayer: .iOSAPI))
        record(await videoPath.checkPathExistence())
        record(exportResult(message: "Diagnostics are exportable as JSONL."))
        return results
    }

    private func appendLog(for result: ProbeResult, runID: UUID, logStore: ProbeLogStore) {
        logStore.append(
            ProbeLogEvent(
                runID: runID,
                probeID: result.command.rawValue,
                phase: "result",
                route: route(for: result.command),
                requestSummary: result.command.rawValue,
                responseSummary: result.message,
                status: result.status,
                failureLayer: result.failureLayer,
                evidence: result.evidence
            )
        )
    }

    private func route(for command: ProbeCommand) -> ProbeAPIroute {
        switch command {
        case .discovery:
            return .imageCaptureCore
        case .abilities, .summary, .listConfig, .getConfig, .eventObservation:
            return .ptp
        case .videoPathExistence:
            return .avFoundation
        case .statusObservation:
            return .imageCaptureCore
        case .exportDiagnostics:
            return .internalFake
        case .setConfig, .capture, .focus, .halfPress, .record, .deleteFile,
             .formatStorage, .fileDownload, .upload, .syncClock, .metadataWrite:
            return .internalFake
        }
    }

    private func criticalPauseResult(message: String) -> ProbeResult {
        ProbeResult(
            command: .abilities,
            status: .inconclusive,
            message: message,
            failureLayer: .iOSAPI,
            requiresUserDecision: true,
            evidence: ["criticalPause": "true"]
        )
    }

    private func exportResult(message: String) -> ProbeResult {
        ProbeResult(command: .exportDiagnostics, status: .passed, message: message)
    }

    private func parseDeviceInfo(from response: PTPTransportResponse?) -> PTPDeviceInfo? {
        guard let response, !response.payloadData.isEmpty else { return nil }
        return try? PTPDeviceInfoParser.parse(response.payloadData)
    }

    private func parseDevicePropDesc(from response: PTPTransportResponse?, propertyCode: UInt16) -> PTPDevicePropDesc? {
        guard let response, !response.payloadData.isEmpty else { return nil }
        return try? PTPDevicePropDescParser.parse(response.payloadData, expectedPropertyCode: propertyCode)
    }

    private func parseDevicePropValue(from response: PTPTransportResponse?, propDesc: PTPDevicePropDesc) -> PTPPropertyValue? {
        guard let response, !response.payloadData.isEmpty else { return nil }
        return try? PTPDevicePropValueParser.parse(
            response.payloadData,
            dataType: propDesc.dataType,
            propertyCode: propDesc.propertyCode
        )
    }
}
