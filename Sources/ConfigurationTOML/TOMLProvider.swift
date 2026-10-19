import Configuration

/// A configuration provider that reads values from TOML data.
///
/// Use `TOMLProvider` with `ConfigReader` to read configuration values from TOML-formatted
/// data. Nested keys use dot notation, which maps directly to TOML table hierarchies.
///
/// ## Usage
///
/// Create a provider from a TOML file:
///
/// ```swift
/// let provider = try await TOMLProvider(filePath: "/etc/config.toml")
/// let config = ConfigReader(provider: provider)
/// ```
///
/// The file is read once, when the provider is created. Use ``ReloadingTOMLProvider`` to
/// watch the file for changes.
///
/// ## Supported types
///
/// This provider supports the following `ConfigType` values:
/// - `.string`
/// - `.int`
/// - `.double`
/// - `.bool`
/// - `.bytes`
/// - `.stringArray`
/// - `.intArray`
/// - `.doubleArray`
/// - `.boolArray`
/// - `.byteChunkArray`
///
/// TOML date and time literals are represented as `.string` values.
public typealias TOMLProvider = FileProvider<TOMLSnapshot>

#if Reloading
    /// A configuration provider that reads values from a TOML file with automatic reloading.
    ///
    /// Use `ReloadingTOMLProvider` when you want to watch a TOML configuration file on disk and
    /// automatically reload it when it changes.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// let provider = try await ReloadingTOMLProvider(filePath: "/etc/config.toml")
    /// let config = ConfigReader(provider: provider)
    /// ```
    ///
    /// - Note: This provider is available only when the `Reloading` trait is enabled
    ///   for the `swift-configuration` and `swift-configuration-toml` packages.
    /// - SeeAlso: ``TOMLProvider``
    public typealias ReloadingTOMLProvider = ReloadingFileProvider<TOMLSnapshot>
#endif

/// Errors that can occur when creating or using a TOML provider.
public enum TOMLProviderError: Error, Sendable, CustomStringConvertible {
    /// The provided data is invalid.
    ///
    /// - Parameter message: A description of what was invalid.
    case invalidData(_ message: String)

    /// The TOML document contains a value that can't be represented.
    ///
    /// - Parameter message: A description of what was invalid.
    case invalidValue(_ message: String)

    public var description: String {
        switch self {
        case .invalidData(let message):
            return "Invalid TOML data: \(message)"
        case .invalidValue(let message):
            return "Invalid TOML value: \(message)"
        }
    }
}
