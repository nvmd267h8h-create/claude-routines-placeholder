# ADR-0002: Hand-rolled CLI argument parsing

Date: 2026-08-10 · Status: accepted

## Context

The Phase 0 CLI has four subcommands (`inspect`, `validate`, `roundtrip`, `graph`)
with one positional argument each and at most one valued option. The obvious
dependency would be apple/swift-argument-parser.

## Decision

Parse by hand (~100 lines with typed errors and usage text). The spec's default
(§12.2) is no third-party dependencies unless the standard library is clearly
insufficient; for this surface it is not. Avoiding the dependency also removes SPM
network resolution as a CI failure mode — relevant here because every verification
runs through CI.

## Consequences

- Zero dependencies; instant builds; typed `ArgumentParseError` matches the exit
  code contract (usage errors exit 2).
- If Phase 1 grows the surface (plan/apply/diff with multiple options each),
  revisit swift-argument-parser in a new ADR; the parsing seam (`CLIArguments.parse`
  returning `ParsedCommand`) keeps that swap local.
