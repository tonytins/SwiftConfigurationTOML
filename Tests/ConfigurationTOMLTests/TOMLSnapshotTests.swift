import Configuration
import Foundation
import SystemPackage
import Testing

@testable import ConfigurationTOML

/// Creates a configuration key from its components, for brevity in tests.
private func key(_ components: String...) -> AbsoluteConfigKey {
    AbsoluteConfigKey(components)
}

@Suite("TOMLSnapshot Tests")
struct TOMLSnapshotTests {
    private enum TestError: Error {
        case unexpectedContent
    }

    private func makeSnapshot(
        _ toml: String,
        providerName: String = "test",
        parsingOptions: TOMLSnapshot.ParsingOptions = .default
    ) throws -> TOMLSnapshot {
        try TOMLSnapshot(string: toml, providerName: providerName, parsingOptions: parsingOptions)
    }

    private func content(of result: LookupResult) throws -> ConfigContent {
        guard let content = result.value?.content else {
            throw TestError.unexpectedContent
        }
        return content
    }

    private func stringValue(of result: LookupResult) throws -> String {
        guard case .string(let string) = try content(of: result) else {
            throw TestError.unexpectedContent
        }
        return string
    }

    // MARK: - Scalars

    @Test("Parses basic string, int, double, bool")
    func basicTypes() throws {
        let snapshot = try makeSnapshot(
            """
            string = "hello"
            int = 42
            double = 3.14
            bool = true
            """
        )

        #expect(try content(of: snapshot.value(forKey: key("string"), type: .string)) == .string("hello"))
        #expect(try content(of: snapshot.value(forKey: key("int"), type: .int)) == .int(42))
        #expect(try content(of: snapshot.value(forKey: key("double"), type: .double)) == .double(3.14))
        #expect(try content(of: snapshot.value(forKey: key("bool"), type: .bool)) == .bool(true))
    }

    @Test("Parses negative and boundary integers")
    func boundaryIntegers() throws {
        let snapshot = try makeSnapshot(
            """
            zero = 0
            negative = -17
            max = 9223372036854775807
            min = -9223372036854775808
            """
        )

        #expect(try content(of: snapshot.value(forKey: key("zero"), type: .int)) == .int(0))
        #expect(try content(of: snapshot.value(forKey: key("negative"), type: .int)) == .int(-17))
        #expect(try content(of: snapshot.value(forKey: key("max"), type: .int)) == .int(Int(Int64.max)))
        #expect(try content(of: snapshot.value(forKey: key("min"), type: .int)) == .int(Int(Int64.min)))
    }

    @Test("Parses hexadecimal, octal, binary, and underscored integers")
    func integerNotations() throws {
        let snapshot = try makeSnapshot(
            """
            hex = 0xDEADBEEF
            octal = 0o755
            binary = 0b1010
            grouped = 1_000_000
            """
        )

        #expect(try content(of: snapshot.value(forKey: key("hex"), type: .int)) == .int(0xDEADBEEF))
        #expect(try content(of: snapshot.value(forKey: key("octal"), type: .int)) == .int(0o755))
        #expect(try content(of: snapshot.value(forKey: key("binary"), type: .int)) == .int(0b1010))
        #expect(try content(of: snapshot.value(forKey: key("grouped"), type: .int)) == .int(1_000_000))
    }

    @Test("Parses special float values")
    func specialFloats() throws {
        let snapshot = try makeSnapshot(
            """
            positive = inf
            negative = -inf
            exponent = 5e+22
            """
        )

        #expect(try content(of: snapshot.value(forKey: key("positive"), type: .double)) == .double(.infinity))
        #expect(try content(of: snapshot.value(forKey: key("negative"), type: .double)) == .double(-.infinity))
        #expect(try content(of: snapshot.value(forKey: key("exponent"), type: .double)) == .double(5e22))
    }

    @Test("Parses strings with escapes, unicode, and multiline content")
    func stringForms() throws {
        let snapshot = try makeSnapshot(
            """
            escaped = "tab:\\t quote:\\" backslash:\\\\"
            unicode = "caf\u{00e9} \u{1F600}"
            literal = 'C:\\Users\\nope'
            multiline = \"\"\"
            first
            second\"\"\"
            """
        )

        #expect(try stringValue(of: snapshot.value(forKey: key("escaped"), type: .string)) == "tab:\t quote:\" backslash:\\")
        #expect(try stringValue(of: snapshot.value(forKey: key("unicode"), type: .string)) == "caf\u{00e9} \u{1F600}")
        #expect(try stringValue(of: snapshot.value(forKey: key("literal"), type: .string)) == "C:\\Users\\nope")
        #expect(try stringValue(of: snapshot.value(forKey: key("multiline"), type: .string)) == "first\nsecond")
    }

    @Test("Parses quoted keys")
    func quotedKeys() throws {
        let snapshot = try makeSnapshot(
            """
            "quoted key" = 1
            'literal key' = 2
            """
        )

        #expect(try content(of: snapshot.value(forKey: key("quoted key"), type: .int)) == .int(1))
        #expect(try content(of: snapshot.value(forKey: key("literal key"), type: .int)) == .int(2))
    }

    // MARK: - Tables

    @Test("Parses nested tables with dot notation")
    func nestedTables() throws {
        let snapshot = try makeSnapshot(
            """
            [database]
            host = "localhost"
            port = 5432

            [api]
            timeout = 30.0
            enabled = false
            """
        )

        #expect(try content(of: snapshot.value(forKey: key("database", "host"), type: .string)) == .string("localhost"))
        #expect(try content(of: snapshot.value(forKey: key("database", "port"), type: .int)) == .int(5432))
        #expect(try content(of: snapshot.value(forKey: key("api", "timeout"), type: .double)) == .double(30.0))
        #expect(try content(of: snapshot.value(forKey: key("api", "enabled"), type: .bool)) == .bool(false))
    }

    @Test("Parses deeply nested tables")
    func deepNestedTables() throws {
        let snapshot = try makeSnapshot(
            """
            [a.b.c.d]
            key = "deep"
            """
        )

        #expect(try content(of: snapshot.value(forKey: key("a", "b", "c", "d", "key"), type: .string)) == .string("deep"))
    }

    @Test("Parses tables declared at the same level")
    func multipleTables() throws {
        let snapshot = try makeSnapshot(
            """
            [server]
            host = "example.com"

            [server.auth]
            token = "abc123"
            """
        )

        #expect(try content(of: snapshot.value(forKey: key("server", "host"), type: .string)) == .string("example.com"))
        #expect(try content(of: snapshot.value(forKey: key("server", "auth", "token"), type: .string)) == .string("abc123"))
    }

    @Test("Parses dotted keys")
    func dottedKeys() throws {
        let snapshot = try makeSnapshot(
            """
            database.host = "localhost"
            database.port = 5432
            """
        )

        #expect(try content(of: snapshot.value(forKey: key("database", "host"), type: .string)) == .string("localhost"))
        #expect(try content(of: snapshot.value(forKey: key("database", "port"), type: .int)) == .int(5432))
    }

    @Test("Parses inline tables")
    func inlineTables() throws {
        let snapshot = try makeSnapshot(#"server = { host = "localhost", port = 5432 }"#)

        #expect(try content(of: snapshot.value(forKey: key("server", "host"), type: .string)) == .string("localhost"))
        #expect(try content(of: snapshot.value(forKey: key("server", "port"), type: .int)) == .int(5432))
    }

    @Test("Parses arrays of tables as a single value")
    func arraysOfTables() throws {
        // Arrays of tables aren't flattened into indexed keys; the whole array is stored
        // under the table's key.
        let snapshot = try makeSnapshot(
            """
            [[products]]
            name = "Hammer"

            [[products]]
            name = "Nail"
            """
        )

        #expect(throws: TOMLSnapshot.Error.self) {
            _ = try snapshot.value(forKey: key("products"), type: .stringArray)
        }
        #expect(try snapshot.value(forKey: key("products", "name"), type: .string).value == nil)
    }

    // MARK: - Arrays

    @Test("Parses arrays")
    func arrays() throws {
        let snapshot = try makeSnapshot(
            """
            strings = ["a", "b", "c"]
            ints = [1, 2, 3]
            doubles = [1.1, 2.2]
            bools = [true, false, true]
            bytes = ["YWI=", "YmM="]
            """
        )

        #expect(try content(of: snapshot.value(forKey: key("strings"), type: .stringArray)) == .stringArray(["a", "b", "c"]))
        #expect(try content(of: snapshot.value(forKey: key("ints"), type: .intArray)) == .intArray([1, 2, 3]))
        #expect(try content(of: snapshot.value(forKey: key("doubles"), type: .doubleArray)) == .doubleArray([1.1, 2.2]))
        #expect(try content(of: snapshot.value(forKey: key("bools"), type: .boolArray)) == .boolArray([true, false, true]))
        #expect(
            try content(of: snapshot.value(forKey: key("bytes"), type: .byteChunkArray))
                == .byteChunkArray([[0x61, 0x62], [0x62, 0x63]])
        )
    }

    @Test("Parses empty arrays")
    func emptyArrays() throws {
        let snapshot = try makeSnapshot("empty = []")

        #expect(try content(of: snapshot.value(forKey: key("empty"), type: .stringArray)) == .stringArray([]))
        #expect(try content(of: snapshot.value(forKey: key("empty"), type: .intArray)) == .intArray([]))
    }

    @Test("Rejects arrays with mismatched element types")
    func mismatchedArrayElements() throws {
        let snapshot = try makeSnapshot("mixed = [1, \"two\"]")

        #expect(throws: TOMLSnapshot.Error.self) {
            _ = try snapshot.value(forKey: key("mixed"), type: .intArray)
        }
        #expect(throws: TOMLSnapshot.Error.self) {
            _ = try snapshot.value(forKey: key("mixed"), type: .stringArray)
        }
    }

    // MARK: - Date and time

    @Test("Parses date and time values as strings")
    func dateTimeValues() throws {
        let snapshot = try makeSnapshot(
            """
            date = 2026-10-19
            time = 14:23:45
            datetime = 2026-10-19T14:23:45
            offset = 2026-10-19T14:23:45Z
            """
        )

        #expect(try stringValue(of: snapshot.value(forKey: key("date"), type: .string)) == "2026-10-19")
        #expect(try stringValue(of: snapshot.value(forKey: key("time"), type: .string)) == "14:23:45")
        #expect(try stringValue(of: snapshot.value(forKey: key("datetime"), type: .string)) == "2026-10-19T14:23:45")
        #expect(try stringValue(of: snapshot.value(forKey: key("offset"), type: .string)) == "2026-10-19T14:23:45Z")
    }

    @Test("Date and time values aren't convertible to other types")
    func dateTimeTypeMismatch() throws {
        let snapshot = try makeSnapshot("date = 2026-10-19")

        #expect(throws: TOMLSnapshot.Error.self) {
            _ = try snapshot.value(forKey: key("date"), type: .int)
        }
    }

    // MARK: - Lookups

    @Test("Missing key returns nil value")
    func missingKey() throws {
        let snapshot = try makeSnapshot("exists = true")

        let result = try snapshot.value(forKey: key("missing"), type: .string)
        #expect(result.value == nil)
        #expect(result.encodedKey == "missing")
    }

    @Test("Looking up a table returns nil value")
    func tableLookupReturnsNil() throws {
        let snapshot = try makeSnapshot(
            """
            [table]
            key = "value"
            """
        )

        #expect(try snapshot.value(forKey: key("table"), type: .string).value == nil)
    }

    @Test("Type mismatch throws configValueNotConvertible")
    func typeMismatchThrows() throws {
        let snapshot = try makeSnapshot("value = 42")

        #expect(throws: TOMLSnapshot.Error.self) {
            _ = try snapshot.value(forKey: key("value"), type: .string)
        }
        #expect(throws: TOMLSnapshot.Error.self) {
            _ = try snapshot.value(forKey: key("value"), type: .bool)
        }
        #expect(throws: TOMLSnapshot.Error.self) {
            _ = try snapshot.value(forKey: key("value"), type: .double)
        }
        #expect(throws: TOMLSnapshot.Error.self) {
            _ = try snapshot.value(forKey: key("value"), type: .stringArray)
        }
    }

    @Test("Type mismatch error carries the key and type")
    func typeMismatchErrorDetails() throws {
        let snapshot = try makeSnapshot("value = 42")

        do {
            _ = try snapshot.value(forKey: key("value"), type: .string)
            Issue.record("Expected a type mismatch to throw")
        } catch let error as TOMLSnapshot.Error {
            guard case .configValueNotConvertible(let name, let type) = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
            #expect(name == "value")
            #expect(type == .string)
            #expect(error.description == "Config value not convertible: value as string")
        }
    }

    @Test("Strings aren't converted to bytes when the decoder rejects them")
    func invalidBytesThrows() throws {
        let snapshot = try makeSnapshot("value = \"not base64!\"")

        #expect(throws: TOMLSnapshot.Error.self) {
            _ = try snapshot.value(forKey: key("value"), type: .bytes)
        }
    }

    // MARK: - Documents

    @Test("Empty document has no values")
    func emptyDocument() throws {
        let snapshot = try makeSnapshot("")

        #expect(try snapshot.value(forKey: key("anything"), type: .string).value == nil)
        #expect(snapshot.description.contains("0 values"))
    }

    @Test("Document with only comments has no values")
    func commentOnlyDocument() throws {
        let snapshot = try makeSnapshot("# just a comment\n")

        #expect(try snapshot.value(forKey: key("anything"), type: .string).value == nil)
    }

    @Test("Invalid TOML syntax throws")
    func invalidTOMLSyntax() throws {
        #expect(throws: (any Error).self) {
            _ = try makeSnapshot("= not valid toml")
        }
        #expect(throws: (any Error).self) {
            _ = try makeSnapshot("[unterminated")
        }
        #expect(throws: (any Error).self) {
            _ = try makeSnapshot("duplicate = 1\nduplicate = 2")
        }
    }

    @Test("Invalid TOML syntax reports the location of the error")
    func invalidTOMLSyntaxReportsLocation() throws {
        do {
            _ = try makeSnapshot("valid = 1\nthis is not valid\n")
            Issue.record("Expected invalid TOML to throw")
        } catch {
            let description = String(describing: error)
            #expect(description.contains("line"))
            #expect(description.contains("column"))
        }
    }

    @Test("Invalid UTF-8 data throws invalidData")
    func invalidUTF8Data() throws {
        let data = Data([0xFF, 0xFE])

        #expect(throws: TOMLProviderError.self) {
            _ = try TOMLSnapshot(data: data.bytes, providerName: "test", parsingOptions: .default)
        }
    }

    @Test("Parses UTF-8 data from a raw span")
    func validUTF8Data() throws {
        let data = Data("value = 42".utf8)

        let snapshot = try TOMLSnapshot(data: data.bytes, providerName: "test", parsingOptions: .default)
        #expect(try content(of: snapshot.value(forKey: key("value"), type: .int)) == .int(42))
    }

    // MARK: - Descriptions

    @Test("Description and debug description format correctly")
    func descriptions() throws {
        let snapshot = try makeSnapshot("a = 1\nb = 2", providerName: "myProvider")

        #expect(snapshot.description == "myProvider[2 values]")
        #expect(snapshot.debugDescription == "myProvider[2 values: a=1, b=2]")
    }

    @Test("Debug description sorts values and describes arrays")
    func debugDescriptionFormat() throws {
        let snapshot = try makeSnapshot(
            """
            zebra = 1
            array = [1, 2, 3]
            alpha = "text"
            """
        )

        #expect(snapshot.debugDescription == "test[3 values: alpha=text, array=1,2,3, zebra=1]")
    }

    @Test("Provider name is exposed")
    func providerName() throws {
        let snapshot = try makeSnapshot("a = 1", providerName: "custom")

        #expect(snapshot.providerName == "custom")
    }

    // MARK: - Secrets

    @Test("Secrets specifier marks matching values")
    func secretsSpecifier() throws {
        let options = TOMLSnapshot.ParsingOptions(
            bytesDecoder: .base64,
            secretsSpecifier: .dynamic { key, _ in key == "password" }
        )
        let snapshot = try makeSnapshot(
            """
            password = "s3cret"
            username = "admin"
            """,
            parsingOptions: options
        )

        #expect(try snapshot.value(forKey: key("password"), type: .string).value?.isSecret == true)
        #expect(try snapshot.value(forKey: key("username"), type: .string).value?.isSecret == false)
    }

    @Test("Secrets specifier applies to nested keys")
    func secretsSpecifierNestedKeys() throws {
        let options = TOMLSnapshot.ParsingOptions(
            secretsSpecifier: .dynamic { key, _ in key.contains("token") }
        )
        let snapshot = try makeSnapshot(
            """
            [auth]
            token = "abc"
            other = "value"
            """,
            parsingOptions: options
        )

        #expect(try snapshot.value(forKey: key("auth", "token"), type: .string).value?.isSecret == true)
        #expect(try snapshot.value(forKey: key("auth", "other"), type: .string).value?.isSecret == false)
    }

    @Test("Secrets specifier supports specific, all, and none")
    func secretsSpecifierVariants() throws {
        let specific = try makeSnapshot(
            "key = \"value\"",
            parsingOptions: .init(secretsSpecifier: .specific(["key"]))
        )
        #expect(try specific.value(forKey: key("key"), type: .string).value?.isSecret == true)

        let all = try makeSnapshot(
            "key = \"value\"",
            parsingOptions: .init(secretsSpecifier: .all)
        )
        #expect(try all.value(forKey: key("key"), type: .string).value?.isSecret == true)

        let none = try makeSnapshot(
            "key = \"value\"",
            parsingOptions: .init(secretsSpecifier: .none)
        )
        #expect(try none.value(forKey: key("key"), type: .string).value?.isSecret == false)
    }

    @Test("Secret values are redacted in descriptions")
    func secretRedaction() throws {
        let options = TOMLSnapshot.ParsingOptions(
            secretsSpecifier: .dynamic { key, _ in key == "password" }
        )
        let snapshot = try makeSnapshot(
            """
            password = "s3cret"
            username = "admin"
            """,
            parsingOptions: options
        )

        #expect(snapshot.debugDescription.contains("password=<REDACTED>"))
        #expect(!snapshot.debugDescription.contains("s3cret"))
        #expect(snapshot.debugDescription.contains("username=admin"))
    }

    @Test("Secrets specifier receives the value as well as the key")
    func secretsSpecifierReceivesValue() throws {
        let options = TOMLSnapshot.ParsingOptions(
            secretsSpecifier: .dynamic { _, value in (value as? String) == "s3cret" }
        )
        let snapshot = try makeSnapshot(
            """
            password = "s3cret"
            username = "admin"
            """,
            parsingOptions: options
        )

        #expect(try snapshot.value(forKey: key("password"), type: .string).value?.isSecret == true)
        #expect(try snapshot.value(forKey: key("username"), type: .string).value?.isSecret == false)
    }

    // MARK: - Bytes

    @Test("Decodes base64 bytes with the default decoder")
    func base64Bytes() throws {
        let snapshot = try makeSnapshot("key = \"bWFnaWM=\"")

        #expect(
            try content(of: snapshot.value(forKey: key("key"), type: .bytes))
                == .bytes([0x6d, 0x61, 0x67, 0x69, 0x63])
        )
    }

    @Test("Decodes hexadecimal bytes with the hex decoder")
    func hexBytes() throws {
        let snapshot = try makeSnapshot(
            "key = \"6d61676963\"",
            parsingOptions: .init(bytesDecoder: .hex)
        )

        #expect(
            try content(of: snapshot.value(forKey: key("key"), type: .bytes))
                == .bytes([0x6d, 0x61, 0x67, 0x69, 0x63])
        )
    }

    @Test("Custom bytes decoder decodes string values")
    func customBytesDecoder() throws {
        struct FixedDecoder: ConfigBytesFromStringDecoder {
            func decode(_ value: String) -> [UInt8]? { [0xDE, 0xAD] }
        }

        let snapshot = try makeSnapshot(
            "key = \"ignored\"",
            parsingOptions: .init(bytesDecoder: FixedDecoder())
        )

        #expect(try content(of: snapshot.value(forKey: key("key"), type: .bytes)) == .bytes([0xDE, 0xAD]))
    }

    @Test("Bytes aren't read from non-string values")
    func bytesRequireStrings() throws {
        let snapshot = try makeSnapshot("key = 42")

        #expect(throws: TOMLSnapshot.Error.self) {
            _ = try snapshot.value(forKey: key("key"), type: .bytes)
        }
    }
}
