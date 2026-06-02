import Foundation

struct NikonLiveViewPayloadParser: Sendable {
    var maximumPayloadBytes: Int = 16 * 1024 * 1024

    func extractJPEG(from payload: Data) throws -> Data {
        guard payload.count <= maximumPayloadBytes else {
            throw NikonLiveViewPayloadParserError.payloadTooLarge(limit: maximumPayloadBytes, actual: payload.count)
        }

        let bytes = [UInt8](payload)
        let firstEOI = Self.firstMarker(first: 0xFF, second: 0xD9, in: bytes, startingAt: 0)
        guard let soi = Self.firstMarker(first: 0xFF, second: 0xD8, in: bytes, startingAt: 0) else {
            throw NikonLiveViewPayloadParserError.missingSOI(signature: Self.signature(bytes))
        }
        if let firstEOI, firstEOI < soi {
            throw NikonLiveViewPayloadParserError.eoiBeforeSOI(signature: Self.signature(bytes))
        }
        guard let eoi = Self.firstMarker(first: 0xFF, second: 0xD9, in: bytes, startingAt: soi + 2) else {
            throw NikonLiveViewPayloadParserError.missingEOI(signature: Self.signature(bytes))
        }

        return Data(bytes[soi...(eoi + 1)])
    }

    private static func firstMarker(first: UInt8, second: UInt8, in bytes: [UInt8], startingAt start: Int) -> Int? {
        guard bytes.count >= 2, start < bytes.count - 1 else { return nil }

        for index in max(start, 0)..<(bytes.count - 1) where bytes[index] == first && bytes[index + 1] == second {
            return index
        }
        return nil
    }

    private static func signature(_ bytes: [UInt8]) -> String {
        bytes.prefix(8).map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}

enum NikonLiveViewPayloadParserError: Error, Equatable, LocalizedError {
    case missingSOI(signature: String)
    case missingEOI(signature: String)
    case eoiBeforeSOI(signature: String)
    case payloadTooLarge(limit: Int, actual: Int)

    var errorDescription: String? {
        switch self {
        case .missingSOI(let signature):
            return "Nikon live-view payload did not contain a JPEG SOI marker. Signature: \(signature)."
        case .missingEOI(let signature):
            return "Nikon live-view payload did not contain a JPEG EOI marker. Signature: \(signature)."
        case .eoiBeforeSOI(let signature):
            return "Nikon live-view payload contained EOI before SOI. Signature: \(signature)."
        case .payloadTooLarge(let limit, let actual):
            return "Nikon live-view payload had \(actual) bytes; limit is \(limit)."
        }
    }
}
