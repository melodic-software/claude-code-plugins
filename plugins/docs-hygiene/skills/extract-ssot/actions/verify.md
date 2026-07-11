# `verify` action — pre-extraction gate

Cheap pre-extraction gate. Refuse-fast on candidates that wouldn't survive `plan`/`execute` anyway. Surfaces the refusal verdict from a single grep + citation check, without spawning a subagent.

Private surface — external consumers invoke `/extract-ssot verify <cluster>`, never cite this file directly (contract: `/encapsulation-audit`).

## When to invoke

| Use case | Invoke |
|----------|--------|
| `/extract-ssot identify` produced a ranked candidate list and you want to filter before planning | YES |
| User typed `/extract-ssot verify <cluster>` directly | YES |
| Pre-batch filter inside the `batch` action | YES — automatic |
| You already have HIGH confidence the cluster passes the 6+5 gate | OPTIONAL — `plan` will re-verify Tier 0 |
| Cluster has < 3 instances (Rule of Three obvious fail) | NO — refuse via `identify` instead |

`verify` is OPTIONAL. It does NOT gate `plan`/`execute` automatically — preserves user agency. Skipping `verify` and going straight to `plan` is supported.

## Inputs

```text
/extract-ssot verify <cluster-name>
```

`<cluster-name>` matches a candidate from a recent `/extract-ssot identify` output OR is a free-form descriptor of the cluster the user wants to gate.

## Output schema

```yaml
status: PROCEED | REFUSE-{reason} | WARN
reason-code: <see table below>
evidence:
  - <Tier 0 grep output snippet>
  - <Tier 0 grep output snippet>
blockers:
  - <one-line cause>
next-action: <one of the recommended next steps>
notes: <optional 1-line context>
```

Status values:

| Status | Meaning |
|--------|---------|
| `PROCEED` | All 6 gates pass; safe to invoke `/extract-ssot plan <cluster>` |
| `REFUSE-rule-of-three-fails` | < 3 verbatim instances after discriminating-phrase grep (Gate 1) |
| `REFUSE-already-cites-canonical` | All call sites already cite an existing canonical SSOT (Gate 2) |
| `REFUSE-primary-source-citation-gate` | Sites cite a vendor/RFC/spec URL directly; internal SSOT can't improve (Gate 3) |
| `REFUSE-source-of-truth-bifurcation` | Top-tier instruction file ↔ rule-file pair both canonical at different tiers; forcing a single citation = cycle (Gate 4) |
| `REFUSE-off-by-one-different-concern` | Surface-similar but different step counts / variant shapes signal distinct concerns (Gate 5) |
| `REFUSE-low-roi` | Single short stable claim; inline beats abstraction maintenance (Gate 6) |
| `WARN-borderline` | Gates pass but evidence is marginal (e.g. 3 instances exactly, or one gate flagged) — `plan` should include an adversarial-review round |
| `REFUSE-not-found` | Cluster name doesn't resolve to any matching content (no instances grepped) |

## The 6 gates (ordered checks)

Each gate has Tier 0 evidence requirements — direct grep/read output captured this turn per SKILL.md "Evidence discipline". For Gates 1–3 partial facts, run:

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/emit-verify-facts.sh" --phrase "<discriminating phrase>"
```

Map the script output to gate evidence; emit the `status: PROCEED | REFUSE-* | WARN` YAML in the skill — the script never emits verdicts.

### Gate 0: Cluster resolution

Before any gate runs, confirm the cluster exists in the repo.

- Step 1: identify a discriminating phrase from the cluster body (≥ 8 words, unique enough to grep cleanly)
- Step 2: grep for the phrase across the repo's tracked markdown
- Step 3: if zero hits → `REFUSE-not-found` immediately

### Gate 1: Rule-of-Three via discriminating-phrase grep

**Lesson 1** — keyword density over-counts; use discriminating-phrase grep instead.

- Identify a verbatim phrase that uniquely characterizes this cluster (NOT keywords like "subagent" or "rate limit" that appear everywhere)
- Multiline grep where appropriate (use `multiline: true` for cross-line patterns)
- Count distinct **full reproductions** (not paraphrase mentions, not 1-line teaching mentions, not citation-only references)
- If < 3 full reproductions → `REFUSE-rule-of-three-fails`

Tier 0 evidence form:

```text
Grep pattern: '<discriminating phrase ≥ 8 words>'
Files matched (full reproductions): <n>
  - <path>:<line>
  - <path>:<line>
  - <path>:<line>
Files matched (teaching mentions, excluded): <n>
  - <path>:<line> (1-line mention, kept inline)
```

### Gate 2: Pre-existing canonical citation check

**Lesson 2** — sites already citing canonical = no extraction work remains.

- For each call site found in Gate 1, grep the surrounding ~10 lines for an existing citation pattern: `per <some>.md "<heading>"` or backtick-`<some>.md` references
- Count call sites already citing canonical
- If ALL call sites already cite a canonical SSOT → `REFUSE-already-cites-canonical`
- If SOME do but not all → continue (the `execute` action would sweep stragglers); proceed to Gate 3

Tier 0 evidence form:

```text
Citation grep pattern: 'per [a-z-]+\.md \"'
Sites already citing canonical: <n> / <total>
Canonical file(s) referenced: <list>
```

### Gate 3: Primary-source citation gate

**Lesson 6** — sites citing a vendor doc / RFC / spec URL directly outrank any internal SSOT.

- For each call site, grep ~5 lines around it for primary-source URLs: `code.claude.com`, `platform.claude.com`, `anthropic.com`, `tools.ietf.org/rfc`, `developer.mozilla.org`, `learn.microsoft.com`, or whatever primary hosts the repo's domain relies on
- If ALL call sites cite a primary-source URL within ~5 lines → `REFUSE-primary-source-citation-gate`

Rationale: an internal SSOT cannot improve on a primary URL the consumer already inlines. Internal SSOT is for repeated *internal-vocabulary* claims, not re-statements of primary facts.

Tier 0 evidence form:

```text
Primary-URL grep pattern: '(code|platform)\.(claude|anthropic)\.com|tools\.ietf\.org/rfc|learn\.microsoft\.com'
Sites citing primary directly: <n> / <total>
Sample URL(s): <list>
```

### Gate 4: Source-of-truth bifurcation check

**Lesson 8** — a top-tier always-loaded instruction file as source + a rule-file aggregator are both first-class canonicals at different tiers.

Detect the bifurcation pattern:

- Did the cluster originate in `CLAUDE.md` or `AGENTS.md` (top-tier always-loaded)?
- Is the cluster ALSO present in a scoped rule file (deep-disclosure aggregator for hook/skill/script authors)?
- If both: forcing the instruction file to cite the rule = citation cycle. Each tier serves a different audience legitimately.

If bifurcation detected → `REFUSE-source-of-truth-bifurcation`. Document both canonicals + their respective audiences in the output `notes:` field.

Tier 0 evidence form:

```text
Top-tier source: <CLAUDE.md|AGENTS.md>:<line> "<section>"
Aggregator rule: <rule-file>.md:<line> "<heading>"
Audiences:
  Top-tier: <e.g. "every loaded session">
  Aggregator: <e.g. "hook authors / skill authors who Read the rule explicitly">
Forcing single citation would create: cycle (instruction file → rule → instruction file) | over-aggregation
```

### Gate 5: Off-by-one heuristic — different concerns

**Lesson 3** — different step counts / variant shapes signal distinct concerns.

- For multi-step or numbered-list clusters, compare step count across instances
- For decision-table clusters, compare row count + column structure
- For workflow chain prose, compare step names + ordering
- If counts/shapes diverge non-trivially across instances → these are NOT the same cluster; `REFUSE-off-by-one-different-concern`

Adjacent Lesson 4 — an intentional Path 1 / Path 2 bifurcation (two related but distinct lifecycles documented side by side) is the canonical example: 2 lifecycles, intentionally distinct, must NOT collapse.

Tier 0 evidence form:

```text
Instance shapes:
  - <path>: <step count> steps, named <list>
  - <path>: <step count> steps, named <list>
  - <path>: <step count> steps, named <list>
Divergence: <yes/no — describe>
```

### Gate 6: LOW-ROI threshold

**Lesson 5** — single-sentence + low-drift = inline beats abstraction-maintenance cost.

Two heuristics combined:

- **Size**: cluster body ≤ 1 short paragraph (≤ ~80 words OR single sentence)
- **Drift rate**: cluster content changes ≤ 1×/year (verifiable via `git log -p <files>` if needed)

If BOTH true → `REFUSE-low-roi`. Inline at each call site is the disciplined call; the abstraction's overhead would dominate.

Tier 0 evidence form:

```text
Cluster body size: ~<n> words
Drift signal: git log shows <n> edits to the cluster prose in last 12 months
ROI verdict: LOW (size + drift indicate inline is cheaper)
```

## Workflow

```text
1. Read your working notes (resume if mid-phase)
2. Gate 0 — cluster resolution
3. Gate 1 — discriminating-phrase grep, count full reproductions
4. Gate 2 — pre-existing citation check
5. Gate 3 — primary-source citation gate
6. Gate 4 — source-of-truth bifurcation check
7. Gate 5 — off-by-one shape divergence
8. Gate 6 — LOW-ROI threshold
9. Emit structured output (status + evidence + next-action)
10. Optionally append a dated verify entry to the working notes (audit trail)
```

If ANY gate REFUSES, stop and emit. Don't run remaining gates — output the first refusal reason. (Avoids overspecified output that obscures the actual blocker.)

If ALL gates pass, emit `PROCEED` with summary evidence. User runs `/extract-ssot plan <cluster>` next.

## Side observations

When a gate REFUSES with high confidence, the cluster may still warrant action — just not the action `/extract-ssot` provides. Emit ONE side observation per refusal:

| Refusal | Side observation form |
|---------|----------------------|
| `REFUSE-already-cites-canonical` | `Side note: cluster already extracted at <canonical>; no SSOT work remains. Sweep stragglers if any?` |
| `REFUSE-primary-source-citation-gate` | `Side note: <n> sites cite <primary URL>; internal SSOT redundant. Verify URL still resolves.` |
| `REFUSE-source-of-truth-bifurcation` | `Side note: bifurcated SSOT — document the two audiences in the rule file so the split reads as intentional.` |
| `REFUSE-low-roi` | `Side note: inline + cite primary if needed; surface to user only if drift starts.` |
| `REFUSE-off-by-one-different-concern` | `Side note: <n> distinct concerns; consider /extract-ssot identify with a narrower discriminating phrase per concern.` |

Hard limit ≤2 side notes per response. If multiple gates fire, batch the rest into the working-notes entry.

## Audit trail (optional)

When `verify` runs as part of `/extract-ssot batch`, it MUST append a verify audit entry to the batch working notes so the batch summary can aggregate verdicts. When run standalone, an audit entry is OPTIONAL but recommended for non-trivial clusters.

Entry format:

```markdown
---
type: verify-evidence
date: <ISO-8601 UTC, e.g. 2026-06-04T14:30:00Z>
cluster: <name>
verdict: <status>
---
## Cluster
<short description>

## Gate results
| Gate | Result | Evidence |
|------|--------|----------|
| 0 — Cluster resolution | PASS | <count> matches |
| 1 — Discriminating-phrase grep | <PASS|FAIL> | <evidence snippet> |
| 2 — Pre-existing citations | <PASS|FAIL> | <evidence> |
| ... | | |

## Verdict
<final status + reason>

## Side observations
<≤2 entries>
```

## Cross-references

- `context/decision-framework.md` "Pre-extraction Tier 0 checklist" — documents these 6 gates as the formalized pre-extraction discipline
- `context/lessons.md` — the empirical batch-derived patterns the gates encode
- `context/anti-patterns.md` — pattern #11 (source-of-truth bifurcation), #12 (primary-source citation gate), #13 (Shape C dedup-by-deletion, positive)
- SKILL.md "Evidence discipline" — Tier 0 evidence requirements per gate
- `/extract-ssot identify` — produces the ranked candidate list; `verify` filters that list
- `/extract-ssot plan` — runs after `verify` returns PROCEED

## Recheck triggers

| Condition | Action |
|-----------|--------|
| Anthropic ships a canonical refuse-fast/dry-run convention for skill actions | Re-align the gate output schema; consider bringing it under the documented contract |
| A new empirical lesson lands in `context/lessons.md` | Evaluate adding a new gate to this action |
| A gate produces consistently wrong refusals (false-negative or false-positive across 3+ batches) | Tune the Tier 0 evidence threshold; document the tuning rationale in the working notes |
