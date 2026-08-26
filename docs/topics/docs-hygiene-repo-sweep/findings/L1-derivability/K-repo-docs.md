# L1-derivability — `K-repo-docs`

89 files. `docs/` root, `docs/adr`, `docs/conventions`, `docs/specs`, `docs/upstream`. All
human-facing, so the deletion bar is the higher one.

| Verdict | Count |
|---|---:|
| `keep-owns-facts` | 86 |
| `keep-as-derivation-cache` | 3 |

No deletions, no pointer conversions.

Roll-up for the 86 `keep-owns-facts`: seventeen ADRs (decisions plus rejected alternatives, the
Factor 4 trump card by definition), thirty-five convention documents and their CHANGELOGs
(cross-cutting contracts no single file states), five upstream ledgers (external-source provenance
and drift-recheck triggers), and the specs. `docs/PLUGIN-PHILOSOPHY.md` (95 KB) and
`docs/MIGRATION-PLAYBOOK.md` (141 KB) are the repo's governing doctrine and own it outright.

Three files in this group deserve their reasoning recorded because a careless pass would misjudge
them in either direction.

## `docs/CATALOG.md` — verdict: `keep-as-derivation-cache` [audience: human]

| Factor | Reading |
|--------|---------|
| Derivable? | yes, fully — it is generated from the plugin manifests |
| Re-derivation cost | expensive for a human reader (54 plugin manifests plus the taxonomy), trivial for the generator |
| Drift risk | low, because CI holds it in sync |
| Fact ownership | none inside the generated block; the category vocabulary is owned by `docs/CATALOG-TAXONOMY.md` |

Cache drift-control, quoted from `docs/CATALOG.md:3-5`:

> the block between the markers below is generated from the plugin manifests and kept in sync by CI
> — never hand-edit it; the category vocabulary is owned by
> [`docs/CATALOG-TAXONOMY.md`](CATALOG-TAXONOMY.md).

Regeneration path: `scripts/generate-catalog.mjs`. Both a mechanical regeneration path and a CI
verification gate are present, which is more than the rubric's gate requires. No demotion.

## `docs/SKILL-CHEAT-SHEET.md` — verdict: `keep-as-derivation-cache` [audience: human]

Same shape. `docs/SKILL-CHEAT-SHEET.md:3-5`:

> generated from each skill's SKILL.md frontmatter by `scripts/generate-cheatsheet.mjs`. Do not
> hand-edit the generated block below — edit the source frontmatter and regenerate.

Derivable from frontmatter; expensive for a human to re-derive across 237 `SKILL.md` files; drift
controlled by the named generator plus `scripts/generate-cheatsheet.test.sh`. The grouping axis
(sequence of use) is an authored editorial decision recorded above the generated block, which is a
small owned fact riding on a cache. No demotion.

## `docs/NATIVE-SURFACES.md` — verdict: `keep-as-derivation-cache` [audience: human]

`docs/NATIVE-SURFACES.md:3-7`:

> Generated view over the native-overlap store. The block between the markers below is rendered from
> `docs/native-surfaces/records.json` by
> `plugins/claude-ops/skills/audit-native-overlap/scripts/overlap.py generate` and kept in sync by
> CI — **never hand-edit it**. Verdicts, evidence, and recheck triggers are edited in the store;
> this file is output.

The document names its own store, its own renderer, and its own sync gate, and explicitly says the
owned facts live in the store rather than here. Textbook cache with drift control.

## Two near-misses recorded so they are not re-litigated

**`docs/conventions/consumer-config-layering/README.md` (701 bytes) is `keep-owns-facts`, not a
delete.** It reads as a dead stub, and it is not. Lines 8-11:

> This stub is a **compatibility tombstone**: earlier cached `code-tidying` (≤0.7.1) and `testing`
> (≤0.3.1) plugin copies still fetch the old path, so it is preserved to avoid a 404 until those
> installs update. New references must point at `config-cascade`; this file may be removed once the
> old plugin versions are no longer in circulation.

It owns an external fact (which shipped plugin versions still fetch this raw URL) and carries its
own removal condition, which is a recorded recheck trigger. Deleting it breaks live installs.

**`docs/hook-migration-audit.md` is `keep-owns-facts`, not a stale snapshot to drop.** It audits a
*different repository* (`melodic-software/medley`) on a stamped date, so nothing in this repo can
re-derive it, and it states its own decay rule at line 5:

> This is an **audit snapshot**, not durable policy — the [migration playbook](MIGRATION-PLAYBOOK.md)
> is the policy; this table records each candidate's gate compliance on the audit date and which
> follow-up issue owns each accepted migration. Empirical claims decay: a row is only true as of the
> stamp below.

`docs/extensibility-contract-smoke-tests.md` and `docs/formatter-path-probes.md` keep for the same
reason: dated empirical results against an external platform, with re-verification instructions in
the document.

## Cross-lane observations

- L2-progressive-disclosure: `docs/MIGRATION-PLAYBOOK.md` (141 KB), `docs/PLUGIN-PHILOSOPHY.md`
  (95 KB), `docs/conventions/detector-findings/README.md` (85 KB), and
  `docs/conventions/loop-lane/README.md` (60 KB) are the four largest single documents in the
  corpus.
