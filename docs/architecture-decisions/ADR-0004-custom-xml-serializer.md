# ADR-0004: Parse with Foundation XMLDocument, serialize with our own writer

Date: 2026-08-10 · Status: accepted

## Context

The spec (§6.2) requires preserving unknown elements, attributes, ordering and the
source FCPXML version by retaining the source DOM. Development and one CI job run on
Linux, where `XMLDocument` comes from swift-corelibs-foundation's FoundationXML; the
product ships against Darwin Foundation. The two implementations do not guarantee
identical serialization output (`xmlData`): declaration details, DOCTYPE emission,
empty-element style and escaping can differ, which would make byte-level golden tests
platform-dependent — and byte-level fidelity is the strongest cheap signal that a
no-op roundtrip changed nothing.

A second, sharper problem: FoundationXML does not reliably surface the `<!DOCTYPE
fcpxml>` prolog as a DOM node, so a DOM-only serializer can silently drop it.

## Decision

- **Parsing** uses `XMLDocument(options: [.nodePreserveWhitespace])` on both
  platforms (libxml2-backed on both), giving us a retained DOM with document-order
  attributes, comments and whitespace text nodes.
- **Serialization** never calls `xmlData`. `FCPXMLWriter` walks the DOM and emits
  bytes deterministically: attributes in document order, FCP-style escaping (numeric
  references for newline/tab/CR in attribute values), whitespace-only text nodes
  verbatim, childless elements self-closed.
- The XML declaration and DOCTYPE are re-emitted from a **raw-byte prolog scan**
  recorded at load time, never from the DOM, so FoundationXML's DTD handling is out
  of the fidelity path entirely.

## Comparison tiers

- **Tier 1 — byte identity**: writer output equals source bytes. The CI gate for
  synthetic fixtures (authored in the writer's canonical style) on both platforms.
- **Tier 2 — canonical identity**: output re-parses to the same semantic form
  (attributes sorted, whitespace-only text and comments dropped). The gate for
  real-world Final Cut exports, where stylistic byte drift (quoting, spacing) is
  tolerable but semantic drift is not.

## Consequences

- Golden files are platform-stable and byte-comparable; a one-byte drift fails CI.
- The writer is ~100 lines we own and test directly (escaping tables, self-closing
  rules) instead of undocumented Foundation behaviour we don't.
- If a real FCP export uses a construct the writer does not re-emit byte-exactly
  (unusual quoting, CDATA), Tier 2 still protects semantics, and the byte diff makes
  the gap visible for a targeted fix.
- Stop condition (spec §11.2): if Linux parsing itself proves lossy (dropped
  comments/whitespace), the fallback is a minimal hand-rolled preservation parser —
  an architecture change requiring explicit sign-off before any work.
