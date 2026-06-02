import XCTest
@testable import PrismBlade

final class NikonLiveViewPayloadParserTests: XCTestCase {
    func testExtractsJPEGWithVendorPrefixAndSuffix() throws {
        let parser = NikonLiveViewPayloadParser()
        let jpeg = Data([0xFF, 0xD8, 0x01, 0x02, 0xFF, 0xD9])
        let payload = Data([0x10, 0x20, 0x30]) + jpeg + Data([0x40, 0x50])

        XCTAssertEqual(try parser.extractJPEG(from: payload), jpeg)
    }

    func testChoosesFirstCompleteJPEGSpan() throws {
        let parser = NikonLiveViewPayloadParser()
        let first = Data([0xFF, 0xD8, 0xAA, 0xFF, 0xD9])
        let second = Data([0xFF, 0xD8, 0xBB, 0xFF, 0xD9])

        XCTAssertEqual(try parser.extractJPEG(from: first + second), first)
    }

    func testRejectsMissingSOI() {
        XCTAssertThrowsError(try NikonLiveViewPayloadParser().extractJPEG(from: Data([0x00, 0xFF, 0xD9]))) { error in
            XCTAssertEqual(error as? NikonLiveViewPayloadParserError, .missingSOI(signature: "00 FF D9"))
        }
    }

    func testRejectsMissingEOI() {
        XCTAssertThrowsError(try NikonLiveViewPayloadParser().extractJPEG(from: Data([0xFF, 0xD8, 0x11]))) { error in
            XCTAssertEqual(error as? NikonLiveViewPayloadParserError, .missingEOI(signature: "FF D8 11"))
        }
    }

    func testRejectsEOIBeforeSOI() {
        XCTAssertThrowsError(try NikonLiveViewPayloadParser().extractJPEG(from: Data([0xFF, 0xD9, 0xFF, 0xD8, 0x00]))) { error in
            XCTAssertEqual(error as? NikonLiveViewPayloadParserError, .eoiBeforeSOI(signature: "FF D9 FF D8 00"))
        }
    }

    func testRejectsOversizedPayload() {
        let parser = NikonLiveViewPayloadParser(maximumPayloadBytes: 3)

        XCTAssertThrowsError(try parser.extractJPEG(from: Data([0xFF, 0xD8, 0x00, 0xFF, 0xD9]))) { error in
            XCTAssertEqual(error as? NikonLiveViewPayloadParserError, .payloadTooLarge(limit: 3, actual: 5))
        }
    }
}
