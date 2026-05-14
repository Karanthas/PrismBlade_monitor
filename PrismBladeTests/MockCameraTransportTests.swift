@testable import PrismBlade
import XCTest

final class MockCameraTransportTests: XCTestCase {
    func testRequiresConnectionBeforeReadingState() async {
        let transport = MockCameraTransport()

        do {
            _ = try await transport.currentState()
            XCTFail("Expected currentState to fail before connect.")
        } catch let error as CameraTransportError {
            guard case .notConnected = error else {
                return XCTFail("Unexpected camera transport error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testConnectThenSetSupportedValue() async throws {
        let transport = MockCameraTransport()

        try await transport.connect()
        let state = try await transport.setValue("800", for: .iso)

        XCTAssertEqual(state.iso.current, "800")
    }

    func testRejectsUnsupportedOption() async throws {
        let transport = MockCameraTransport()
        try await transport.connect()

        do {
            _ = try await transport.setValue("12800", for: .iso)
            XCTFail("Expected unsupported ISO value to be rejected.")
        } catch let error as CameraTransportError {
            guard case .unsupportedValue(let parameter, let value) = error else {
                return XCTFail("Unexpected camera transport error: \(error)")
            }

            XCTAssertEqual(parameter, .iso)
            XCTAssertEqual(value, "12800")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testTransportEnforcesExposureModeLock() async throws {
        let transport = MockCameraTransport()

        try await transport.connect()
        _ = try await transport.setValue(ExposureMode.shutterPriority.rawValue, for: .exposureMode)

        do {
            _ = try await transport.setValue("f/4.0", for: .aperture)
            XCTFail("Expected aperture write to be rejected in shutter priority mode.")
        } catch let error as CameraTransportError {
            guard case .parameterLockedByExposureMode(let parameter, let mode) = error else {
                return XCTFail("Unexpected camera transport error: \(error)")
            }

            XCTAssertEqual(parameter, .aperture)
            XCTAssertEqual(mode, .shutterPriority)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testToggleRecordUpdatesRecordingStateAndStatus() async throws {
        let transport = MockCameraTransport()

        try await transport.connect()
        let state = try await transport.trigger(.toggleRecord)

        XCTAssertTrue(state.isRecording)
        XCTAssertEqual(state.lastActionStatus, "REC")
    }
}
