# ReEdit AI

An AI revision system for completed Final Cut Pro edits. An editor exports an FCPXML
project and a compressed review video, reviews the video on iPhone with time-bound
notes, and the Mac application generates a safe, revised FCPXML project. Final Cut Pro
remains responsible for media management, final rendering, and the authoritative
timeline.

**Delivery strategy: local first, original safe, deterministic before semantic.**

The full product requirements live in [`docs/product-spec.md`](docs/product-spec.md).
Architecture decisions are recorded in
[`docs/architecture-decisions/`](docs/architecture-decisions/).

## Current status: Phase 0 — feasibility harness

Per the build specification, work proceeds one phase at a time. This repository
currently contains **Phase 0 only**: exact rational time arithmetic, FCPXML
loading/inspection, a normalised read-only timeline graph, and a no-op roundtrip.
There are **no edit commands, no SwiftUI apps, no sync, and no AI integration yet** —
those are later phases, gated on Phase 0 acceptance.

Phase 0's critical gate: an untouched FCPXML export must reimport into Final Cut Pro
with acceptable fidelity on representative real projects before anything else is built.

## Layout

```
Packages/ReEditCore     Domain models, exact rational time (FCPTime), shared utilities
Packages/ReEditXML      FCPXML loading, DOM preservation, timeline graph, roundtrip
Tools/reedit-cli        Phase 0 command line harness (the `reedit` executable)
Tests/Fixtures          Synthetic FCPXML fixtures (valid and invalid)
Tests/GoldenFiles       Golden outputs for roundtrip, graph, and inspect
Scripts                 Fixture verification used by CI
docs                    Product spec, conventions, architecture decision records
```

One root `Package.swift` builds everything (see ADR-0001).

## Building and testing

Requires a Swift 6 toolchain (macOS 14+ with Xcode 16, or Swift 6.1 on Linux).

```sh
swift build
swift test
swift run reedit inspect Tests/Fixtures/valid/f01-simple-25fps.fcpxml
```

CI runs both a Linux job (`swift:6.1` container — FoundationXML code path) and a
macOS job (Darwin Foundation + CoreMedia code path). Both must pass.

## CLI (Phase 0 contract)

```
reedit inspect   <input.fcpxml|input.fcpxmld>
reedit validate  <input>
reedit roundtrip <input> --output <path>
reedit graph     <input> --json <path>
```

Exit codes: `0` success · `1` validation findings / fidelity failure · `2` usage
error · `3` load/parse error · `4` internal error.

## Safety principles (non-negotiable, from the spec)

- Never edit a Final Cut library bundle directly.
- Never overwrite an imported XML, review proxy, or original Final Cut project.
- Exact rational time arithmetic only — no floating point in edit logic.
- Preserve unknown XML elements, attributes, and the source FCPXML version.
- Unknown constructs default to read-only and are reported, never silently altered.

## Phase 0 exit gate (manual, on a Mac with Final Cut Pro)

CI proves the harness against synthetic fixtures. Closing Phase 0 additionally
requires, on real projects:

1. In Final Cut Pro, duplicate a completed project and export it as FCPXML.
2. Run `reedit roundtrip export.fcpxml --output roundtrip.fcpxml` and confirm the
   fidelity report.
3. Import `roundtrip.fcpxml` into a **disposable** Final Cut event.
4. Confirm: no import warnings, no version change, no media relink prompts, and no
   visible timeline/title/audio/effect differences in the supported subset. Check
   titles especially closely — macOS XML parsing cannot preserve whitespace-only
   styled runs (ADR-0004), so multi-run titles are the most likely place for
   fidelity loss to show.
5. Repeat for at least three representative projects (simple, normal wedding
   highlight with connected clips, intentionally complex with compound/multicam).

If fidelity is unacceptable, stop and catalogue the failure before building further
(spec §6.1 and §11.2).
