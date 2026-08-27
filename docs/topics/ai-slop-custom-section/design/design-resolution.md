# Design resolution — ai-slop model-era custom additions

outcome: early-exit (Tier B, light design)

Reason: no new module, package, or type system — the change is a catalog content section,
one additive pattern rule in an existing flat registry, and a localized config-contract
tweak. The contract shapes were resolved and adversarially validated during
`/planning:audit-answers` (two fresh-context validators, full-corpus measurements; record
in `.work/ai-slop-custom-section/interview-checklist.md`).

## Contract sketch

New config keys in `.claude/ai-slop.json` (config-cascade, later layer wins):

```jsonc
{
  "phrase_add": ["that.s my honest take"],   // ERE fragments OR'd into the phrase rule
  "phrase_remove": ["honest take"]           // shipped phrase fragments filtered out
}
```

- Values are ERE alternation fragments (documented contract: apostrophes written as `.`,
  metacharacters are the author's responsibility — same convention as the shipped
  PATTERN_RULES phrase lists).
- Read via a separator-preserving jq reader (`join("|")`-style / `@tsv` precedent at
  detect.sh:249-253), never `cfg_array` (space-joins, destroys multiword phrases).
- Shipped phrases move from an inline ERE to a `MODEL_PHRASES` bash array so
  `phrase_remove` can filter per-phrase; joined at runtime into a `__PHRASES__`
  placeholder substitution (the `__VOCAB__` precedent, detect.sh:94,636).

New rule: `rule-model-era-phrases` — PATTERN_RULES entry, wording class (quotation
exemption applies), per-occurrence, severity-crosswalk row argued like its siblings.

Catalog: new H2 section "Model-era additions (repo-owned)" with per-entry fields
`detectability / applicability / v1 / era / models / attribution / evidence`, where
`evidence: locally-observed | community-attested | measured` gates placement
(locally-observed → `recorded-only` or rubric only), plus a dated model-era record block
(upstream-drift-record shape).

Prerequisite fix (validated defect): `rule_allowed()` passes `$globs` unquoted →
pathname expansion against the caller cwd; fix by `read -r -a` into an array before the
`matches_glob` call (read does not glob-expand), with a cwd-independence regression test.
