import Foundation
import TOML

/// Decodes TOML documents into the value tree defined by the TOML specification.
///
/// The parsing itself is delegated to `swift-toml`, which wraps a spec-compliant C parser.
/// This type adapts that parser to the `Decodable` tree used by ``TOMLSnapshot`` and adds
/// human-readable descriptions for the parsed values.
enum TOMLDocumentDecoder {

    /// Parses a TOML document into its top-level table.
    ///
    /// - Parameter string: The TOML document to parse.
    /// - Returns: The top-level table of the document.
    /// - Throws: ``TOMLProviderError/invalidData(_:)`` if the document isn't valid UTF-8 or
    ///   isn't valid TOML.
    static func decode(_ string: String) throws -> [String: TOMLValue] {
        let decoder = TOMLDecoder()
        return try decoder.decode(TOMLTable.self, from: string).values
    }

    /// Returns the string representation of a TOML value.
    ///
    /// TOML date and time literals are surfaced as strings, using the representation from the
    /// TOML specification.
    ///
    /// - Parameter value: The value to describe.
    /// - Returns: The string representation, or `nil` if the value isn't string-like.
    static func stringValue(of value: TOMLValue) -> String? {
        switch value {
        case .string(let string):
            return string
        case .offsetDateTime, .localDateTime, .localDate, .localTime:
            return description(of: value)
        case .integer, .float, .boolean, .array, .table:
            return nil
        }
    }

    /// Returns a human-readable description of a TOML value.
    ///
    /// - Parameter value: The value to describe.
    /// - Returns: The description of the value.
    static func description(of value: TOMLValue) -> String {
        switch value {
        case .string(let string):
            return string
        case .integer(let integer):
            return integer.description
        case .float(let double):
            return double.description
        case .boolean(let boolean):
            return boolean.description
        case .offsetDateTime(let date):
            return date.formatted(.iso8601)
        case .localDateTime(let dateTime):
            return
                "\(padded(dateTime.year, width: 4))-\(padded(dateTime.month, width: 2))-\(padded(dateTime.day, width: 2))"
                + "T\(padded(dateTime.hour, width: 2)):\(padded(dateTime.minute, width: 2)):\(padded(dateTime.second, width: 2))"
        case .localDate(let date):
            return "\(padded(date.year, width: 4))-\(padded(date.month, width: 2))-\(padded(date.day, width: 2))"
        case .localTime(let time):
            return "\(padded(time.hour, width: 2)):\(padded(time.minute, width: 2)):\(padded(time.second, width: 2))"
        case .array(let array):
            if array.isEmpty { return "[]" }
            return array.map(description(of:)).joined(separator: ",")
        case .table:
            return "{...}"
        }
    }

    /// Formats a number using a fixed width, padding with leading zeros.
    private static func padded(_ value: Int, width: Int) -> String {
        let text = String(value)
        let isNegative = text.hasPrefix("-")
        let digits = isNegative ? String(text.dropFirst()) : text
        guard digits.count < width else { return text }
        let padding = String(repeating: "0", count: width - digits.count)
        return isNegative ? "-\(padding)\(digits)" : "\(padding)\(digits)"
    }
}

// MARK: - Decoding

/// A TOML document decoded into its top-level table.
private struct TOMLTable: Decodable {
    let values: [String: TOMLValue]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        var values: [String: TOMLValue] = [:]
        values.reserveCapacity(container.allKeys.count)
        for key in container.allKeys {
            values[key.stringValue] = try container.decode(TOMLValueBox.self, forKey: key).value
        }
        self.values = values
    }
}

/// A single TOML value decoded into a ``TOMLValue``.
///
/// `swift-toml` doesn't expose its parsed value tree directly, so the value is recovered by
/// probing the decoder for each type the TOML specification defines. Probing stops at the
/// first matching type, and only type mismatches are treated as "not this type"; any other
/// failure is propagated so malformed input keeps its original diagnostic.
private struct TOMLValueBox: Decodable {
    let value: TOMLValue

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        // Tables and arrays are probed first, because they're the only values that aren't
        // scalars.
        if let table = try container.decodeIfMatching([String: TOMLValueBox].self) {
            value = .table(table.mapValues(\.value))
        } else if let array = try container.decodeIfMatching([TOMLValueBox].self) {
            value = .array(array.map(\.value))
        } else if let string = try container.decodeIfMatching(String.self) {
            value = .string(string)
        } else if let integer = try container.decodeIfMatching(Int64.self) {
            // Integers are probed before floats, because a float also matches an integer.
            value = .integer(integer)
        } else if let double = try container.decodeIfMatching(Double.self) {
            value = .float(double)
        } else if let boolean = try container.decodeIfMatching(Bool.self) {
            value = .boolean(boolean)
        } else if let dateTime = try container.decodeIfMatching(LocalDateTime.self) {
            value = .localDateTime(dateTime)
        } else if let date = try container.decodeIfMatching(LocalDate.self) {
            value = .localDate(date)
        } else if let time = try container.decodeIfMatching(LocalTime.self) {
            value = .localTime(time)
        } else if let date = try container.decodeIfMatching(Date.self) {
            value = .offsetDateTime(date)
        } else {
            throw TOMLProviderError.invalidValue("Unsupported TOML value")
        }
    }
}

/// A coding key that accepts any string value.
private struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

extension SingleValueDecodingContainer {
    /// Decodes a value of the given type, or returns `nil` if the value has a different type.
    ///
    /// Only type mismatches are swallowed. Every other decoding failure is rethrown so that
    /// malformed input surfaces with its original diagnostic instead of being reported as an
    /// unsupported value.
    func decodeIfMatching<T: Decodable>(_ type: T.Type) throws -> T? {
        do {
            return try decode(type)
        } catch DecodingError.typeMismatch {
            return nil
        }
    }
}
