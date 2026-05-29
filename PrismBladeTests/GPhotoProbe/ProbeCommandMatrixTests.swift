import XCTest
@testable import GPhotoProbe

final class ProbeCommandMatrixTests: XCTestCase {
    func testFirstPassAllowsOnlyReadOnlyCommands() throws {
        let allowed: Set<ProbeCommand> = [
            .discovery,
            .summary,
            .abilities,
            .listConfig,
            .getConfig,
            .statusObservation,
            .eventObservation,
            .videoPathExistence,
            .exportDiagnostics
        ]

        XCTAssertEqual(ProbeCommandMatrix.firstPassAllowed, allowed)
        try allowed.forEach(ProbeCommandMatrix.validateFirstPass)
    }

    func testFirstPassRejectsMutatingCommands() {
        let forbidden: [ProbeCommand] = [
            .setConfig,
            .capture,
            .focus,
            .halfPress,
            .record,
            .deleteFile,
            .formatStorage,
            .fileDownload,
            .upload,
            .syncClock,
            .metadataWrite
        ]

        for command in forbidden {
            XCTAssertThrowsError(try ProbeCommandMatrix.validateFirstPass(command)) { error in
                XCTAssertEqual(error as? ProbeSafetyError, .forbiddenCommand(command))
            }
        }
    }

    func testReadOnlySuiteContainsNoForbiddenCommands() throws {
        try ReadOnlyProbeSuite().validateSuite()
        XCTAssertTrue(ReadOnlyProbeSuite.orderedCommands.allSatisfy(\.isFirstPassAllowed))
    }
}
