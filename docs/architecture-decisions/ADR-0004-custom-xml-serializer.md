# ADR-0004: Parse with Foundation XMLDocument, serialize with our own writer

Date: 2026-08-10 · Status: accepted (amended after first cross-platform CI run)

## Context

The spec (§6.2) requires preserving unknown elements, attributes, ordering and the
source FCPXML version by retaining the source DOM. Development and one CI job run on
Linux, where `XMLDocument` comes from swift-corelibs-foundation's FoundationXML; the
product ships against Darwin Foundation. Byte-level fidelity of a no-op roundtrip is
the strongest cheap signal that nothing changed, so serialization must be identical
on both platforms.

The first cross-platform CI run (run 5) established two facts empirically:

1. **Darwin Foundation drops whitespace-only text nodes** during parsing even with
   `.nodePreserveWhitespace`; Linux FoundationXML keeps them. A writer that trusts
   the DOM for formatting can never be byte-stable across platforms.
2. **Linux FoundationXML silently recovers malformed XML** (libxml2 recovery mode)
   where Darwin throws, so `XMLDocument` cannot be the well-formedness authority.

## Decision

- **Well-formedness** is decided by a strict SAX parse (`XMLParser`, external
  entities never resolved) before any DOM work — strict on both platforms.
- **Parsing** then uses `XMLDocument(options: [.nodePreserveWhitespace])`, giving a
  retained DOM with document-order attributes and comments.
- **Serialization** never calls `xmlData`. `FCPXMLWriter` walks the DOM and **owns
  formatting entirely**: whitespace-only text nodes are ignored, and the writer
  emits Final Cut's canonical style itself — four-space indentation, one element
  per line, childless elements self-closed, attributes in document order, FCP-style
  escaping (numeric references for newline/tab/CR in attribute values). Elements
  containing significant text (mixed content such as `<text>`) emit children inline
  with no injected whitespace, because whitespace there is meaning.
- The XML declaration and DOCTYPE are re-emitted from a **raw-byte prolog scan**
  recorded at load time, never from the DOM, so FoundationXML's DTD handling is out
  of the fidelity path entirely.

## Comparison tiers

- **Tier 1 — byte identity**: writer output equals source bytes. Holds exactly when
  the source is already in canonical style — true for all synthetic fixtures
  (authored canonically) and for normal Final Cut exports (four-space indented).
  CI gates on this for fixtures on both platforms.
- **Tier 2 — canonical identity**: output re-parses to the same semantic form
  (attributes sorted, whitespace-only text and comments dropped). Must always hold;
  it is the gate for real-world files whose formatting differs from canonical.

## Consequences

- Output bytes are identical on Linux and macOS by construction — formatting comes
  from ~30 lines of writer code, not from either platform's DOM behaviour.
- Golden files are platform-stable; a one-byte drift fails CI.
- A source with non-canonical formatting (unusual indentation, blank lines)
  re-emits in canonical form: byte tier reports the difference, canonical tier
  proves meaning survived. Known, intended behaviour with a dedicated test.
- Inter-element whitespace inside mixed content that Darwin's parser drops cannot
  be reproduced anywhere; Final Cut derives titles from `text-style` runs, not
  inter-run whitespace, so this is cosmetic. The Final Cut import gate (spec §6.1)
  remains the semantic authority.
- Stop condition (spec §11.2): if real-export fidelity proves unacceptable at the
  Final Cut import gate, the fallback is a minimal hand-rolled preservation parser —
  an architecture change requiring explicit sign-off before any work.
