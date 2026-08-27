---
description: "Audit markdown prose for AI-writing tells (slop): em dashes (zero-tolerance by default), emoji formatting, AI vocabulary, negative parallelisms, chatbot phrases, filler, stacked hedging, citation artifacts, model-era phrases ('that's the unlock', 'the part most people skip'), and the rest of the catalog (distilled from Wikipedia's Signs of AI writing plus an evolving model-era inventory), plus a judgment rubric for superficial analysis, vague attribution, promotional tone, metaphor jargon ('load-bearing', 'seam'), and mechanism-free claims. Use when: 'check for AI slop', 'de-slop this doc', 'unslop this', 'find AI tells', 'does this read AI-written', 'remove em dashes', or before publishing agent-written prose. Read-only by default; 'fix' as an explicit argument applies rewrites behind a semantic-diff guard and may be chained ('detect and rewrite'). Empty target audits the repo's tracked markdown, high-impact and high-velocity files first."
argument-hint: "[audit|fix] [target]"
user-invocable: true
disable-model-invocation: false
allowed-tools: ["Bash(${CLAUDE_SKILL_DIR}/scripts/detect.sh:*)", "Bash(${CLAUDE_SKILL_DIR}/scripts/emit-findings.sh:*)", "Bash(git:*)", "Bash(grep:*)", "Bash(head:*)", "Bash(wc:*)"]
shell: bash
metadata:
  workflow-stage: anytime
  summary: Detect and remove AI-writing tells from markdown prose
---

## Pre-computed context

Current branch: !`git branch --show-current 2>/dev/null || echo "unknown"`
Effective config: !`${CLAUDE_SKILL_DIR}/scripts/detect.sh --show-config 2>/dev/null | head -8 || echo "detector unavailable"`

## Purpose

Detect and remove AI-writing tells in checked-in markdown prose. Two detection layers over one
rule inventory ([`reference/catalog.md`](reference/catalog.md), distilled from Wikipedia's
"Signs of AI writing", revision-pinned, plus the catalog's "Cursor unslop additions" section
and its repo-owned, evidence-graded "Model-era additions" section of current-generation model
vocabulary):

1. **Deterministic**: `${CLAUDE_SKILL_DIR}/scripts/detect.sh` runs the catalog's `v1: script`
   rules. Its findings carry argued severity tiers (the detector-findings convention's crosswalk)
   and persist as a conforming findings file. **What the relay APPLIES is narrow; what it ROUTES
   is not.** `rule-utm-params` alone is auto-applicable, and every other rule is
   `/ai-slop:audit fix` work — but the crosswalk now declares that ownership, so the relay hands
   those rows to this skill's `fix` action rather than to its cleanup route, which prefers
   `/simplify`, a code-simplification skill, and applies the rows itself when `/simplify` is
   absent. Neither branch loads this skill's rewrite guide. The findings file is how a consumer
   *sees* them and how they reach the one surface that can rewrite them.
2. **Judgment rubric**: the catalog's `v1: rubric` tells, applied by reading the prose. Rubric
   findings reach the human report only, never the findings file.

Both layers sit behind the catalog's policy-level **quotation exemption**: wording rules never
scan blockquotes, double-quoted spans, or inline code spans (typography rules still do), so a
document that quotes a tell to document it, and a changelog that backticks the phrase a fix
removed, stay marker-free by construction.

## Action router

| Argument | Action |
|---|---|
| *(empty)* or `audit [target]` | Read-only audit (default). Empty target = repo-wide |
| `fix [target]` | Explicit fix pass over the target's findings (guarded; below). "Detect and rewrite" or `audit fix` chains audit then fix in one invocation |

## Audit flow

1. **Scope.** A path argument narrows to that file or directory. Empty target = the repo's
   tracked markdown minus config `excluded_paths`. Order repo-wide work by impact class first
   (instruction surfaces: `CLAUDE.md`, `AGENTS.md`, `.claude/rules/**`, `**/SKILL.md`,
   `README.md`), then by change frequency (`git log --since=90.days --name-only` counts over
   tracked `.md`); ordering affects report and chunk order only, never inclusion.
2. **Run the detector.** Chunk large corpora: write the ordered list to a temp file and invoke
   `detect.sh --paths-file <list> --offset N --limit M` per chunk (one process per chunk, no
   per-file shell loop; roughly 200 files per chunk keeps each call under a minute).
3. **Apply the rubric** to the highest-priority files (instruction surfaces always; further files
   as budget allows, saying which were rubric-covered). The rubric pass is independent of the
   detector: a file with zero script findings still gets its rubric read when it is in the
   priority set — a fix pass that only revisits detector hits has not covered the rubric. The
   rubric tells and their boundaries are the catalog entries marked `v1: rubric`; cite the
   entry when reporting. Counter-signs (the catalog's "Signs of human writing") temper a
   verdict, never generate findings.
4. **Report.** Group findings by file in priority order: for script findings quote the rule id,
   line, and fired condition; for rubric findings quote the offending text and name the catalog
   entry. State the declined counts (marker/config/code-fence exemptions) and any disabled rules
   from the detector's `Summary` rows. State what was scanned and what the rubric did not cover.
5. **Persist the findings file** per [`context/persist-findings.md`](context/persist-findings.md)
   whenever the audit examined tracked files: fetch the producer contract first and refuse to
   write when unreachable (report-only is then the outcome, and say so). Script findings only.
6. **Recommend**, never auto-run: the `fix` action for the findings, or `/ai-slop:setup` when the
   run tripped over deliberate house style (heavy declined counts or a flooded rule).
   `review:fanout fix` is now a valid route for the whole file, not just one rule: it hands every
   row but `rule-utm-params` to this skill's own `fix` action, which the crosswalk declares as
   their remediation owner. `rule-utm-params` is the one row the relay is *capable* of applying
   meaning-preservingly — do not promise that it will. It takes its ordinary cleanup class and
   reaches the relay's cleanup route, which prefers `/simplify`, a code-simplification skill that
   reads no findings file, and applies rows itself only when `/simplify` is absent. Recommend the
   relay when the operator is already running a fix pass; recommend this skill's `fix` directly
   when they are not, since it is the shorter path to the same rewrites. Name the condition that
   changes the answer — the relay can only hand the rows over when `/ai-slop:audit` is available
   in that session, and surfaces them otherwise.

## Fix flow (explicit invocation only)

Never runs on bare invocation. Requires the user's explicit `fix` (or a chained
"detect and rewrite" request). Per file, worst-first:

1. **Apply** the file's findings per [`reference/rewrite-guide.md`](reference/rewrite-guide.md)
   (read it first; it owns the replacement forms, the plain-speech target, the legitimate-hit
   taxonomy, the risky-class disambiguation rules, and the voice guidance): rewrite each
   flagged line (em dashes to commas, periods, or restructured sentences — never parentheses
   or en dashes, which swap one tell for another; deflate stock phrases; collapse
   parallelisms; delete filler and chat residue; strip `utm_*` params; delete or source
   residue artifacts) and the rubric rewrites for tells the audit reported. Preserve meaning
   over style: when a rewrite would change what a sentence asserts, skip it and record why.
   **Triads collapse toward one**: for a rule-of-three rubric finding, prefer the single
   strongest item and cut the rest — keep all three only when each is load-bearing (a complete
   set the reader needs, not rhetorical rhythm; enumerating three actual things is not a
   tell), and never collapse when the survivors would not entail the deleted items. Fewer
   parallel items is also less to maintain. Then run the guide's **voice pass** (its "Adding
   voice" section) on the file's authored-register prose — README narrative, changelog
   rationale, design tradeoffs; never operative instructions or reference tables — and close
   each file with the guide's self-audit pass ("what still makes this read machine-written?")
   before handing it to verification.
2. **Verify** with a fresh-context semantic-diff subagent: hand it the before/after pair,
   blind to the rewrite rationale; it flags SEMANTIC LOSS (a qualifier, threshold, or claim
   dropped), AMBIGUITY (a reading the original excluded), and QUOTE CORRUPTION (any changed
   byte inside quoted text), with the guide's risky classes called out for adversarial
   attention: a negative-parallelism restatement must preserve which reading the original
   meant, and a collapsed triad must still entail its deleted items. Revert every flagged
   hunk before moving on.
3. **Close** the file: findings fixed, explicitly suppressed (in-file marker with a reason), or
   reverted-with-reason. Report per file as you go on long runs.

After the last file: re-run the detector over the fixed set and re-emit the findings file per
[`context/persist-findings.md`](context/persist-findings.md) "Re-running", so no stale findings
file survives its own remediation. Then report totals: fixed, suppressed, reverted, remaining.

## Configuration

`.claude/ai-slop.json` per the config-cascade convention; keys, layers, and the in-file marker
forms are documented in the plugin README and managed by `/ai-slop:setup`. The detector's
`--show-config` names the layer supplying each effective value. When a whole document
legitimately needs em dashes, the remedy is `em_dash_allowed_paths` or the file marker, never a
threshold: the em-dash rule is zero-tolerance by design (user decision at plan approval).

## What this skill does NOT do

- **Does not fix on bare invocation.** `audit` and `scan` verbs are read-only in this
  marketplace; mutation rides only the explicit `fix` argument.
- **Does not put rubric findings in the findings file.** No crosswalk row, no relay: judgment
  verdicts reach the human report only (V1 boundary, revisit with field history).
- **Does not scan code comments** (`code-tidying:audit-comment-residue` owns them), commit
  messages, PR bodies, or non-repo text; structural markdown (heading hierarchy, multiple H1,
  title case) belongs to the markdown linter lane.
- **Does not weaken rules to pass its own corpus**: a deliberate house style is config in the
  consuming repo, never a shipped-default change.
