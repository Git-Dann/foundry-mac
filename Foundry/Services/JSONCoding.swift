import Foundation

/// Shared JSON coders tuned for the Foundry web API.
///
/// The API serialises **camelCase** keys (so we do NOT use `.convertFromSnakeCase`) and emits
/// ISO‑8601 timestamps **with fractional seconds** (JS `Date.toISOString()` → `…T08:33:00.000Z`).
/// `JSONDecoder.iso8601` rejects fractional seconds, so we install a tolerant strategy that
/// accepts both fractional and whole‑second ISO‑8601.
extension JSONDecoder {
    static let foundry: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = ISO8601DateParser.date(from: raw) { return date }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unrecognised ISO‑8601 date: \(raw)"
            )
        }
        return decoder
    }()
}

extension JSONEncoder {
    static let foundry: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(ISO8601DateParser.string(from: date))
        }
        return encoder
    }()
}

/// ISO‑8601 parsing that tolerates fractional seconds (and their absence).
enum ISO8601DateParser {
    private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func date(from string: String) -> Date? {
        withFraction.date(from: string) ?? plain.date(from: string)
    }

    static func string(from date: Date) -> String {
        withFraction.string(from: date)
    }
}
