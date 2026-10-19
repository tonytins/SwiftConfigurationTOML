import Configuration
import Foundation
import SystemPackage
import TOML

/// A snapshot of configuration values parsed from TOML data.
///
/// This structure represents a point-in-time view of configuration values. It handles the
/// conversion from TOML types to configuration value types.
///
/// ## Usage
///
/// Use with ``FileProvider``:
///
/// ```swift
/// let provider = try await FileProvider<TOMLSnapshot>(filePath: "/etc/config.toml")
/// let config = ConfigReader(provider: provider)
/// ```
///
/// To parse TOML that isn't backed by a file, use ``init(string:providerName:parsingOptions:)``:
///
/// ```swift
/// let snapshot = try TOMLSnapshot(string: "port = 8080")
/// ```
///
/// ## Key mapping
///
/// TOML tables map onto nested configuration keys using dot notation, so the table
///
/// ```toml
/// [database]
/// host = "localhost"
/// ```
///
/// is read with `config.string(forKey: "database.host")`.
///
/// ## Type mapping
///
/// TOML values are converted to configuration values using the following rules:
///
/// | TOML          | Configuration                          |
/// | ------------- | -------------------------------------- |
/// | String        | `.string`, `.bytes`                    |
/// | Integer       | `.int`                                 |
/// | Float         | `.double`                              |
/// | Boolean       | `.bool`                                |
/// | Offset date-time | `.string`                         |
/// | Local date-time  | `.string`                         |
/// | Local date       | `.string`                         |
/// | Local time       | `.string`                         |
/// | Array of strings  | `.stringArray`, `.byteChunkArray`  |
/// | Array of integers | `.intArray`                       |
/// | Array of floats   | `.doubleArray`                     |
/// | Array of booleans | `.boolArray`                       |
///
/// Conversions are strict: an integer TOML value isn't converted to a `.double`, and a
/// `.doubleArray` requires every element to be a TOML float.
public struct TOMLSnapshot: Sendable {

    /// Errors that can occur when converting a TOML value to a configuration value.
    public enum Error: Swift.Error, Sendable, CustomStringConvertible {
        /// The underlying TOML value can't be converted to the requested ``ConfigType``.
        case configValueNotConvertible(name: String, type: ConfigType)

        /// The TOML integer is outside the range of a configuration integer.
        case integerOutOfRange(name: String, value: Int64)

        public var description: String {
            switch self {
            case .configValueNotConvertible(let name, let type):
                return "Config value not convertible: \(name) as \(type)"
            case .integerOutOfRange(let name, let value):
                return "Config value out of range: \(name) = \(value)"
            }
        }
    }

    /// Parsing options for TOML snapshot creation.
    ///
    /// Use this type to customize how TOML values are converted to configuration values,
    /// including byte decoding and secrets specification.
    public struct ParsingOptions: FileParsingOptions {
        /// A decoder of bytes from a string.
        public var bytesDecoder: any ConfigBytesFromStringDecoder

        /// A specifier for determining which configuration values should be treated as secrets.
        public var secretsSpecifier: SecretsSpecifier<String, any Sendable>

        /// Creates parsing options for TOML snapshots.
        ///
        /// - Parameters:
        ///   - bytesDecoder: The decoder to use for converting string values to byte arrays.
        ///   - secretsSpecifier: The specifier for identifying secret values.
        public init(
            bytesDecoder: some ConfigBytesFromStringDecoder = .base64,
            secretsSpecifier: SecretsSpecifier<String, any Sendable> = .none
        ) {
            self.bytesDecoder = bytesDecoder
            self.secretsSpecifier = secretsSpecifier
        }

        /// The default parsing options.
        ///
        /// Uses base64 byte decoding and treats no values as secrets.
        public static var `default`: Self { .init() }
    }

    private struct ValueWrapper: CustomStringConvertible, Sendable {
        let value: TOMLValue
        let isSecret: Bool

        var description: String {
            if isSecret { return "<REDACTED>" }
            return TOMLDocumentDecoder.description(of: value)
        }
    }

    private let values: [String: ValueWrapper]
    public let providerName: String
    private let bytesDecoder: any ConfigBytesFromStringDecoder

    private init(
        values: [String: ValueWrapper],
        providerName: String,
        bytesDecoder: any ConfigBytesFromStringDecoder
    ) {
        self.values = values
        self.providerName = providerName
        self.bytesDecoder = bytesDecoder
    }

    /// Creates a snapshot by parsing a TOML document.
    ///
    /// - Parameters:
    ///   - string: The TOML document to parse.
    ///   - providerName: The name of the provider that created the snapshot.
    ///   - parsingOptions: Options that customize how the document is parsed.
    /// - Throws: ``TOMLProviderError/invalidData(_:)`` if the document isn't valid TOML.
    public init(
        string: String,
        providerName: String = "TOMLSnapshot",
        parsingOptions: ParsingOptions = .default
    ) throws {
        let table = try TOMLDocumentDecoder.decode(string)
        self.init(
            values: Self.flattenValues(table, secretsSpecifier: parsingOptions.secretsSpecifier),
            providerName: providerName,
            bytesDecoder: parsingOptions.bytesDecoder
        )
    }

    private static func encodeKeyComponents(_ components: [String]) -> String {
        components.joined(separator: ".")
    }

    private static func encodeKey(_ key: AbsoluteConfigKey) -> String {
        encodeKeyComponents(key.components)
    }

    private static func dataFromRawSpan(_ data: RawSpan) -> Data {
        data.withUnsafeBytes { Data($0) }
    }

    private static func flattenValues(
        _ table: [String: TOMLValue],
        secretsSpecifier: SecretsSpecifier<String, any Sendable>
    ) -> [String: ValueWrapper] {
        var values: [String: ValueWrapper] = [:]
        flatten(
            table,
            into: &values,
            keyComponents: [],
            secretsSpecifier: secretsSpecifier
        )
        return values
    }

    /// Flattens nested tables into dot-separated keys.
    ///
    /// Tables don't produce configuration values of their own; only the leaves of the tree do.
    private static func flatten(
        _ table: [String: TOMLValue],
        into values: inout [String: ValueWrapper],
        keyComponents: [String],
        secretsSpecifier: SecretsSpecifier<String, any Sendable>
    ) {
        for (key, value) in table {
            var components = keyComponents
            components.append(key)
            if case .table(let nested) = value {
                flatten(
                    nested,
                    into: &values,
                    keyComponents: components,
                    secretsSpecifier: secretsSpecifier
                )
            } else {
                let encodedKey = encodeKeyComponents(components)
                let isSecret = secretsSpecifier.isSecret(
                    key: encodedKey,
                    value: TOMLDocumentDecoder.description(of: value)
                )
                values[encodedKey] = ValueWrapper(value: value, isSecret: isSecret)
            }
        }
    }

    private func parseValue(
        _ valueWrapper: ValueWrapper,
        key: AbsoluteConfigKey,
        type: ConfigType
    ) throws -> ConfigValue {
        func throwMismatch() throws -> Never {
            throw Error.configValueNotConvertible(name: key.description, type: type)
        }

        let value = valueWrapper.value
        let content: ConfigContent

        func mapArray<T>(_ transform: (TOMLValue) throws -> T) throws -> [T] {
            guard case .array(let array) = value else { try throwMismatch() }
            return try array.map(transform)
        }

        func intValue(_ integer: Int64) throws -> Int {
            guard let int = Int(exactly: integer) else {
                throw Error.integerOutOfRange(name: key.description, value: integer)
            }
            return int
        }

        switch type {
        case .string:
            guard let string = TOMLDocumentDecoder.stringValue(of: value) else { try throwMismatch() }
            content = .string(string)
        case .int:
            guard case .integer(let integer) = value else { try throwMismatch() }
            content = .int(try intValue(integer))
        case .double:
            guard case .float(let double) = value else { try throwMismatch() }
            content = .double(double)
        case .bool:
            guard case .boolean(let boolean) = value else { try throwMismatch() }
            content = .bool(boolean)
        case .bytes:
            guard case .string(let string) = value, let bytes = bytesDecoder.decode(string) else { try throwMismatch() }
            content = .bytes(bytes)
        case .stringArray:
            let strings = try mapArray { item -> String in
                guard case .string(let string) = item else { try throwMismatch() }
                return string
            }
            content = .stringArray(strings)
        case .intArray:
            let ints = try mapArray { item -> Int in
                guard case .integer(let integer) = item else { try throwMismatch() }
                return try intValue(integer)
            }
            content = .intArray(ints)
        case .doubleArray:
            let doubles = try mapArray { item -> Double in
                guard case .float(let double) = item else { try throwMismatch() }
                return double
            }
            content = .doubleArray(doubles)
        case .boolArray:
            let bools = try mapArray { item -> Bool in
                guard case .boolean(let boolean) = item else { try throwMismatch() }
                return boolean
            }
            content = .boolArray(bools)
        case .byteChunkArray:
            let chunks = try mapArray { item -> [UInt8] in
                guard case .string(let string) = item, let bytes = bytesDecoder.decode(string) else {
                    try throwMismatch()
                }
                return bytes
            }
            content = .byteChunkArray(chunks)
        }

        return ConfigValue(content, isSecret: valueWrapper.isSecret)
    }
}

// MARK: - CustomStringConvertible

extension TOMLSnapshot: CustomStringConvertible {
    public var description: String {
        "\(providerName)[\(values.count) values]"
    }
}

// MARK: - CustomDebugStringConvertible

extension TOMLSnapshot: CustomDebugStringConvertible {
    public var debugDescription: String {
        let prettyValues =
            values
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ", ")
        return "\(providerName)[\(values.count) values: \(prettyValues)]"
    }
}

// MARK: - ConfigSnapshot

extension TOMLSnapshot: ConfigSnapshot {
    public func value(forKey key: AbsoluteConfigKey, type: ConfigType) throws -> LookupResult {
        let encodedKey = Self.encodeKey(key)
        guard let value = values[encodedKey] else {
            return .init(encodedKey: encodedKey, value: nil)
        }
        return .init(encodedKey: encodedKey, value: try parseValue(value, key: key, type: type))
    }
}

// MARK: - FileConfigSnapshot

extension TOMLSnapshot: FileConfigSnapshot {
    public init(data: RawSpan, providerName: String, parsingOptions: ParsingOptions) throws {
        let fileData = Self.dataFromRawSpan(data)
        guard let string = String(data: fileData, encoding: .utf8) else {
            throw TOMLProviderError.invalidData("Unable to decode data as UTF-8")
        }
        try self.init(string: string, providerName: providerName, parsingOptions: parsingOptions)
    }
}
