# Phase 0 conventions

Reference for conventions the Phase 0 code and tests rely on. Change these only
with a failing test first (spec §12.2).

## Absolute time

Graph times (`TimelineNode.absoluteStart`) are **0-based timeline-local** rational
times: the first frame of the sequence is `0s` regardless of the project's timecode
start. The sequence `tcStart` is reported separately as `TimelineGraph.projectStart`;
consumers add the two when they need presentation timecode. The recursion is

```
absStart(child) = absStart(parent) + (child.offset − parent.start)
```

because a child's `offset` is expressed on its parent's local timeline, whose origin
sits at the parent's `start` (media in-point). The spine's children live on the
**sequence timeline, whose origin is `tcStart`** — Final Cut exports the first clip
of a 01:00:00:00 project at `offset="3600s"` — so spine children use `tcStart` as
the subtracted origin and come out 0-based.

## XML paths

`/fcpxml` for the root; every descendant element appends `name[i]` where `i` counts
same-named element siblings in document order:

```
/fcpxml/library[0]/event[0]/project[0]/sequence[0]/spine[0]/asset-clip[2]
```

Paths are deterministic on both platforms and identify nodes in errors, findings,
graph JSON and sidecar manifests.

## Canonical XML style (writer output)

- The whole prolog — XML declaration, comments, processing instructions and
  `<!DOCTYPE fcpxml>` (including an internal subset), plus a UTF-8 BOM if present —
  is re-emitted exactly as found by the raw-byte prolog scan (never invented,
  never dropped).
- Four-space indentation, one element per line.
- Childless elements self-close (`<gap .../>`).
- Attributes in document order, double-quoted.
- Text escaping: `& < >` and `&#13;` for CR. Attribute escaping additionally `"`
  and numeric references `&#10;` `&#9;`.
- Mixed content — `<text>` subtrees and any element with significant text — emits
  children inline with every text node preserved verbatim, including
  whitespace-only styled runs (they are title content, not formatting).
- Trailing newline matches the source.

Sources already in this style (all fixtures, normal Final Cut exports) roundtrip
byte-identically; anything else normalises to it and is covered by the canonical
comparison tier (ADR-0004).

## CLI exit codes

| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | Validation findings (error severity) or roundtrip fidelity failure |
| 2 | Usage error (unknown command, missing argument) |
| 3 | Load/parse error (any `FCPXMLLoadError`) |
| 4 | Internal error (a bug — never expected in normal operation) |

Human output goes to stdout; diagnostics and error descriptions go to stderr.

## Fixture naming

Fixture file IDs (`f01`…) are local to this repository and do not map 1:1 onto the
spec's §10.2 fixture table: `f06-bundle` covers `.fcpxmld` bundle input (part of the
spec's supported-input contract), while the spec's F06 (23.976/29.97 samples) and
F07 (compound/multicam) are **before-beta** gates that need real anonymised exports
from the user and are intentionally not represented yet.

## Golden files

- `*.roundtrip.golden.fcpxml` — byte-exact expected roundtrip output (equals the
  fixture for canonical-style fixtures). Compared byte-wise on both platforms.
- `*.inspect.golden.txt` — byte-exact CLI inspect text (deterministic rendering).
- `*.graph.golden.json` — decoded and compared **structurally** (JSON byte
  formatting differs between Foundation implementations).

## StableIDs

`stableID = hex(SHA256(sourceFingerprint ∥ 0x1F ∥ xmlPath ∥ 0x1F ∥ nodeFingerprint))[0..<32]`
where `nodeFingerprint = SHA256(elementName ∥ 0x1F ∥ name=value…)` over attributes
sorted by name. IDs live in graph JSON and `<output>.reedit-manifest.json` sidecars
only; production XML is never annotated (spec §6.3).
