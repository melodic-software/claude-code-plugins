---
description: "Audit markdown prose for AI-writing tells (slop): em dashes (zero-tolerance by default), emoji formatting, AI vocabulary, negative parallelisms, citation artifacts, and the rest of the Signs-of-AI-writing catalog, plus a judgment rubric for puffery, vague attribution, and promotional tone. Use when: 'check for AI slop', 'de-slop this doc', 'find AI tells', 'does this read AI-written', 'remove em dashes', or before publishing agent-written prose. Read-only by default; 'fix' as an explicit argument applies rewrites behind a semantic-diff guard and may be chained ('detect and rewrite'). Empty target audits the repo's tracked markdown, high-impact and high-velocity files first."
argument-hint: "[audit|fix] [target]"
user-invocable: true
disable-model-invocation: false
allowed-tools: ["Bash(${CLAUDE_SKILL_DIR}/scripts/detect.sh:*)", "Bash(${CLAUDE_SKILL_DIR}/scripts/emit-findings.sh:*)", "Bash(git:*)", "Bash(grep:*)", "Bash(head:*)", "Bash(wc:*)"]
shell: bash
---

## Pre-computed context

Current branch: !`git branch --show-current 2>/dev/null || echo "unknown"`
Effective config: !`${CLAUDE_SKILL_DIR}/scripts/detect.sh --show-config 2>/dev/null | head -8 || echo "detector unavailable"`

## Purpose

Detect and remove AI-writing tells in checked-in markdown prose. Two detection layers over one
rule inventory ([`reference/catalog.md`](reference/catalog.md), distilled from Wikipedia's
"Signs of AI writing", revision-pinned):

1. **Deterministic**: `${CLAUDE_SKILL_DIR}/scripts/detect.sh` runs the catalog's `v1: script`
   rules. Its findings carry argued severity tiers (the detector-findings convention's crosswalk)
   and can reach the `review:fanout fix` relay as a conforming findings file.
2. **Judgment rubric**: the catalog's `v1: rubric` tells, applied by reading the prose. Rubric
   findings reach the human report only, never the findings file.

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
   as budget allows, saying which were rubric-covered). The rubric tells and their boundaries are
   the catalog entries marked `v1: rubric`; cite the entry when reporting. Counter-signs
   (the catalog's "Signs of human writing") temper a verdict, never generate findings.
4. **Report.** Group findings by file in priority order: for script findings quote the rule id,
   line, and fired condition; for rubric findings quote the offending text and name the catalog
   entry. State the declined counts (marker/config/code-fence exemptions) and any disabled rules
   from the detector's `Summary` rows. State what was scanned and what the rubric did not cover.
5. **Persist the findings file** per [`context/persist-findings.md`](context/persist-findings.md)
   whenever the audit examined tracked files: fetch the producer contract first and refuse to
   write when unreachable (report-only is then the outcome, and say so). Script findings only.
6. **Recommend**, never auto-run: the `fix` action for the findings, `/ai-slop:setup` when the
   run tripped over deliberate house style (heavy declined counts or a flooded rule), or
   `review:fanout fix` where the consumer prefers the relay to apply mechanical fixes.

## Fix flow (explicit invocation only)

Never runs on bare invocation. Requires the user's explicit `fix` (or a chained
"detect and rewrite" request). Per file, worst-first:

1. **Apply** the file's findings: rewrite each flagged line (em dashes to commas, colons,
   periods, or restructured sentences; deflate stock phrases; collapse parallelisms; strip
   `utm_*` params; delete or source residue artifacts) and the rubric rewrites for tells the
   audit reported. Preserve meaning over style: when a rewrite would change what a sentence
   asserts, skip it and record why. **Triads collapse toward one**: for a `rule-of-three`
   finding, prefer the single strongest item and cut the rest — keep all three only when each
   is load-bearing (a complete set the reader needs, not rhetorical rhythm; enumerating three
   actual things is not a tell). Fewer parallel items is also less to maintain.
2. **Verify** with a fresh-context semantic-diff subagent (the compress model): hand it the
   before/after pair, blind to the rewrite rationale; it flags SEMANTIC LOSS (a qualifier,
   threshold, or claim dropped) and AMBIGUITY (a reading the original excluded). Revert every
   flagged hunk before moving on.
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
