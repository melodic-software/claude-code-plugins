# `verify` action — pre-extraction gate

## Contents

- [When to invoke](#when-to-invoke)
- [Inputs](#inputs)
- [Output schema](#output-schema)
- [The 6 gates (ordered checks)](#the-6-gates-ordered-checks)
- [Workflow](#workflow)
- [Side observations](#side-observations)
- [Audit trail (optional)](#audit-trail-optional)
- [Cross-references](#cross-references)
- [Recheck triggers](#recheck-triggers)

Cheap pre-extraction gate. Assigns the candidate's multiplicity bucket, then refuses fast on candidates that wouldn't survive `plan`/`execute` anyway. Surfaces the bucket plus a PROCEED/refusal verdict from a single grep — or, for a semantic cluster, a short read of the candidate files — plus a citation check, without spawning a subagent. A sub-three bucket is a remedy constraint, not a refusal.

Private surface — external consumers invoke `/docs-hygiene:extract-ssot verify <cluster>`, never cite this file directly (contract: `/docs-hygiene:audit-encapsulation`).

## When to invoke

| Use case | Invoke |
|----------|--------|
| `/docs-hygiene:extract-ssot identify` produced a ranked candidate list and you want to filter before planning | YES |
| User typed `/docs-hygiene:extract-ssot verify <cluster>` directly | YES |
| Pre-batch filter inside the `batch` action | YES — automatic |
| You already have HIGH confidence the cluster passes the 6+5 gate | OPTIONAL — `plan` will re-verify Tier 0 |
| Cluster has 1 or 2 instances | YES — `identify` no longer refuses these; `verify` assigns the bucket and returns the bucket-appropriate non-abstracting remedies |

`verify` is OPTIONAL. It does NOT gate `plan`/`execute` automatically — preserves user agency. Skipping `verify` and going straight to `plan` is supported.

## Inputs

```text
/docs-hygiene:extract-ssot verify <cluster-name>
```

`<cluster-name>` matches a candidate from a recent `/docs-hygiene:extract-ssot identify` output OR is a free-form descriptor of the cluster the user wants to gate.

## Output schema

```yaml
status: PROCEED | REFUSE-{reason} | WARN
bucket: N=1 | N=2 | N>=3          # assigned by Gate 1 from the full-reproduction count
reason-code: <see table below>
permitted-remedies:                # the bucket's remedy set; empty on REFUSE
  - <trim-to-citation | normalize-wording | edit-existing-rule | name-an-owner | rule-file | new-skill | new-action>
evidence:
  - <Tier 0 grep output snippet>
  - <Tier 0 grep output snippet>
blockers:
  - <one-line cause>
next-action: <one of the recommended next steps>
notes: <optional 1-line context>
```

`bucket:` is emitted on EVERY verdict, refusals included — the caller needs it to file the candidate
in the right roster section.

Status values:

| Status | Meaning |
|--------|---------|
| `PROCEED` | All 6 gates pass. `permitted-remedies` lists what the assigned bucket allows: N=1 → `trim-to-citation` / `normalize-wording`; N=2 → `trim-to-citation` / `edit-existing-rule` / `name-an-owner` / `normalize-wording` (trim both recaps when a canonical home exists; name an owner when neither file is one); N≥3 → those plus `rule-file` / `new-skill` / `new-action` behind the 6-test gate. Safe to invoke `/docs-hygiene:extract-ssot plan <cluster>` |
| `REFUSE-rule-of-three-fails` | An **artifact-creating** output (`rule-file` / `new-skill` / `new-action`) was suggested or requested at N < 3 (Gate 1). Fires ONLY against those three artifact-creating outputs below N≥3 — never against reporting, and never against any non-abstracting remedy. (The issue vocabulary calls this `REFUSE-premature`; the code here is the canonical one) |
| `REFUSE-already-cites-canonical` | All call sites already cite an existing canonical SSOT (Gate 2) |
| `REFUSE-primary-source-citation-gate` | Sites cite a vendor/RFC/spec URL directly; internal SSOT can't improve (Gate 3) |
| `REFUSE-source-of-truth-bifurcation` | **Intentional** bifurcation — top-tier instruction file ↔ rule-file pair both canonical at different tiers for different audiences; forcing a single citation = cycle (Gate 4). Accidental bifurcation does NOT refuse here; it is the N=2 bucket |
| `REFUSE-off-by-one-different-concern` | Surface-similar but different step counts / variant shapes signal distinct concerns (Gate 5) |
| `REFUSE-low-roi` | Single short stable claim; inline beats abstraction maintenance (Gate 6) |
| `WARN-borderline` | Gates pass but evidence is marginal (e.g. 3 instances exactly, or one gate flagged) — `plan` should include an adversarial-review round |
| `REFUSE-not-found` | Cluster name doesn't resolve to any matching content — neither the literal grep nor the semantic reading found an instance (Gate 0) |

## The 6 gates (ordered checks)

Each gate has Tier 0 evidence requirements — direct grep/read output captured this turn per SKILL.md "Evidence discipline". For Gates 1–3 partial facts, run:

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/emit-verify-facts.sh" --phrase "<discriminating phrase>"
```

Map the script output to gate evidence; emit the `status: PROCEED | REFUSE-* | WARN` YAML in the skill — the script never emits verdicts. The script takes a phrase, so it serves literal clusters; a semantic cluster has no shared phrase, and its Gate 1 count comes from reading the candidate files (Gate 1, semantic shape).

Gate 1 assigns the bucket and gates artifact-creating remedies against it. Gate 4 splits intentional
bifurcation (refuses, any bucket) from accidental (the N=2 bucket's own defect). Gates 0, 3, 5, and 6
are unchanged and multiplicity-independent: they judge cluster validity and ROI, so their refusals
apply in every bucket.

### Gate 0: Cluster resolution

Before any gate runs, confirm the cluster exists in the repo. Resolution is evidence-shape-aware,
matching the two shapes `actions/identify.md` "Per-candidate evidence requirement" defines.

- Step 1: classify the cluster's shape. **Literal** (identify forms a, e) — identify a
  discriminating phrase from the cluster body (≥ 8 words, unique enough to grep cleanly).
  **Semantic** (identify forms c2, i — reproductions share no verbatim ≥ 8-word phrase) — state the
  canonical truth in one sentence instead; there is no phrase to grep for
- Step 2: literal → grep the phrase across the repo's tracked markdown. Semantic → read the
  candidate files and collect the paragraphs that reproduce that canonical truth in any phrasing
- Step 3: `REFUSE-not-found` fires ONLY when NEITHER the literal grep NOR the semantic reading
  resolves any instance. A semantic cluster is **not** "not found" merely because its phrase grep
  hits one file — that is the expected grep result for a paraphrase cluster; carry it to Gate 1 and
  count it there by reading

### Gate 1: Bucket assignment from an evidence-shape-aware count

**Lesson 1** — keyword density over-counts; use discriminating-phrase grep instead.

This gate ASSIGNS the bucket. It does not refuse on count alone. Count by the cluster's evidence
shape, mirroring `actions/identify.md` — discriminating-phrase grep for literal clusters,
reading-driven canonical-truth clustering for semantic ones. Phrase grep applied to a semantic
cluster undercounts it to 1 and files a real N=2/N≥3 paraphrase cluster in the wrong bucket.

**Literal clusters (identify forms a, e):**

- Identify a verbatim phrase that uniquely characterizes this cluster (NOT keywords like "subagent" or "rate limit" that appear everywhere)
- Multiline grep where appropriate (use `multiline: true` for cross-line patterns)
- Count distinct **full reproductions** (not paraphrase mentions, not 1-line teaching mentions, not citation-only references)

**Semantic clusters (identify forms c2, i — no shared verbatim ≥ 8-word phrase):**

- Read the candidate files; do not rely on phrase grep, which finds only the instance the phrase was lifted from
- Count distinct files whose paragraph reproduces the canonical truth in ANY phrasing — the same reading-derived canonical-truth roster `identify` Pass B builds
- Grep still helps as a file-shortlist (topic keywords, cited concept names); the COUNT comes from the reading
- Exclusions are unchanged: 1-line teaching mentions, citation-only references, and form (h) domain-specific applications are not reproductions

**Both shapes:**

- Assign `bucket:` from that count — 1 → `N=1`, 2 → `N=2`, ≥3 → `N>=3` — and emit it
- At `N=1`, confirm the bucket's admission gate: a canonical home exists that this site recaps instead of cites. No existing home + a single site = not duplication → `REFUSE-not-found` (nothing is being reproduced)
- Refuse ONLY on remedy mismatch: if the suggested or user-requested output is artifact-creating (`rule-file` / `new-skill` / `new-action`) and the bucket is `N=1` or `N=2` → `REFUSE-rule-of-three-fails`, naming the bucket's permitted remedies in `next-action`
- Otherwise continue to Gate 2 with `permitted-remedies` set from the bucket

Tier 0 evidence form — literal shape:

```text
Grep pattern: '<discriminating phrase ≥ 8 words>'
Files matched (full reproductions): <n>
  - <path>:<line>
  - <path>:<line>
  - <path>:<line>
Files matched (teaching mentions, excluded): <n>
  - <path>:<line> (1-line mention, kept inline)
Bucket assigned: N=1 | N=2 | N>=3
Artifact creation: permitted (N>=3, subject to the 6-test gate) | refused (N<3)
```

Tier 0 evidence form — semantic shape (no shared verbatim phrase to grep):

```text
Canonical truth: '<the single rule/fact each reproduction asserts, in one sentence>'
Files read: <n>
Files reproducing the truth (full reproductions): <n>
  - <path>:<line> — "<paraphrase excerpt>"
  - <path>:<line> — "<paraphrase excerpt>"
  - <path>:<line> — "<paraphrase excerpt>"
Files excluded: <n>
  - <path>:<line> (1-line mention | citation-only | form (h) domain-specific application)
Bucket assigned: N=1 | N=2 | N>=3
Artifact creation: permitted (N>=3, subject to the 6-test gate) | refused (N<3)
```

### Gate 2: Pre-existing canonical citation check

**Lesson 2** — sites already citing canonical = no extraction work remains.

- For each call site found in Gate 1, grep the surrounding ~10 lines for an existing citation pattern: `per <some>.md "<heading>"` or backtick-`<some>.md` references
- Count call sites already citing canonical
- If ALL call sites already cite a canonical SSOT → `REFUSE-already-cites-canonical`
- If SOME do but not all → continue (the `execute` action would sweep stragglers); proceed to Gate 3

This gate is the natural terminal for the N=1 bucket: a single site that recaps a canonical home
PROCEEDs with `trim-to-citation`; a single site that already cites it correctly has no work left and
refuses here.

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

Detect the bifurcation pattern, then split intentional from accidental:

- Did the cluster originate in `CLAUDE.md` or `AGENTS.md` (top-tier always-loaded)?
- Is the cluster ALSO present in a scoped rule file (deep-disclosure aggregator for hook/skill/script authors)?
- If both: forcing the instruction file to cite the rule = citation cycle. Each tier serves a different audience legitimately.

**Intentional bifurcation** — two tiers, two named audiences, the split reads as deliberate →
`REFUSE-source-of-truth-bifurcation`. Document both canonicals + their respective audiences in the
output `notes:` field. This is the case anti-pattern #11 protects and it refuses at any bucket.

**Accidental bifurcation** — two files assert the same contract, serve the SAME audience, and
NEITHER is declared the owner. This is not the protected case; it is the N=2 bucket's defect.
Emit `PROCEED` with `bucket: N=2` and `permitted-remedies: [name-an-owner, edit-existing-rule,
normalize-wording]` — this branch has no canonical home yet, so `trim-to-citation` (the other N=2
shape's remedy) has no target until an owner is named. Creating a third file to own the contract is
NOT among them.

Tier 0 evidence form:

```text
Top-tier source: <CLAUDE.md|AGENTS.md>:<line> "<section>"
Aggregator rule: <rule-file>.md:<line> "<heading>"
Audiences:
  Top-tier: <e.g. "every loaded session">
  Aggregator: <e.g. "hook authors / skill authors who Read the rule explicitly">
Distinct audiences? <yes → intentional, REFUSE | no → accidental, N=2 remedies>
Declared owner? <path, or "none — accidental bifurcation">
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
3. Gate 1 — count full reproductions by evidence shape (phrase grep for literal clusters, reading
   for semantic ones), ASSIGN the bucket, gate artifact-creating remedies against it
4. Gate 2 — pre-existing citation check
5. Gate 3 — primary-source citation gate
6. Gate 4 — source-of-truth bifurcation check
7. Gate 5 — off-by-one shape divergence
8. Gate 6 — LOW-ROI threshold
9. Emit structured output (status + evidence + next-action)
10. Optionally append a dated verify entry to the working notes (audit trail)
```

If ANY gate REFUSES, stop and emit. Don't run remaining gates — output the first refusal reason. (Avoids overspecified output that obscures the actual blocker.)

If ALL gates pass, emit `PROCEED` with summary evidence, the assigned `bucket:`, and the bucket's
`permitted-remedies`. User runs `/docs-hygiene:extract-ssot plan <cluster>` next.

## Side observations

When a gate REFUSES with high confidence, the cluster may still warrant action — just not the action `/docs-hygiene:extract-ssot` provides. Emit ONE side observation per refusal:

| Refusal | Side observation form |
|---------|----------------------|
| `REFUSE-already-cites-canonical` | `Side note: cluster already extracted at <canonical>; no SSOT work remains. Sweep stragglers if any?` |
| `REFUSE-primary-source-citation-gate` | `Side note: <n> sites cite <primary URL>; internal SSOT redundant. Verify URL still resolves.` |
| `REFUSE-source-of-truth-bifurcation` | `Side note: bifurcated SSOT — document the two audiences in the rule file so the split reads as intentional.` |
| `REFUSE-low-roi` | `Side note: inline + cite primary if needed; surface to user only if drift starts.` |
| `REFUSE-off-by-one-different-concern` | `Side note: <n> distinct concerns; consider /docs-hygiene:extract-ssot identify with a narrower discriminating phrase per concern.` |
| `REFUSE-rule-of-three-fails` | `Side note: bucket <N=1\|N=2> — no new artifact, but <permitted remedies> still apply; the candidate stays on the roster.` |

Hard limit ≤2 side notes per response. If multiple gates fire, batch the rest into the working-notes entry.

## Audit trail (optional)

When `verify` runs as part of `/docs-hygiene:extract-ssot batch`, it MUST append a verify audit entry to the batch working notes so the batch summary can aggregate verdicts. When run standalone, an audit entry is OPTIONAL but recommended for non-trivial clusters.

Entry format:

```markdown
---
type: verify-evidence
date: <ISO-8601 UTC, e.g. 2026-06-04T14:30:00Z>
cluster: <name>
verdict: <status>
bucket: <N=1|N=2|N>=3>
---
## Cluster
<short description>

## Gate results
| Gate | Result | Evidence |
|------|--------|----------|
| 0 — Cluster resolution | PASS | <count> matches |
| 1 — Bucket assignment (phrase grep / semantic reading) | <bucket + PASS|FAIL> | <evidence snippet> |
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
- `/docs-hygiene:extract-ssot identify` — produces the ranked candidate list; `verify` filters that list
- `/docs-hygiene:extract-ssot plan` — runs after `verify` returns PROCEED

## Recheck triggers

| Condition | Action |
|-----------|--------|
| Anthropic ships a canonical refuse-fast/dry-run convention for skill actions | Re-align the gate output schema; consider bringing it under the documented contract |
| A new empirical lesson lands in `context/lessons.md` | Evaluate adding a new gate to this action |
| A gate produces consistently wrong refusals (false-negative or false-positive across 3+ batches) | Tune the Tier 0 evidence threshold; document the tuning rationale in the working notes |
