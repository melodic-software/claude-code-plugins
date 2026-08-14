# Tracked citation shape

This document owns the citation shape that `knowledge` skills use whenever a TRACKED output
refers to fetched external content. The rule it serves: **tracked outputs cite, never copy** —
the verbatim snapshot stays in the untracked work slice; only the citation crosses into anything
committed.

Any `knowledge` skill adopting the cite-never-copy rule conforms to this shape for the
citations it emits into tracked outputs. One shipped emitter predates this contract and does
not yet conform: `youtube-digest`'s staged `research/sources.md` records URLs without retrieval
dates or hashes — a known, not-yet-migrated exception; migrating it is a separate decision, not
implied by this document. Skill-internal hashes (node span hashes, slug hashes) remain owned by
their skill's own format docs; this document owns only the citation that leaves the slice.

## Shape

A citation names exactly three facts, none optional:

1. **URL** — the canonical fetched URL, after the emitting skill's URL normalization. Cite the
   channel actually fetched (e.g. a site's raw-markdown channel, a raw file URL), not a prettier
   equivalent that serves different bytes.
2. **Retrieval date** — ISO 8601 calendar date (UTC) of the fetch that produced the snapshot,
   e.g. `2026-08-14`.
3. **Content hash** — `sha256:<hex64>` over the raw snapshot bytes exactly as fetched, before
   any decoding, normalization, or extraction.

### Inline form (prose)

> `<URL>` (retrieved `<YYYY-MM-DD>`, `sha256:<hex64>`)

### Structured form (JSON/YAML artifacts)

```json
{
  "url": "https://example.org/page.md",
  "retrieved": "2026-08-14",
  "sha256": "<hex64>"
}
```

Field names `url`, `retrieved`, `sha256` are fixed. The hash value matches the emitting skill's
snapshot-level hash (`snapshot_sha256` in map-corpus inventories and queues) so a citation is
checkable against its slice without re-fetching.

## Sub-resource anchors (optional extension)

A citation MAY narrow to a region of the resource with the emitting skill's deterministic node
id (e.g. map-corpus `n0007-05b0396b`, whose trailing 8 hex are the first 8 of the node's span
hash). Serialization is fixed so independent emitters converge:

- **Inline form** — a fourth comma-separated element inside the parentheses, keyword `node`:

  > `<URL>` (retrieved `<YYYY-MM-DD>`, `sha256:<hex64>`, node `<node-id>`)

- **Structured form** — an optional `node` field beside the three required fields:

  ```json
  { "url": "…", "retrieved": "…", "sha256": "…", "node": "n0007-05b0396b" }
  ```

Never a URL fragment — `<URL>#<node-id>` would corrupt the `url` field's identity (fragments
are dropped by the canonical-URL rule) and suggest the anchor resolves in a browser, which it
does not. The anchor never replaces the three required facts; a reader with only the base
citation can still verify the whole resource. Node-id semantics stay owned by the emitting
skill's manifest format doc.

## Drift

A citation asserts what WAS fetched, not what the URL serves now. On re-fetch, a differing hash
means upstream drift: record the new fetch as a new citation (new date, new hash) and note the
drift; never edit the old citation's hash in place and never silently re-snapshot over the slice
the old citation points into.

## Non-goals

- Not a bibliography or attribution format — licensing attribution follows the source's license
  terms separately.
- Not an archival guarantee — the snapshot bytes live in an untracked slice on the machine that
  fetched them; the hash makes any surviving copy verifiable, it does not promise one survives.
