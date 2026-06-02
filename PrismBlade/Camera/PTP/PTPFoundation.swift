import Foundation

enum PTPDataPhase: Equatable {
    case noData
    case inboundDataExpected
    case outboundDataRequired
}

enum NikonPTPOperation: UInt16, CaseIterable, Equatable {
    case getDeviceInfo = 0x1001
    case getDevicePropDesc = 0x1014
    case getDevicePropValue = 0x1015
    case setDevicePropValue = 0x1016
    case startLiveView = 0x9201
    case endLiveView = 0x9202
    case getLiveViewImage = 0x9203
}

enum PTPForbiddenOperation: String, Equatable {
    case recordToggle
    case capture
    case halfPress
    case fileDownload
    case fileListOrObjectTraversal
    case deleteObject
    case formatStorage
    case uploadObject
    case syncClock
    case metadataWrite
    case menuOrProfileWrite
    case unknownVendorOperation
    case nonZ6IIIGenericOperation
    case rawPTPBypass
}

enum PTPCommandIntent: Equatable {
    case liveViewStart
    case liveViewFrameFetch
    case liveViewEnd
    case readDeviceInfo
    case readPropertyDescription(UInt16)
    case readPropertyValue(UInt16)
    case writeImmediateControl(parameter: CameraParameter, propertyCode: UInt16, encodedValue: Data)
    case forbidden(PTPForbiddenOperation)
    case raw(operationCode: UInt16, parameters: [UInt32], outboundData: Data?)
}

struct PTPOperationRequest: Equatable {
    var operation: NikonPTPOperation
    var parameters: [UInt32]
    var dataPhase: PTPDataPhase
    var outboundData: Data?
    var diagnosticName: String
}

enum PTPOperationPolicyError: Error, Equatable, LocalizedError {
    case forbiddenOperation(PTPForbiddenOperation)
    case rawOperationBypass(UInt16)
    case unsupportedImmediateControl(CameraParameter)
    case mismatchedWriteProperty(parameter: CameraParameter, expected: UInt16, actual: UInt16)
    case emptyWritePayload(CameraParameter)

    var errorDescription: String? {
        switch self {
        case .forbiddenOperation(let operation):
            return "PTP operation is forbidden before packet construction: \(operation.rawValue)."
        case .rawOperationBypass(let code):
            return "Raw PTP operation \(PTPDiagnostics.hex(code)) is not allowed in production camera code."
        case .unsupportedImmediateControl(let parameter):
            return "\(parameter.title) is not approved for immediate PTP writes."
        case .mismatchedWriteProperty(let parameter, let expected, let actual):
            return "\(parameter.title) write targeted \(PTPDiagnostics.hex(actual)); expected \(PTPDiagnostics.hex(expected))."
        case .emptyWritePayload(let parameter):
            return "\(parameter.title) write has no encoded PTP payload."
        }
    }
}

struct PTPOperationPolicy {
    private let approvedWriteParameters: Set<CameraParameter>
    private let approvedWritePropertyCodes: [CameraParameter: UInt16]

    init(
        approvedWriteParameters: Set<CameraParameter> = Set(CameraParameter.allCases),
        approvedWritePropertyCodes: [CameraParameter: UInt16] = Self.nikonZ6IIIImmediateWritePropertyCodes
    ) {
        self.approvedWriteParameters = approvedWriteParameters
        self.approvedWritePropertyCodes = approvedWritePropertyCodes
    }

    static let nikonZ6IIIImmediateWritePropertyCodes: [CameraParameter: UInt16] = [
        .exposureMode: 0x500E,
        .iso: 0x500F,
        .shutter: 0x500D,
        .aperture: 0x5007,
        .whiteBalance: 0x5005,
        .focusMode: 0x500A
    ]

    static let nikonZ6IIIWriteApprovedParameters = Set(nikonZ6IIIImmediateWritePropertyCodes.keys)

    static func nikonZ6IIIImmediateControlPolicy() -> PTPOperationPolicy {
        PTPOperationPolicy(approvedWriteParameters: nikonZ6IIIWriteApprovedParameters)
    }

    func validate(_ intent: PTPCommandIntent) throws -> PTPOperationRequest {
        switch intent {
        case .liveViewStart:
            return PTPOperationRequest(
                operation: .startLiveView,
                parameters: [],
                dataPhase: .noData,
                outboundData: nil,
                diagnosticName: "nikon.startLiveView"
            )
        case .liveViewFrameFetch:
            return PTPOperationRequest(
                operation: .getLiveViewImage,
                parameters: [],
                dataPhase: .inboundDataExpected,
                outboundData: nil,
                diagnosticName: "nikon.getLiveViewImage"
            )
        case .liveViewEnd:
            return PTPOperationRequest(
                operation: .endLiveView,
                parameters: [],
                dataPhase: .noData,
                outboundData: nil,
                diagnosticName: "nikon.endLiveView"
            )
        case .readDeviceInfo:
            return PTPOperationRequest(
                operation: .getDeviceInfo,
                parameters: [],
                dataPhase: .inboundDataExpected,
                outboundData: nil,
                diagnosticName: "ptp.getDeviceInfo"
            )
        case .readPropertyDescription(let propertyCode):
            return PTPOperationRequest(
                operation: .getDevicePropDesc,
                parameters: [UInt32(propertyCode)],
                dataPhase: .inboundDataExpected,
                outboundData: nil,
                diagnosticName: "ptp.getDevicePropDesc"
            )
        case .readPropertyValue(let propertyCode):
            return PTPOperationRequest(
                operation: .getDevicePropValue,
                parameters: [UInt32(propertyCode)],
                dataPhase: .inboundDataExpected,
                outboundData: nil,
                diagnosticName: "ptp.getDevicePropValue"
            )
        case .writeImmediateControl(let parameter, let propertyCode, let encodedValue):
            guard approvedWriteParameters.contains(parameter),
                  let expectedPropertyCode = approvedWritePropertyCodes[parameter] else {
                throw PTPOperationPolicyError.unsupportedImmediateControl(parameter)
            }
            guard propertyCode == expectedPropertyCode else {
                throw PTPOperationPolicyError.mismatchedWriteProperty(
                    parameter: parameter,
                    expected: expectedPropertyCode,
                    actual: propertyCode
                )
            }
            guard !encodedValue.isEmpty else {
                throw PTPOperationPolicyError.emptyWritePayload(parameter)
            }
            return PTPOperationRequest(
                operation: .setDevicePropValue,
                parameters: [UInt32(propertyCode)],
                dataPhase: .outboundDataRequired,
                outboundData: encodedValue,
                diagnosticName: "ptp.setDevicePropValue.\(parameter.rawValue)"
            )
        case .forbidden(let operation):
            throw PTPOperationPolicyError.forbiddenOperation(operation)
        case .raw(let operationCode, _, _):
            throw PTPOperationPolicyError.rawOperationBypass(operationCode)
        }
    }
}

struct PTPCommandPacket: Equatable {
    static let commandContainerType: UInt16 = 1

    private(set) var operationCode: UInt16
    private(set) var transactionID: UInt32
    private(set) var parameters: [UInt32]

    fileprivate init(operationCode: UInt16, transactionID: UInt32, parameters: [UInt32]) {
        self.operationCode = operationCode
        self.transactionID = transactionID
        self.parameters = parameters
    }

    var encodedCommand: Data {
        var data = Data()
        data.appendLittleEndian(UInt32(0))
        data.appendLittleEndian(Self.commandContainerType)
        data.appendLittleEndian(operationCode)
        data.appendLittleEndian(transactionID)
        parameters.forEach { data.appendLittleEndian($0) }
        data.replaceSubrange(0..<4, with: UInt32(data.count).littleEndianData)
        return data
    }
}

struct PTPTransportResponse: Equatable {
    var responseContainer: Data
    var payloadData: Data
    var durationMilliseconds: Int
}

enum PTPResponseCode: UInt16, Equatable {
    case ok = 0x2001
    case generalError = 0x2002
    case operationNotSupported = 0x2005
    case parameterNotSupported = 0x2006
    case accessDenied = 0x200F
    case invalidDevicePropValue = 0x201C
    case deviceBusy = 0x2019
    case unknown = 0xFFFF

    init(rawResponseCode: UInt16) {
        self = PTPResponseCode(rawValue: rawResponseCode) ?? .unknown
    }
}

struct PTPParsedResponse: Equatable {
    var code: PTPResponseCode
    var rawCode: UInt16
    var transactionID: UInt32
    var parameters: [UInt32]
}

enum PTPResponseParseError: Error, Equatable, LocalizedError {
    case truncated(minimumBytes: Int, actualBytes: Int)
    case mismatchedContainerLength(declared: Int, actual: Int)
    case unalignedParameterBytes(Int)
    case unexpectedContainerType(UInt16)

    var errorDescription: String? {
        switch self {
        case .truncated(let minimumBytes, let actualBytes):
            return "PTP response had \(actualBytes) bytes; expected at least \(minimumBytes)."
        case .mismatchedContainerLength(let declared, let actual):
            return "PTP response declared \(declared) bytes but contained \(actual) bytes."
        case .unalignedParameterBytes(let byteCount):
            return "PTP response had \(byteCount) parameter bytes; expected a multiple of 4."
        case .unexpectedContainerType(let type):
            return "PTP response container type \(type) is not a response container."
        }
    }
}

enum PTPResponseParser {
    private static let responseContainerType: UInt16 = 3

    static func parse(_ data: Data) throws -> PTPParsedResponse {
        let minimumBytes = 12
        guard data.count >= minimumBytes else {
            throw PTPResponseParseError.truncated(minimumBytes: minimumBytes, actualBytes: data.count)
        }

        let declaredLength = Int(try data.readLittleEndianUInt32(at: 0))
        guard declaredLength == data.count else {
            throw PTPResponseParseError.mismatchedContainerLength(declared: declaredLength, actual: data.count)
        }

        let containerType = try data.readLittleEndianUInt16(at: 4)
        guard containerType == responseContainerType else {
            throw PTPResponseParseError.unexpectedContainerType(containerType)
        }

        let parameterByteCount = data.count - minimumBytes
        guard parameterByteCount.isMultiple(of: 4) else {
            throw PTPResponseParseError.unalignedParameterBytes(parameterByteCount)
        }

        var parameters: [UInt32] = []
        var offset = 12
        while offset + 4 <= data.count {
            parameters.append(try data.readLittleEndianUInt32(at: offset))
            offset += 4
        }

        let rawCode = try data.readLittleEndianUInt16(at: 6)
        return PTPParsedResponse(
            code: PTPResponseCode(rawResponseCode: rawCode),
            rawCode: rawCode,
            transactionID: try data.readLittleEndianUInt32(at: 8),
            parameters: parameters
        )
    }
}

protocol PTPCommandTransport {
    func send(_ packet: PTPCommandPacket, outboundData: Data?) async throws -> PTPTransportResponse
}

protocol PTPTransportSessionResetting {
    func resetSessionAfterDisconnect() async
}

enum PTPClientError: Error, Equatable, LocalizedError {
    case missingPTPCapability
    case responseError(code: PTPResponseCode, rawCode: UInt16)
    case timeout(operationCode: UInt16, transactionID: UInt32, durationMilliseconds: Int)
    case timedOutOperationStillInFlight(operationCode: UInt16, transactionID: UInt32)
    case transactionMismatch(expected: UInt32, actual: UInt32)

    var errorDescription: String? {
        switch self {
        case .missingPTPCapability:
            return "The selected camera cannot accept PTP commands."
        case .responseError(let code, let rawCode):
            return "PTP command failed with \(code) (\(PTPDiagnostics.hex(rawCode)))."
        case .timeout(let operationCode, let transactionID, let durationMilliseconds):
            return "PTP command \(PTPDiagnostics.hex(operationCode)) transaction \(transactionID) timed out after \(durationMilliseconds) ms."
        case .timedOutOperationStillInFlight(let operationCode, let transactionID):
            return "PTP command \(PTPDiagnostics.hex(operationCode)) transaction \(transactionID) is still resolving after a timeout or cancellation; reconnect before sending more commands."
        case .transactionMismatch(let expected, let actual):
            return "PTP response transaction \(actual) did not match request transaction \(expected)."
        }
    }
}

struct PTPClientResult: Equatable {
    var request: PTPOperationRequest
    var operationCode: UInt16
    var transactionID: UInt32
    var parameters: [UInt32]
    var response: PTPParsedResponse
    var payloadData: Data
}

actor PTPClient {
    private let policy: PTPOperationPolicy
    private let transport: PTPCommandTransport
    private let diagnostics: PTPDiagnosticsRecorder?
    private let sendTimeoutNanoseconds: UInt64
    private var nextTransactionID: UInt32
    private var transportSessionGeneration = 0
    private var timedOutOperationInFlight: (operationCode: UInt16, transactionID: UInt32, generation: Int)?
    private var isSendActive = false
    private var sendWaiters: [(id: UUID, continuation: CheckedContinuation<Void, Error>)] = []

    init(
        policy: PTPOperationPolicy = PTPOperationPolicy(),
        transport: PTPCommandTransport,
        diagnostics: PTPDiagnosticsRecorder? = nil,
        initialTransactionID: UInt32 = 1,
        sendTimeoutNanoseconds: UInt64 = 3_000_000_000
    ) {
        self.policy = policy
        self.transport = transport
        self.diagnostics = diagnostics
        self.sendTimeoutNanoseconds = sendTimeoutNanoseconds
        nextTransactionID = initialTransactionID
    }

    func send(_ intent: PTPCommandIntent) async throws -> PTPClientResult {
        try await acquireSendSlot()
        defer { releaseSendSlot() }
        try Task.checkCancellation()

        if let timedOutOperationInFlight {
            throw PTPClientError.timedOutOperationStillInFlight(
                operationCode: timedOutOperationInFlight.operationCode,
                transactionID: timedOutOperationInFlight.transactionID
            )
        }

        let request = try policy.validate(intent)
        let transactionID = nextTransactionID
        nextTransactionID += 1

        let packet = PTPCommandPacket(
            operationCode: request.operation.rawValue,
            transactionID: transactionID,
            parameters: request.parameters
        )

        await diagnostics?.record(.ptpSendStarted(
            operationCode: packet.operationCode,
            transactionID: packet.transactionID,
            parameters: packet.parameters,
            diagnosticName: request.diagnosticName,
            outboundByteCount: request.outboundData?.count ?? 0
        ))

        let transportResponse: PTPTransportResponse
        do {
            transportResponse = try await sendTransport(packet, outboundData: request.outboundData)
        } catch let error as PTPClientError {
            if case .timeout(let operationCode, let transactionID, let durationMilliseconds) = error {
                await diagnostics?.record(.ptpSendTimedOut(
                    operationCode: operationCode,
                    transactionID: transactionID,
                    durationMilliseconds: durationMilliseconds
                ))
            }
            throw error
        }

        let parsedResponse = try PTPResponseParser.parse(transportResponse.responseContainer)
        guard parsedResponse.transactionID == packet.transactionID else {
            throw PTPClientError.transactionMismatch(expected: packet.transactionID, actual: parsedResponse.transactionID)
        }

        await diagnostics?.record(.ptpSendFinished(
            operationCode: packet.operationCode,
            transactionID: packet.transactionID,
            responseCode: parsedResponse.rawCode,
            payloadByteCount: transportResponse.payloadData.count,
            durationMilliseconds: transportResponse.durationMilliseconds
        ))

        guard parsedResponse.code == .ok else {
            throw PTPClientError.responseError(code: parsedResponse.code, rawCode: parsedResponse.rawCode)
        }

        return PTPClientResult(
            request: request,
            operationCode: packet.operationCode,
            transactionID: packet.transactionID,
            parameters: packet.parameters,
            response: parsedResponse,
            payloadData: transportResponse.payloadData
        )
    }

    func resetSessionAfterDisconnect() async {
        if let resettableTransport = transport as? PTPTransportSessionResetting {
            await resettableTransport.resetSessionAfterDisconnect()
        }
        transportSessionGeneration += 1
        timedOutOperationInFlight = nil
    }

    private func sendTransport(_ packet: PTPCommandPacket, outboundData: Data?) async throws -> PTPTransportResponse {
        guard sendTimeoutNanoseconds > 0 else {
            return try await transport.send(packet, outboundData: outboundData)
        }

        let coordinator = PTPTransportTimeoutCoordinator()
        let transport = transport
        let sessionGeneration = transportSessionGeneration
        let timeoutMilliseconds = max(Int(sendTimeoutNanoseconds / 1_000_000), 1)
        let timeoutError = PTPClientError.timeout(
            operationCode: packet.operationCode,
            transactionID: packet.transactionID,
            durationMilliseconds: timeoutMilliseconds
        )

        let transportTask = Task { [weak self] in
            do {
                let response = try await transport.send(packet, outboundData: outboundData)
                coordinator.resolve(.success(response))
            } catch {
                coordinator.resolve(.failure(error))
            }
            await self?.markTimedOutTransportResolved(
                operationCode: packet.operationCode,
                transactionID: packet.transactionID,
                generation: sessionGeneration
            )
        }

        let timeoutTask = Task { [weak self, sendTimeoutNanoseconds] in
            try? await Task.sleep(nanoseconds: sendTimeoutNanoseconds)
            guard !Task.isCancelled else { return }
            await self?.markTimedOutTransportInFlight(
                operationCode: packet.operationCode,
                transactionID: packet.transactionID,
                generation: sessionGeneration
            )
            coordinator.resolve(.failure(timeoutError))
            transportTask.cancel()
        }

        do {
            let response = try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    coordinator.install(continuation)
                }
            } onCancel: {
                transportTask.cancel()
                timeoutTask.cancel()
                coordinator.resolve(.failure(CancellationError()))
            }
            timeoutTask.cancel()
            return response
        } catch {
            if error is CancellationError {
                markTimedOutTransportInFlight(
                    operationCode: packet.operationCode,
                    transactionID: packet.transactionID,
                    generation: sessionGeneration
                )
            }
            transportTask.cancel()
            timeoutTask.cancel()
            throw error
        }
    }

    private func markTimedOutTransportInFlight(operationCode: UInt16, transactionID: UInt32, generation: Int) {
        guard transportSessionGeneration == generation else { return }
        timedOutOperationInFlight = (operationCode: operationCode, transactionID: transactionID, generation: generation)
    }

    private func markTimedOutTransportResolved(operationCode: UInt16, transactionID: UInt32, generation: Int) {
        guard timedOutOperationInFlight?.operationCode == operationCode,
              timedOutOperationInFlight?.transactionID == transactionID,
              timedOutOperationInFlight?.generation == generation else { return }
        timedOutOperationInFlight = nil
    }

    private func acquireSendSlot() async throws {
        try Task.checkCancellation()
        guard isSendActive else {
            isSendActive = true
            return
        }

        let waiterID = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                sendWaiters.append((id: waiterID, continuation: continuation))
            }
        } onCancel: {
            Task { await self.cancelSendWaiter(id: waiterID) }
        }
    }

    private func releaseSendSlot() {
        guard !sendWaiters.isEmpty else {
            isSendActive = false
            return
        }

        let nextWaiter = sendWaiters.removeFirst()
        nextWaiter.continuation.resume(returning: ())
    }

    private func cancelSendWaiter(id: UUID) {
        guard let index = sendWaiters.firstIndex(where: { $0.id == id }) else { return }
        let waiter = sendWaiters.remove(at: index)
        waiter.continuation.resume(throwing: CancellationError())
    }
}

private final class PTPTransportTimeoutCoordinator: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<PTPTransportResponse, Error>?
    private var pendingResult: Result<PTPTransportResponse, Error>?
    private var isResolved = false

    func install(_ continuation: CheckedContinuation<PTPTransportResponse, Error>) {
        let pendingResult: Result<PTPTransportResponse, Error>?

        lock.lock()
        if let result = self.pendingResult {
            pendingResult = result
            self.pendingResult = nil
        } else if isResolved {
            pendingResult = .failure(CancellationError())
        } else {
            self.continuation = continuation
            pendingResult = nil
        }
        lock.unlock()

        if let pendingResult {
            continuation.resume(with: pendingResult)
        }
    }

    func resolve(_ result: Result<PTPTransportResponse, Error>) {
        let continuation: CheckedContinuation<PTPTransportResponse, Error>?

        lock.lock()
        guard !isResolved else {
            lock.unlock()
            return
        }

        isResolved = true
        if let installedContinuation = self.continuation {
            continuation = installedContinuation
            self.continuation = nil
        } else {
            continuation = nil
            pendingResult = result
        }
        lock.unlock()

        continuation?.resume(with: result)
    }
}

protocol NikonRuntimePTPSending {
    func send(_ intent: PTPCommandIntent) async throws -> PTPClientResult
    func resetSessionAfterDisconnect() async
}

extension PTPClient: NikonRuntimePTPSending {}

extension NikonRuntimePTPSending {
    func resetSessionAfterDisconnect() async {}
}

enum PTPDiagnosticEvent: Equatable {
    case discoveryStarted
    case discoveryAuthorization(contents: String, control: String)
    case discoveryBrowserSnapshot(
        cameraCount: Int,
        browserDeviceCount: Int,
        isBrowsing: Bool,
        contentsAuthorization: String,
        controlAuthorization: String
    )
    case discoveryFinished(cameraCount: Int)
    case selectedCamera(name: String, manufacturer: String, model: String, serialNumber: String?)
    case gateFailed(reason: String)
    case ptpSendStarted(
        operationCode: UInt16,
        transactionID: UInt32,
        parameters: [UInt32],
        diagnosticName: String,
        outboundByteCount: Int
    )
    case ptpSendFinished(
        operationCode: UInt16,
        transactionID: UInt32,
        responseCode: UInt16,
        payloadByteCount: Int,
        durationMilliseconds: Int
    )
    case ptpSendTimedOut(
        operationCode: UInt16,
        transactionID: UInt32,
        durationMilliseconds: Int
    )

    var fields: [String: String] {
        switch self {
        case .discoveryStarted:
            return ["event": "discovery.started"]
        case .discoveryAuthorization(let contents, let control):
            return [
                "event": "discovery.authorization",
                "contentsAuthorization": contents,
                "controlAuthorization": control
            ]
        case .discoveryBrowserSnapshot(
            let cameraCount,
            let browserDeviceCount,
            let isBrowsing,
            let contentsAuthorization,
            let controlAuthorization
        ):
            return [
                "event": "discovery.browserSnapshot",
                "cameraCount": "\(cameraCount)",
                "browserDeviceCount": "\(browserDeviceCount)",
                "browserIsBrowsing": isBrowsing ? "true" : "false",
                "contentsAuthorization": contentsAuthorization,
                "controlAuthorization": controlAuthorization
            ]
        case .discoveryFinished(let cameraCount):
            return ["event": "discovery.finished", "cameraCount": "\(cameraCount)"]
        case .selectedCamera(let name, let manufacturer, let model, let serialNumber):
            var fields = [
                "event": "camera.selected",
                "name": name,
                "manufacturer": manufacturer,
                "model": model
            ]
            if let serialNumber, !serialNumber.isEmpty {
                fields["serialNumber"] = PTPDiagnostics.redactedSerial(serialNumber)
            }
            return fields
        case .gateFailed(let reason):
            return ["event": "gate.failed", "reason": reason]
        case .ptpSendStarted(let operationCode, let transactionID, let parameters, let diagnosticName, let outboundByteCount):
            return [
                "event": "ptp.send.started",
                "operationCode": PTPDiagnostics.hex(operationCode),
                "transactionID": "\(transactionID)",
                "parameters": parameters.map(PTPDiagnostics.hex).joined(separator: ","),
                "diagnosticName": diagnosticName,
                "outboundByteCount": "\(outboundByteCount)"
            ]
        case .ptpSendFinished(let operationCode, let transactionID, let responseCode, let payloadByteCount, let durationMilliseconds):
            return [
                "event": "ptp.send.finished",
                "operationCode": PTPDiagnostics.hex(operationCode),
                "transactionID": "\(transactionID)",
                "responseCode": PTPDiagnostics.hex(responseCode),
                "payloadByteCount": "\(payloadByteCount)",
                "durationMilliseconds": "\(durationMilliseconds)"
            ]
        case .ptpSendTimedOut(let operationCode, let transactionID, let durationMilliseconds):
            return [
                "event": "ptp.send.timeout",
                "operationCode": PTPDiagnostics.hex(operationCode),
                "transactionID": "\(transactionID)",
                "durationMilliseconds": "\(durationMilliseconds)"
            ]
        }
    }
}

actor PTPDiagnosticsRecorder {
    private let appLog: AppDiagnosticsLog?
    private var storage: [PTPDiagnosticEvent] = []

    init(appLog: AppDiagnosticsLog? = nil) {
        self.appLog = appLog
    }

    func record(_ event: PTPDiagnosticEvent) {
        storage.append(event)
        appLog?.record("ptp.\(event.fields["event"] ?? "event")", fields: event.fields)
    }

    func events() -> [PTPDiagnosticEvent] {
        storage
    }
}

enum PTPDiagnostics {
    static func hex(_ value: UInt16) -> String {
        String(format: "0x%04X", value)
    }

    static func hex(_ value: UInt32) -> String {
        String(format: "0x%08X", value)
    }

    static func redactedSerial(_ serialNumber: String) -> String {
        guard serialNumber.count > 4 else { return "REDACTED" }
        return "REDACTED-\(serialNumber.suffix(4))"
    }
}

extension Data {
    mutating func appendLittleEndian(_ value: UInt16) {
        var littleEndian = value.littleEndian
        append(Data(bytes: &littleEndian, count: MemoryLayout<UInt16>.size))
    }

    mutating func appendLittleEndian(_ value: UInt32) {
        var littleEndian = value.littleEndian
        append(Data(bytes: &littleEndian, count: MemoryLayout<UInt32>.size))
    }

    func readLittleEndianUInt16(at offset: Int) throws -> UInt16 {
        guard offset >= 0, offset + 2 <= count else {
            throw PTPResponseParseError.truncated(minimumBytes: offset + 2, actualBytes: count)
        }
        return UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }

    func readUInt8(at offset: Int) throws -> UInt8 {
        guard offset >= 0, offset < count else {
            throw PTPResponseParseError.truncated(minimumBytes: offset + 1, actualBytes: count)
        }
        return self[offset]
    }

    func readLittleEndianUInt32(at offset: Int) throws -> UInt32 {
        guard offset >= 0, offset + 4 <= count else {
            throw PTPResponseParseError.truncated(minimumBytes: offset + 4, actualBytes: count)
        }
        return UInt32(self[offset]) |
            (UInt32(self[offset + 1]) << 8) |
            (UInt32(self[offset + 2]) << 16) |
            (UInt32(self[offset + 3]) << 24)
    }
}

private extension UInt32 {
    var littleEndianData: Data {
        var littleEndian = self.littleEndian
        return Data(bytes: &littleEndian, count: MemoryLayout<UInt32>.size)
    }
}
