@testable import PrismBlade
import XCTest

final class CameraCommandServiceTests: XCTestCase {
    func testConnectReturnsCurrentTransportState() async throws {
        let transport = ScriptedCameraTransport()
        let service = CameraCommandService(transport: transport)

        let state = try await service.connect()

        XCTAssertTrue(transport.didConnect)
        XCTAssertEqual(state.exposureMode.current, ExposureMode.manual.rawValue)
    }

    func testSetValuePassesAllowedParameterToTransport() async throws {
        let transport = ScriptedCameraTransport()
        let service = CameraCommandService(transport: transport)

        let state = try await service.setValue("800", for: .iso)

        XCTAssertEqual(state.iso.current, "800")
        XCTAssertEqual(transport.setValueRequests, [SetValueRequest(value: "800", parameter: .iso)])
    }

    func testSetValueRejectsParameterLockedByExposureModeBeforeWritingTransport() async {
        let state = CameraState.mockInitial.withExposureMode(.shutterPriority)
        let transport = ScriptedCameraTransport(state: state)
        let service = CameraCommandService(transport: transport)

        do {
            _ = try await service.setValue("f/4.0", for: .aperture)
            XCTFail("Expected aperture write to be rejected in shutter priority mode.")
        } catch let error as CameraTransportError {
            guard case .parameterLockedByExposureMode(let parameter, let mode) = error else {
                return XCTFail("Unexpected camera transport error: \(error)")
            }

            XCTAssertEqual(parameter, .aperture)
            XCTAssertEqual(mode, .shutterPriority)
            XCTAssertTrue(transport.setValueRequests.isEmpty)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testTriggerForwardsActionToTransport() async throws {
        let transport = ScriptedCameraTransport()
        let service = CameraCommandService(transport: transport)

        let state = try await service.trigger(.toggleRecord)

        XCTAssertTrue(state.isRecording)
        XCTAssertEqual(transport.triggerRequests.count, 1)
    }
}

private final class ScriptedCameraTransport: CameraTransport {
    var didConnect = false
    var didDisconnect = false
    var setValueRequests: [SetValueRequest] = []
    var triggerRequests: [CameraAction] = []

    private var state: CameraState

    init(state: CameraState = .mockInitial) {
        self.state = state
    }

    func connect() async throws {
        didConnect = true
    }

    func disconnect() async {
        didDisconnect = true
    }

    func currentState() async throws -> CameraState {
        state
    }

    func setValue(_ value: String, for parameter: CameraParameter) async throws -> CameraState {
        setValueRequests.append(SetValueRequest(value: value, parameter: parameter))

        switch parameter {
        case .exposureMode:
            state.exposureMode.current = value
        case .iso:
            state.iso.current = value
        case .shutter:
            state.shutter.current = value
        case .aperture:
            state.aperture.current = value
        case .whiteBalance:
            state.whiteBalance.current = value
        case .focusMode:
            state.focusMode.current = value
        }

        return state
    }

    func trigger(_ action: CameraAction) async throws -> CameraState {
        triggerRequests.append(action)

        switch action {
        case .toggleRecord:
            state.isRecording.toggle()
        case .capture, .halfPress, .focus:
            break
        }

        return state
    }
}

private struct SetValueRequest: Equatable {
    var value: String
    var parameter: CameraParameter
}

private extension CameraState {
    func withExposureMode(_ mode: ExposureMode) -> CameraState {
        var copy = self
        copy.exposureMode.current = mode.rawValue
        return copy
    }
}
