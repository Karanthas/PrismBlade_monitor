@testable import PrismBlade
import XCTest

final class LUTParserTests: XCTestCase {
    private let parser = LUTParser()

    func testParsesGeneratedIdentityCube() throws {
        let parsed = try parser.parse(CubeFixtureFactory.identity(size: 2, title: "Test Identity"))

        XCTAssertEqual(parsed.title, "Test Identity")
        XCTAssertEqual(parsed.cubeSize, 2)
        XCTAssertEqual(parsed.entries.count, 8)
        XCTAssertEqual(parsed.entries.first, SIMD3<Double>(0, 0, 0))
        XCTAssertEqual(parsed.entries.last, SIMD3<Double>(1, 1, 1))
        XCTAssertTrue(parsed.warnings.isEmpty)
    }

    func testParsesGeneratedWarmCube() throws {
        let parsed = try parser.parse(CubeFixtureFactory.warmOffset(size: 2))

        XCTAssertEqual(parsed.title, "Warm Offset")
        XCTAssertEqual(parsed.cubeSize, 2)
        XCTAssertEqual(parsed.entries.count, 8)
        XCTAssertEqual(parsed.entries[0], SIMD3<Double>(0.08, 0.03, 0))
    }

    func testClampsOutOfRangeDataAndPreservesDomain() throws {
        let parsed = try parser.parse(CubeFixtureFactory.outOfRangeDomainAndData())

        XCTAssertEqual(parsed.domainMin, SIMD3<Double>(-0.1, 0, 0))
        XCTAssertEqual(parsed.domainMax, SIMD3<Double>(1.1, 1, 1))
        XCTAssertEqual(parsed.entries[0], SIMD3<Double>(0, 0, 0))
        XCTAssertEqual(parsed.entries[1], SIMD3<Double>(1, 0, 0))
        XCTAssertEqual(parsed.entries[2], SIMD3<Double>(0, 1, 0))
        XCTAssertEqual(parsed.entries[3], SIMD3<Double>(0, 0, 1))
        XCTAssertEqual(parsed.warnings.count, 4)
    }

    func testRejectsInvalidSize() {
        XCTAssertThrowsError(try parser.parse(CubeFixtureFactory.invalidSize())) { error in
            XCTAssertEqual(error as? LUTImportError, .invalidCubeSize("LUT_3D_SIZE 1"))
        }
    }

    func testRejectsDataCountMismatch() {
        XCTAssertThrowsError(try parser.parse(CubeFixtureFactory.dataCountMismatch(size: 3, actualRows: 2))) { error in
            XCTAssertEqual(error as? LUTImportError, .dataCountMismatch(expected: 27, actual: 2))
        }
    }

    func testRejectsInvalidFloatData() {
        XCTAssertThrowsError(try parser.parse(CubeFixtureFactory.invalidFloat())) { error in
            XCTAssertEqual(
                error as? LUTImportError,
                .invalidRGBLine(line: 3, value: "nope 0.000000 0.000000")
            )
        }
    }
}
