@testable import PrismBlade
import XCTest

final class CameraExposureRulesTests: XCTestCase {
    func testManualModeAllowsExposureParameters() {
        assertEnabled([.iso, .shutter, .aperture, .whiteBalance], in: .manual)
    }

    func testAperturePriorityLocksShutterOnly() {
        assertEnabled([.iso, .aperture, .whiteBalance], in: .aperturePriority)
        assertDisabled(.shutter, in: .aperturePriority, reason: "当前 A 模式下快门由相机控制")
    }

    func testShutterPriorityLocksApertureOnly() {
        assertEnabled([.iso, .shutter, .whiteBalance], in: .shutterPriority)
        assertDisabled(.aperture, in: .shutterPriority, reason: "当前 S 模式下光圈由相机控制")
    }

    func testProgramModeLocksShutterAndAperture() {
        assertEnabled([.iso, .whiteBalance], in: .program)
        assertDisabled(.shutter, in: .program, reason: "当前 P 模式下快门由相机控制")
        assertDisabled(.aperture, in: .program, reason: "当前 P 模式下光圈由相机控制")
    }

    func testAutoModeLocksExposureAndWhiteBalanceParameters() {
        assertEnabled([.exposureMode, .focusMode], in: .auto)
        assertDisabled(.iso, in: .auto, reason: "Auto 模式下 ISO 由相机控制")
        assertDisabled(.shutter, in: .auto, reason: "Auto 模式下曝光参数由相机控制")
        assertDisabled(.aperture, in: .auto, reason: "Auto 模式下曝光参数由相机控制")
        assertDisabled(.whiteBalance, in: .auto, reason: "Auto 模式下白平衡由相机控制")
    }

    private func assertEnabled(
        _ parameters: [CameraParameter],
        in mode: ExposureMode,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for parameter in parameters {
            let availability = CameraExposureRules.availability(for: parameter, in: mode)
            XCTAssertTrue(availability.isEnabled, "\(parameter) should be enabled in \(mode)", file: file, line: line)
            XCTAssertNil(availability.reason, file: file, line: line)
        }
    }

    private func assertDisabled(
        _ parameter: CameraParameter,
        in mode: ExposureMode,
        reason: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let availability = CameraExposureRules.availability(for: parameter, in: mode)
        XCTAssertFalse(availability.isEnabled, "\(parameter) should be disabled in \(mode)", file: file, line: line)
        XCTAssertEqual(availability.reason, reason, file: file, line: line)
    }
}
