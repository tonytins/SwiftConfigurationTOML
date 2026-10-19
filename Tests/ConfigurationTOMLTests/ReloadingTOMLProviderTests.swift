import Configuration
import Foundation
import Testing

@testable import ConfigurationTOML

#if Reloading
    @Suite("ReloadingTOMLProvider Tests")
    struct ReloadingTOMLProviderTests {
        @Test("ReloadingTOMLProvider is a ReloadingFileProvider of TOML snapshots")
        func typealiasIsDefined() {
            #expect(ReloadingTOMLProvider.self == ReloadingFileProvider<TOMLSnapshot>.self)
        }
    }
#endif
