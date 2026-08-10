# ADR-0001: Single root SwiftPM package with custom target paths

Date: 2026-08-10 · Status: accepted

## Context

The build specification (§12.1) suggests a repository shape with `Packages/ReEditCore`,
`Packages/ReEditXML`, and `Tools/reedit-cli` as separate directories. SwiftPM offers two
ways to realise that: independent packages per directory wired together with local path
dependencies, or a single root `Package.swift` whose targets point at those directories
via custom `path:` settings.

Phase 0 is developed on a Linux container without a local Swift toolchain; every
verification round-trips through CI. Anything that multiplies build/resolve steps
multiplies CI latency and failure modes.

## Decision

One root `Package.swift` with three library/executable targets and three test targets,
using custom `path:`s that preserve the spec's directory layout. Shared fixtures live at
`Tests/Fixtures` and are located by tests relative to the repository root.

## Consequences

- One `swift build` / one `swift test` covers everything; CI stays a two-command job.
- No local path-dependency resolution graph to maintain.
- The directory layout still matches the spec, so splitting into real standalone
  packages later (e.g. when Apps/ReEditMac needs ReEditCore alone) is a mechanical
  change confined to manifests.
- Targets remain strictly layered (reedit-cli → ReEditXML → ReEditCore) via target
  dependencies, so the architecture boundary the multi-package layout would have
  enforced is still enforced.
