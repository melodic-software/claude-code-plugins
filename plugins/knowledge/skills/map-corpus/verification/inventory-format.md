# Node inventory format (`node-inventory/v1`)

Owner doc for the per-resource inventory the corpus mapper emits and `check_inventory.py` gates.
The inventory is where agent judgment lives (relevance verdicts); this format exists so that
judgment is *checkable*: every verdict is pinned to a node the deterministic manifest defines and
to a byte-exact quote the gate can confirm.

**Verdict coverage is the completeness invariant** (this replaces `docpage-digest`'s digest-unit
parity, which is false by design under tiering): every manifest node has exactly one inventory
row, and every row carries a verdict, a rationale, and an evidence token. The gate enforces
exactly that. A "clean" gate run covers only the rows and fields it names in its own output.

## Inventory shape

```json
{
  "schema": "node-inventory/v1",
  "snapshot_sha256": "<hex64 — must equal the manifest's snapshot.sha256>",
  "rows": [
    {
      "node_id": "n0002-e6dcf3a7",
      "verdict": "relevant",
      "rationale": "Names the verification-loop pattern the mapper composes.",
      "evidence": {
        "quote": "Give Claude a way to verify its work",
        "start_byte": 2205,
        "end_byte": 2241
      }
    }
  ]
}
```

Serialization for emitters: JSON, UTF-8. The gate accepts any valid JSON spelling (it parses, it
does not diff bytes), but rejects unknown keys — a misspelled field must fail loudly, never be
silently ignored — and rejects duplicate JSON keys at any depth: `json` parsers are last-wins on
duplicates, so a duplicated field would let unvalidated bytes ride under a validated name.
Emitters must never emit a duplicate key.

## Field contract

- `schema` — literal `node-inventory/v1`.
- `snapshot_sha256` — SHA-256 of the snapshot the verdicts were formed against. The gate refuses
  a manifest/inventory pair whose hashes disagree: verdicts about other bytes are not verdicts
  about this resource.
- `rows` — exactly one row per manifest node, any order. Missing node → fail (unrepresented
  content). Unknown `node_id` → fail (verdict about nothing). Duplicate `node_id` → fail
  (ambiguous verdict).
- `verdict` — `relevant` | `not-relevant` | `uncertain`. `relevant` feeds the approved queue;
  `uncertain` routes to the interview, never silently either way. Any other value fails loudly.
- `rationale` — non-empty string; one or two sentences of why. The gate checks presence, not
  quality — quality is the fresh-eyes verifier's lane.
- `evidence` — the proof-of-reading token:
  - `quote` — non-empty string, verbatim from the snapshot.
  - `start_byte` / `end_byte` — the quote's exact span in RAW SNAPSHOT bytes (end exclusive).

## Evidence-token byte mapping

The manifest is byte-addressed; quotes are text. The mapping rule:

1. UTF-8-encode `quote`; the encoded bytes MUST equal `snapshot[start_byte:end_byte]` exactly —
   no normalization, no whitespace forgiveness. (Snapshots are UTF-8 by the extractor's encoding
   contract, so this is well-defined.)
2. The span MUST lie inside the claimed node:
   `node.start_byte <= start_byte < end_byte <= node.end_byte`.
   - **Multi-occurrence** is resolved by the explicit offsets: the row commits to one occurrence,
     the gate checks that occurrence. A quote appearing elsewhere too is irrelevant.
   - **Node-straddling is forbidden.** A span crossing a node boundary fails containment. Quote
     within one node; a claim genuinely about two nodes belongs in both rows' rationales with a
     per-node quote each.
3. Emitters that locate a quote by search must search only within the claimed node's span and
   then record the found offsets — never offsets computed from decoded-text indexes (char != byte
   for non-ASCII).

## Single-node resources

Opaque formats (JSON schemas, licenses, PDF text extractions) and outline-less pages legitimately
yield a one-node manifest and therefore a one-row inventory: one whole-resource verdict with one
quote. `node_count == 1` is normal, not suspicious.

## Gate contract (`check_inventory.py`)

Inputs: manifest path, inventory path, snapshot path. Checks, in order:

1. Both JSON files parse; failure exits 2 naming the file and the parse error.
2. Schema strict: required fields present, types right, enums valid, unknown keys rejected —
   each failure names the offending row by `node_id` (or index when the id itself is missing).
3. Manifest is re-verified against the snapshot (partition contiguity, whole-file and per-node
   hashes) — the gate does not trust that the manifest on disk still matches the snapshot.
4. Coverage: exactly-one-row-per-node diff, both directions, by `node_id`.
5. Evidence: byte-exact quote match and node containment per the mapping rule above.

Exit codes: 0 all checks passed; 1 one or more named check failures; 2 unusable input
(parse/IO/schema-literal errors); 3 internal invariant violation. A clean run prints what it
exercised (file names, row count, node count, field list) — silence is never a pass, and a pass
covers only what was printed. The gate was written and tested to fail loudly on unparsable and
malformed input BEFORE being made a required artifact (two prior gates in this codebase shipped
fail-open and were caught by verifiers).
