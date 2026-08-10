# ADR-0003: Pure-Swift SHA-256 instead of CryptoKit or swift-crypto

Date: 2026-08-10 · Status: accepted

## Context

The spec (§4.2, §6.3) uses SHA-256 fingerprints for source XML, proxies, generated
revisions and stableID derivation. CryptoKit does not exist on Linux, where CI and the
current development environment run. The alternatives were apple/swift-crypto (Apple's
own open-source CryptoKit-compatible package) or a minimal local implementation.

These fingerprints establish identity and detect accidental divergence. They are not a
security boundary: no signatures, no secrets, no adversarial inputs.

## Decision

A ~150-line pure-Swift FIPS 180-4 implementation in ReEditCore, verified against NIST
test vectors on every platform and cross-checked against CryptoKit in a Darwin-only
test. The spec's default (§12.2) is no third-party dependencies unless Apple
frameworks are clearly insufficient; for non-security hashing, the standard library
plus 150 audited lines is sufficient, and it keeps `swift build` dependency-free and
identical on Linux and macOS.

## Consequences

- Zero SPM dependency resolution in CI; no version drift.
- If a later phase needs real cryptography (signed sync payloads, keychain-adjacent
  work), adopt apple/swift-crypto then and delete this file — the API surface
  (`SHA256.hexDigest`) is one call site wide.
- Performance is adequate for Phase 0 workloads (megabyte-scale XML); revisit only if
  profiling of full proxy fingerprinting demands it.
