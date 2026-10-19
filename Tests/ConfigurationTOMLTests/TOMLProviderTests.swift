import Configuration
import ConfigurationTesting
import Foundation
import SystemPackage
import Testing

@testable import ConfigurationTOML

@Suite("TOMLProvider Tests")
struct TOMLProviderTests {
    private enum TestError: Error {
        case missingResource(String)
    }

    /// Returns the path of a bundled test resource.
    private func resourcePath(_ name: String) throws -> FilePath {
        guard let url = Bundle.module.url(forResource: name, withExtension: "toml", subdirectory: "Resources") else {
            throw TestError.missingResource(name)
        }
        return FilePath(url.path)
    }

    /// Writes a TOML document to a temporary file and returns its path.
    private func writeTemporaryFile(_ toml: String, named name: String = "config.toml") throws -> FilePath {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("configuration-toml-tests", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(UUID().uuidString)-\(name)")
        try Data(toml.utf8).write(to: url)
        return FilePath(url.path)
    }

    // MARK: - Reading values

    @Test("Provider reads values from a TOML file")
    func providerReadsValues() async throws {
        let filePath = try writeTemporaryFile(
            """
            name = "app"
            port = 8080
            debug = true

            [database]
            host = "localhost"
            """
        )

        let provider = try await TOMLProvider(filePath: filePath)
        let config = ConfigReader(provider: provider)

        #expect(try config.requiredString(forKey: "name") == "app")
        #expect(try config.requiredInt(forKey: "port") == 8080)
        #expect(try config.requiredBool(forKey: "debug") == true)
        #expect(try config.requiredString(forKey: "database.host") == "localhost")
    }

    @Test("Provider reads arrays and bytes")
    func providerReadsArraysAndBytes() async throws {
        let filePath = try writeTemporaryFile(
            """
            names = ["alpha", "beta"]
            ports = [8001, 8002]
            ratios = [0.5, 1.5]
            flags = [true, false]
            blobs = ["YWI=", "Yg=="]
            key = "bWFnaWM="
            """
        )

        let provider = try await TOMLProvider(filePath: filePath)
        let config = ConfigReader(provider: provider)

        #expect(config.stringArray(forKey: "names") == ["alpha", "beta"])
        #expect(config.intArray(forKey: "ports") == [8001, 8002])
        #expect(config.doubleArray(forKey: "ratios") == [0.5, 1.5])
        #expect(config.boolArray(forKey: "flags") == [true, false])
        #expect(config.byteChunkArray(forKey: "blobs") == [[0x61, 0x62], [0x62]])
        #expect(config.bytes(forKey: "key") == [0x6d, 0x61, 0x67, 0x69, 0x63])
    }

    @Test("Provider reads double values")
    func providerReadsDoubles() async throws {
        let filePath = try writeTemporaryFile("ratio = 0.25")
        let provider = try await TOMLProvider(filePath: filePath)
        let config = ConfigReader(provider: provider)

        #expect(config.double(forKey: "ratio") == 0.25)
        #expect(try config.requiredDouble(forKey: "ratio") == 0.25)
    }

    @Test("Provider exposes date and time literals as strings")
    func providerReadsDateTimes() async throws {
        let filePath = try writeTemporaryFile(
            """
            offset_datetime = 2024-01-02T03:04:05Z
            local_datetime = 2024-01-02T03:04:05
            local_date = 2024-01-02
            local_time = 03:04:05
            """
        )

        let provider = try await TOMLProvider(filePath: filePath)
        let config = ConfigReader(provider: provider)

        #expect(config.string(forKey: "offset_datetime") == "2024-01-02T03:04:05Z")
        #expect(config.string(forKey: "local_datetime") == "2024-01-02T03:04:05")
        #expect(config.string(forKey: "local_date") == "2024-01-02")
        #expect(config.string(forKey: "local_time") == "03:04:05")
    }

    // MARK: - Missing and mismatched values

    @Test("Required read throws when key is missing")
    func requiredReadThrowsOnMissingKey() async throws {
        let filePath = try writeTemporaryFile("existing = true")
        let provider = try await TOMLProvider(filePath: filePath)
        let config = ConfigReader(provider: provider)

        #expect(throws: (any Error).self) {
            try config.requiredString(forKey: "missing")
        }
    }

    @Test("Required read throws on type mismatch")
    func requiredReadThrowsOnTypeMismatch() async throws {
        let filePath = try writeTemporaryFile("value = 42")
        let provider = try await TOMLProvider(filePath: filePath)
        let config = ConfigReader(provider: provider)

        #expect(throws: (any Error).self) {
            try config.requiredString(forKey: "value")
        }
    }

    @Test("Optional read returns nil on missing key")
    func optionalReadReturnsNilOnMissingKey() async throws {
        let filePath = try writeTemporaryFile("existing = true")
        let provider = try await TOMLProvider(filePath: filePath)
        let config = ConfigReader(provider: provider)

        #expect(config.string(forKey: "missing") == nil)
    }

    @Test("Optional read returns nil on type mismatch")
    func optionalReadReturnsNilOnTypeMismatch() async throws {
        let filePath = try writeTemporaryFile("value = 42")
        let provider = try await TOMLProvider(filePath: filePath)
        let config = ConfigReader(provider: provider)

        #expect(config.string(forKey: "value") == nil)
    }

    @Test("Default value is returned for missing or invalid keys")
    func defaultValueFallback() async throws {
        let filePath = try writeTemporaryFile("name = \"app\"")
        let provider = try await TOMLProvider(filePath: filePath)
        let config = ConfigReader(provider: provider)

        #expect(config.string(forKey: "name", default: "fallback") == "app")
        #expect(config.string(forKey: "missing", default: "fallback") == "fallback")
    }

    // MARK: - Files

    @Test("Missing file throws when allowMissing is false")
    func missingFileThrows() async throws {
        let filePath = FilePath("/tmp/nonexistent-config-\(UUID().uuidString).toml")

        await #expect(throws: (any Error).self) {
            _ = try await TOMLProvider(filePath: filePath)
        }
    }

    @Test("Allow missing treats missing file as empty")
    func allowMissingTreatsMissingAsEmpty() async throws {
        let filePath = FilePath("/tmp/nonexistent-config-\(UUID().uuidString).toml")
        let provider = try await TOMLProvider(filePath: filePath, allowMissing: true)
        let config = ConfigReader(provider: provider)

        #expect(config.string(forKey: "anything") == nil)
    }

    @Test("Malformed file throws even when allowMissing is true")
    func malformedFileThrows() async throws {
        let filePath = try resourcePath("invalid")

        await #expect(throws: (any Error).self) {
            _ = try await TOMLProvider(filePath: filePath)
        }
        await #expect(throws: (any Error).self) {
            _ = try await TOMLProvider(filePath: filePath, allowMissing: true)
        }
    }

    @Test("Empty file is treated as an empty configuration")
    func emptyFile() async throws {
        let filePath = try writeTemporaryFile("", named: "empty.toml")
        let provider = try await TOMLProvider(filePath: filePath)
        let config = ConfigReader(provider: provider)

        #expect(config.string(forKey: "anything") == nil)
        #expect(provider.description.contains("0 values"))
    }

    // MARK: - Descriptions

    @Test("Provider prints a description of its values")
    func providerDescriptions() async throws {
        let provider = try await TOMLProvider(filePath: try resourcePath("config"))

        #expect(provider.description == "FileProvider<TOMLSnapshot>[24 values]")
        #expect(
            provider.debugDescription
                == "FileProvider<TOMLSnapshot>[24 values: bool=true, booly.array=true,false, "
                + "byteChunky.array=bWFnaWM=,bWFnaWMy, bytes=bWFnaWM=, double=3.14, doubly.array=3.14,2.72, "
                + "int=42, inty.array=42,24, local_date=2024-01-02, local_datetime=2024-01-02T03:04:05, "
                + "local_time=03:04:05, offset_datetime=2024-01-02T03:04:05Z, other.bool=false, "
                + "other.booly.array=false,true,true, other.byteChunky.array=bWFnaWM=,bWFnaWMy,bWFnaWM=, "
                + "other.bytes=bWFnaWMy, other.double=2.72, other.doubly.array=0.9,1.8, other.int=24, "
                + "other.inty.array=16,32, other.string=Other Hello, other.stringy.array=Hello,Swift, "
                + "string=Hello, stringy.array=Hello,World]"
        )
    }

    // MARK: - Parsing options

    @Test("Provider applies custom parsing options")
    func providerAppliesParsingOptions() async throws {
        let filePath = try writeTemporaryFile(
            """
            key = "6d61676963"
            password = "s3cret"
            """
        )

        let provider = try await TOMLProvider(
            parsingOptions: .init(
                bytesDecoder: .hex,
                secretsSpecifier: .dynamic { key, _ in key == "password" }
            ),
            filePath: filePath
        )
        let config = ConfigReader(provider: provider)

        #expect(config.bytes(forKey: "key") == [0x6d, 0x61, 0x67, 0x69, 0x63])
        #expect(provider.debugDescription.contains("password=<REDACTED>"))
    }

    // MARK: - Provider protocol conformance

    @Test("Provider can be used as a ConfigProvider")
    func providerConformsToConfigProvider() async throws {
        let filePath = try writeTemporaryFile("name = \"app\"")
        let provider = try await TOMLProvider(filePath: filePath)

        let providers: [any ConfigProvider] = [provider]
        let config = ConfigReader(providers: providers)

        #expect(config.string(forKey: "name") == "app")
    }

    @Test("Provider can be combined with other providers")
    func providerCombinesWithOtherProviders() async throws {
        let filePath = try writeTemporaryFile("fromFile = \"file\"")
        let provider = try await TOMLProvider(filePath: filePath)
        let config = ConfigReader(providers: [provider, InMemoryProvider(values: ["fromMemory": "memory"])])

        #expect(config.string(forKey: "fromFile") == "file")
        #expect(config.string(forKey: "fromMemory") == "memory")
    }

    @Test("Provider exposes a snapshot")
    func providerSnapshot() async throws {
        let provider = try await TOMLProvider(filePath: try resourcePath("config"))
        let snapshot = provider.snapshot()

        #expect(snapshot.providerName == "FileProvider<TOMLSnapshot>")
        #expect(
            try snapshot.value(forKey: AbsoluteConfigKey(["string"]), type: .string).value?.content == .string("Hello")
        )
    }

    @Test("Provider passes the provider compatibility suite")
    func providerCompatibility() async throws {
        let provider = try await TOMLProvider(filePath: try resourcePath("config"))

        try await ProviderCompatTest(provider: provider).runTest()
    }
}
