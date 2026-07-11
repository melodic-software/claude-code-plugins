# Flavor vs content matrix

Canonical FLAVOR / CONTENT taxonomy for the `/compress` semantic-diff pass, plus per-content-type variants tuning expected yield and revert-pass focus.

## Canonical taxonomy

### Flavor (safe to cut)

- Articles (a/an/the)
- Filler (just/really/basically/actually/simply)
- Hedging (perhaps/somewhat/might)
- Pleasantries
- Redundant restatement of bold rule names
- "in order to" / "due to the fact that" verbose forms
- Conversational connectives ("that said", "in other words")
- Verbose verb phrases ("make use of" → "use")

### Content (NEVER cut)

- (a) every directive, including imperative force — "must have" ≠ "has"
- (b) every concrete prohibited-pattern example with a literal token
- (c) every counter-example / anti-example — both halves of "X not Y" pairs
- (d) every qualifier narrowing scope (ONLY, repeatedly, instantly recognized, that appear in)
- (e) every rule-unique "why" rationale — if removing it lets two readers infer different applicability, keep it
- (f) every cross-reference, file path, env var, SHA, version pin, identifier, slash command, hook name, agent name
- (g) every exception clause + example
- (h) every threshold (3+, 5+, ≥30s, <2min)
- (i) every enumeration item
- (j) every inline-code token

## Per-content-type variants

The taxonomy is invariant across content types. What varies is the EXPECTED YIELD and the RISK PROFILE for which (a)–(j) Content items are most often at stake. Variants below tune the revert-pass strictness and the audit-action expected-yield estimate per `context/target-types.md`.

| Content type | Expected yield | At-risk content items (per (a)–(j) above) | Variant guidance |
|---|---|---|---|
| **Always-loaded instruction file** (`.claude/rules/**`, `AGENTS.md`, `CLAUDE.md`, `**/SKILL.md`) | 2-3% | (a) directives, (d) scope qualifiers, (e) rule-unique rationale, (f) cross-references | Author-time-disciplined. Default action will revert per SKILL.md "Hard rules" (<3% AND 0SL → REVERT). `--force` only when a targeted sub-3% diff is intentional. Empirical baseline: 3/3 attempts reverted |
| **Onboarding doc** (README onboarding, `docs/onboarding-*.md`, contributor guides) | 8-15% | (b) prohibited-pattern tokens, (c) counter-examples, (h) thresholds | Verbose-prose baseline. Hedging + pleasantries dense; restatement of policy across sections common. Revert-pass strictness: keep every "X not Y" pair intact (counter-example loss = ambiguity in onboarding) |
| **README** (`README.md`, `*/README.md` at app/lib/service roots) | 5-12% | (f) cross-references, (g) exception clauses, (j) inline-code tokens | Project-front-door surface. Inline-code density usually high (commands, paths); revert any (j) drop. Cross-references load-bearing for navigation |
| **Drifted skill body** (`**/SKILL.md` past ~250 lines AND not author-time-disciplined) | 4-7% | (a) directives, (e) rule-unique rationale, (i) enumeration items | Skill bodies tend to accumulate procedural prose during evolution. Revert any directive softening ("must" → "should"); revert any enumeration-item drop. Often a single revert-pass produces a final ship |
| **Third-party pasted prose** (vendor docs, external policy text, copied research notes) | 10-20% | (b) prohibited-pattern tokens, (h) thresholds, (j) inline-code tokens | Highest yield + highest risk. Pasted prose carries verbose flavor authors did not edit. Inline-code tokens (CLI flags, schema field names) MUST survive verbatim; treat any (j) loss as SEMANTIC LOSS not AMBIGUITY |

## Variants never relax the preservation contract

The (a)–(j) Content list defines the universal preservation contract. Per-content-type framing only changes which list items fire most often and at what yield — it never implies per-type CONTENT relaxation, which is forbidden: every (a)–(j) item is preserved on every content type. The variant table above tunes EXPECTED YIELD + revert-pass FOCUS, never the preservation contract.

## Audit-action expected-yield mapping

`/compress audit <target>` classifies SKIP / COMPRESS / UNCERTAIN per `context/target-types.md` "Author-time-signal heuristic". The "Expected yield" column above feeds that heuristic's output:

- Expected yield < 3% (always-loaded instruction files) → audit emits **SKIP** with empirical-baseline citation
- Expected yield 3-7% (drifted skill bodies) → audit emits **UNCERTAIN**; user gates via `--force` or skip
- Expected yield ≥ 8% (onboarding / README / third-party) → audit emits **COMPRESS**

Numeric ranges drift; revisit the variant table as empirical evidence accumulates.

## Cross-references

- `../SKILL.md` "Auto-detect default" + "Hard rules" — default action revert rules consuming this variant table
- `context/target-types.md` — heuristic that feeds the audit-action SKIP/COMPRESS/UNCERTAIN classification
- `context/semantic-diff-prompt.md` — dispatch template that operationalizes the preservation contract
