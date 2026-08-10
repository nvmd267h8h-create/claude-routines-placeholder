# ADR-0006: CI runs a blocking macOS job alongside Linux

Date: 2026-08-10 · Status: accepted

## Context

Development happens on Linux; the product ships on macOS. The two Foundation
implementations demonstrably diverge in exactly the areas Phase 0 depends on — the
first cross-platform run proved Darwin drops whitespace-only text nodes while Linux
recovers malformed XML (see ADR-0004) — and CMTime/CryptoKit code paths only compile
on Darwin.

## Decision

`.github/workflows/ci.yml` runs two blocking jobs on every push: `linux`
(`swift:6.1-noble` container — the FoundationXML path) and `macos` (`macos-15` —
Darwin Foundation, CoreMedia interop tests, CryptoKit SHA-256 cross-check). Both run
the full test suite plus the fixture verification script; both must pass.

## Consequences

- Platform divergence is caught per-push instead of at the user's Mac. Both
  divergences found so far were caught by exactly this pairing, each visible on only
  one platform.
- The macOS job is the only pre-user-Mac execution of the code paths the shipping
  product will actually use; treating it as advisory would leave the primary
  platform untested.
- CI minutes cost more for macOS runners; the suite is fast (seconds), so the spend
  is negligible against a broken-fidelity escape.
