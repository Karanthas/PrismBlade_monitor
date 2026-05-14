@testable import PrismBlade
import XCTest

final class LUTRepositoryTests: XCTestCase {
    func testLoadsBuiltInDescriptorOnlyWhenCubeExists() throws {
        let sandbox = try makeSandbox()
        let builtInDirectory = sandbox.appendingPathComponent("LUTs", isDirectory: true)
        try FileManager.default.createDirectory(at: builtInDirectory, withIntermediateDirectories: true)
        try CubeFixtureFactory.identity(size: 2, title: "Local Identity")
            .write(to: builtInDirectory.appendingPathComponent("LocalIdentity.cube"), atomically: true, encoding: .utf8)

        let repository = LUTRepository(
            documentsURL: sandbox.appendingPathComponent("Documents", isDirectory: true),
            builtInLUTDirectoryURL: builtInDirectory
        )

        let descriptors = repository.loadBuiltInDescriptors()

        XCTAssertEqual(descriptors.count, 1)
        XCTAssertEqual(descriptors[0].title, "Local Identity")
        XCTAssertEqual(descriptors[0].source, .builtIn)
        XCTAssertEqual(descriptors[0].fileName, "LocalIdentity.cube")

        let parsed = try repository.loadParsedLUT(for: descriptors[0])
        XCTAssertEqual(parsed.entries.count, 8)
    }

    func testMissingBuiltInDirectoryHidesLocalLUTs() throws {
        let sandbox = try makeSandbox()
        let repository = LUTRepository(
            documentsURL: sandbox.appendingPathComponent("Documents", isDirectory: true),
            builtInLUTDirectoryURL: sandbox.appendingPathComponent("Missing", isDirectory: true)
        )

        XCTAssertTrue(repository.loadBuiltInDescriptors().isEmpty)
    }

    func testImportedDescriptorCanReloadParsedEntries() async throws {
        let sandbox = try makeSandbox()
        let sourceURL = sandbox.appendingPathComponent("Imported.cube")
        try CubeFixtureFactory.redChannelRamp(size: 2, title: "Imported Ramp")
            .write(to: sourceURL, atomically: true, encoding: .utf8)

        let repository = LUTRepository(
            documentsURL: sandbox.appendingPathComponent("Documents", isDirectory: true),
            builtInLUTDirectoryURL: sandbox.appendingPathComponent("LUTs", isDirectory: true)
        )

        let descriptor = try await repository.importLUT(from: sourceURL)
        let parsed = try repository.loadParsedLUT(for: descriptor)

        XCTAssertEqual(parsed.title, "Imported Ramp")
        XCTAssertEqual(parsed.entries[1], SIMD3<Double>(1, 0, 0))
    }

    private func makeSandbox() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PrismBladeLUTRepositoryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }
}
