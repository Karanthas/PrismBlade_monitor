import XCTest

final class CPUReferenceTests: XCTestCase {
    func testLumaUsesRec709Weights() {
        XCTAssertEqual(CPUReference.rec709Luma(RGBDouble(red: 1, green: 0, blue: 0)), 0.2126, accuracy: 0.0001)
        XCTAssertEqual(CPUReference.rec709Luma(RGBDouble(red: 0, green: 1, blue: 0)), 0.7152, accuracy: 0.0001)
        XCTAssertEqual(CPUReference.rec709Luma(RGBDouble(red: 0, green: 0, blue: 1)), 0.0722, accuracy: 0.0001)
    }

    func testTrilinearIdentityLUTReturnsInput() {
        let entries = [
            RGBDouble(red: 0, green: 0, blue: 0),
            RGBDouble(red: 1, green: 0, blue: 0),
            RGBDouble(red: 0, green: 1, blue: 0),
            RGBDouble(red: 1, green: 1, blue: 0),
            RGBDouble(red: 0, green: 0, blue: 1),
            RGBDouble(red: 1, green: 0, blue: 1),
            RGBDouble(red: 0, green: 1, blue: 1),
            RGBDouble(red: 1, green: 1, blue: 1)
        ]

        let sampled = CPUReference.sampleTrilinear3DLUT(
            input: RGBDouble(red: 0.25, green: 0.5, blue: 0.75),
            entries: entries,
            size: 2
        )

        XCTAssertEqual(sampled.red, 0.25, accuracy: 0.0001)
        XCTAssertEqual(sampled.green, 0.5, accuracy: 0.0001)
        XCTAssertEqual(sampled.blue, 0.75, accuracy: 0.0001)
    }

    func testWaveformBinsAccumulateByColumnAndLuma() {
        let pixels = [
            RGBDouble(red: 0, green: 0, blue: 0),
            RGBDouble(red: 1, green: 1, blue: 1),
            RGBDouble(red: 1, green: 1, blue: 1),
            RGBDouble(red: 0, green: 0, blue: 0)
        ]

        let bins = CPUReference.waveformBins(pixels: pixels, width: 2, height: 2, binCount: 4)

        XCTAssertEqual(bins, [
            1, 0, 0, 1,
            1, 0, 0, 1
        ])
    }
}
