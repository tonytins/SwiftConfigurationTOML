# AGENTS.md

SwiftConfigurationTOML is a pure Swift TOML parsing and serialization library. It was developed as a drop-in replacement for [`swift-configuration-toml`](https://github.com/mattt/swift-configuration-toml) to avoid issues with CTomlPlusPlus.

## Repository Layout

```text
Sources/  Library source code
Tests/    Swift Testing unit tests
Package.swift
README.md
```

## Golden Rules

### Never crash
Malformed TOML, invalid inputs, missing files, permission issues, and I/O failures must produce actionable errors - never trap or abort. Treat all external inputs (TOML text, file paths, filesystem access) as untrusted.

- Avoid force unwraps (`!`), `try!`, forced casts, implicitly unwrapped optionals, `fatalError`, `precondition`, and `assert`-based control flow. Validate assumptions and throw typed errors.
- Validate inputs before use: check syntax, types, ranges, and file accessibility. Don't silently substitute defaults for invalid data.
- Check file I/O operations and propagate errors with context.
- Fix crash paths before building new features. For each crash or invalid-input fix, add a focused regression test.
- Keep failures isolated - never leave partial state.

## Code & Tests

- Follow existing Swift conventions in the codebase. Prefer small, clear functions, explicit validation, and typed errors.
- Use Swift Testing (`import Testing`, `@Test`). Cover successful parsing/serialization, round-trips, and important error cases (malformed TOML, missing files, etc.).
- Add comments only when they clarify non-obvious invariants or public contracts. Document public APIs where intended for reuse.
- Keep `README.md` accurate if API, behavior, or usage changes.
- Don't add application payloads, credentials, or build artifacts to the repo.

## Build & Validation

Run for changes:
```sh
swift test
swift build -c release
```

Before finishing:
- Run `git diff --check`
- Review the complete diff
- Report the commands that passed and any blocked checks

## Compatibility

Preserve compatibility with the drop-in replacement intent where it makes sense. Don't break existing public APIs without good reason - if you do, document it in the README.