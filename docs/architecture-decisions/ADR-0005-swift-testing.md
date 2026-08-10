# ADR-0005: Swift Testing as the test framework

Date: 2026-08-10 · Status: accepted

## Context

The spec (§10.1) demands exhaustive unit coverage for FCPTime and golden-file
coverage for the XML engine. Swift 6 toolchains bundle Swift Testing (`import
Testing`) alongside XCTest on both macOS and Linux.

## Decision

Swift Testing for all test targets. Its parameterized `@Test(arguments:)` runs each
table row as an independently reported case — exactly the shape of the FCPTime
parse/arithmetic/comparison tables — and `#expect(throws:)` matches the typed
`FCPTimeError` cases directly.

## Consequences

- No third-party dependency; ships with the toolchain on both CI platforms.
- Table rows fail individually with their inputs in the report, which matters when a
  60-case parse table has one bad row.
- XCTest remains available if a future need (performance tests, UI tests in app
  phases) requires it; the two coexist in one package.
