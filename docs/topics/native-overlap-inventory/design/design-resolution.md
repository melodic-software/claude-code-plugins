# Design resolution — native-overlap-inventory

outcome: early-exit (Tier B)

Reason: the design threads a `/planning:design` pass would resolve were driven to resolution by
three adversarial validation rounds over the Brief (interview rounds 1–2, post-discovery
audit-answers) plus verified discovery artifacts — module boundary (claude-ops sibling skill,
forced by the cross-plugin import ban), data contracts (below), extension points (userConfig
paths, seeded-pairs data file), and testability (deterministic self-check + sibling tests per
house precedent). No open design thread remains; re-running design would re-derive settled
outcomes.

## Type sketch (contracts)

**Verdict/record store** — committed JSON (`docs/native-surfaces/records.json`), hand-editable
SSOT. Shape:

```json
{
  "schema": 1,
  "rows": [
    {
      "native": {"name": "code-review",
                  "class": "bundled-skill|builtin-command|plugin-backed-builtin|session-skill",
                  "markers": ["hidden"|"gated"]},
      "component": {"plugin": "review", "skill": "code-review", "kind": "skill|agent"},
      "verdict": "prefer-native|prefer-ours|complementary|superseded|defer",
      "reason": "…",
      "evidence": ["…"],
      "observation": {"class": "extraction|live-roster", "detail": "binary v2.1.232", "date": "YYYY-MM-DD"},
      "recheck": {"trigger": "<observable event>", "verified": "YYYY-MM-DD"},
      "baked": {"description_phrase": true|false, "boundary_section": true|false},
      "budget_caveat": true|false
    }
  ]
}
```

**Registry view** — `docs/NATIVE-SURFACES.md`, generated from the store, marker-fenced, per-source-
lane sections, never hand-edited; `--check` mode regenerates and diffs.

**Seeded candidate pairs** — `plugins/claude-ops/skills/audit-native-overlap/reference/canonical-pairs.json`
(candidates only, no verdicts): `{"schema":1,"pairs":[{"native":{name,class},"component":{plugin,skill,kind}}]}`.

**Self-check script** — Python 3.11+ stdlib-only (inventory.py precedent), exit 0 ok / 1 broken /
3 degraded (2 reserved for argparse usage errors; deviation from the shell gates' 0/1/2 documented
in the header). Deterministic scope only: store parse + schema assert, per-row trigger presence,
record well-formedness, store↔view drift (regenerate + diff), store↔baked-line parity
(direction-sensitive: baked ⊆ store), locally-decidable comparisons.

**Detection substrates** — native side: `inventory.py --out` JSON (consumer asserts `schema == 1`
and presence-checks `builtin_commands`, `bundled_skills`, `plugin_backed`, `integrity`; missing
key → broken).
Target side: the skill's own repo-tree scan of `plugins/*/skills/*/SKILL.md` +
`plugins/*/agents/*.md` frontmatter.
