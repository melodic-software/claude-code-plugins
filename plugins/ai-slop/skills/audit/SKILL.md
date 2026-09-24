---
description: "Audit markdown prose for AI-writing tells (slop): em dashes (zero-tolerance by default), emoji formatting, AI vocabulary, negative parallelisms, chatbot phrases, filler, stacked hedging, citation artifacts, model-era phrases ('that's the unlock', 'the part most people skip'), and the rest of the catalog (distilled from Wikipedia's Signs of AI writing plus an evolving model-era inventory), plus a judgment rubric for superficial analysis, vague attribution, promotional tone, metaphor jargon ('load-bearing', 'seam'), and mechanism-free claims. Use when: 'check for AI slop', 'de-slop this doc', 'unslop this', 'find AI tells', 'does this read AI-written', 'remove em dashes', or before publishing agent-written prose. Read-only by default; 'fix' as an explicit argument applies rewrites behind a semantic-diff guard and may be chained ('detect and rewrite'). Empty target audits the repo's tracked markdown, high-impact and high-velocity files first."
argument-hint: "[audit|fix] [target]"
user-invocable: true
disable-model-invocation: false
allowed-tools: ["Bash(${CLAUDE_SKILL_DIR}/scripts/detect.sh:*)", "Bash(\"${CLAUDE_SKILL_DIR}/scripts/detect.sh\":*)", "Bash(${CLAUDE_SKILL_DIR}/scripts/emit-findings.sh:*)", "Bash(${CLAUDE_SKILL_DIR}/scripts/rubric-fanout.sh:*)", "Bash(\"${CLAUDE_SKILL_DIR}/scripts/rubric-fanout.sh\":*)", "Bash(${CLAUDE_SKILL_DIR}/scripts/cross-check.sh:*)", "Bash(\"${CLAUDE_SKILL_DIR}/scripts/cross-check.sh\":*)", "Bash(sha256sum:*)", "Bash(shasum:*)", "Bash(mkdir:*)", "Bash(git:*)", "Bash(grep:*)", "Bash(head:*)", "Bash(wc:*)"]
shell: bash
metadata:
  workflow-stage: anytime
  summary: Detect and remove AI-writing tells from markdown prose
---

## Repository context. Gather first

Collect these with **individual** Bash calls, one command per call, never combined into a single
invocation:

- Current branch, `git branch --show-current`

Treat a failure (not a repository, git unavailable) as an unknown value and carry on. Keep these as
separate body Bash calls rather than pre-compute lines: the harness runs a skill's whole pre-compute
block as one shell invocation, and a worktree-isolated session refuses a compound command that
contains git.

## Pre-computed context

Effective config: !`"${CLAUDE_SKILL_DIR}/scripts/detect.sh" --show-config >/dev/null 2>&1 && { "${CLAUDE_SKILL_DIR}/scripts/detect.sh" --show-config 2>/dev/null | head -40; :; } || echo "detector unavailable"`

The bound above is generous on purpose: `--show-config` prints `disabled_rules` and every
`rule_allowed_paths` entry after the fixed lines, and those are the values that decide which
rules ran at all.

## Purpose

Detect and remove AI-writing tells in checked-in markdown prose. Two detection layers over one
rule inventory ([`reference/catalog.md`](reference/catalog.md), distilled from Wikipedia's
"Signs of AI writing", revision-pinned, plus the catalog's "Cursor unslop additions" section
and its repo-owned, evidence-graded "Model-era additions" section of current-generation model
vocabulary):

1. **Deterministic**: `${CLAUDE_SKILL_DIR}/scripts/detect.sh` runs the catalog's `v1: script`
   rules. Its findings carry argued severity tiers (the detector-findings convention's crosswalk)
   and persist as a conforming findings file, which is how a consumer sees them and how they
   reach a surface that can rewrite them. Audit step 6 names which surface, and when.
2. **Judgment rubric**: the catalog's `v1: rubric` tells, applied by reading the prose. Rubric
   findings reach the human report only, never the findings file.

Both layers sit behind the catalog's policy-level **quotation exemption**: no rule scans fenced
code or inline code spans, wording rules also skip blockquotes and double-quoted spans, and
typography rules (em dashes, emoji, paste residue, citation tokens, tracking params) still scan
blockquotes and double-quoted spans. A document that quotes a wording tell to document it, and a
changelog that backticks the phrase a fix removed, stay marker-free by construction.

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
   tracked `.md`). `rubric-fanout.sh plan` applies this order to the rubric batches; the
   detector keeps its own path order, and ordering never changes inclusion. Inside a
   repository, a directory target expands to its tracked markdown only, so pass untracked
   in-repo files as file paths. Check the target first: a target outside any repository
   follows [Non-repository targets](#non-repository-targets).
2. **Run the detector.** Build the target list once: `detect.sh --list-targets <targets>`,
   with its stdout redirected to a list file in the session scratchpad (with no targets, it
   lists the repository's tracked markdown). Each line is `<key><TAB><path>`, the key spelled as the
   detector's `file=` field, after directory expansion and `excluded_paths`. That file feeds
   the chunked runs, `detect.sh --paths-file <list> --offset N --limit M` per chunk (one
   process per chunk, no per-file shell loop; roughly 200 files per chunk keeps each call under
   a minute), and `rubric-fanout.sh plan` in step 3. A `--paths-file` with no paths scans
   nothing.
3. **Apply the rubric** to every file in scope, in the same priority order. The rubric pass is
   independent of the detector: a file with zero script findings still gets its rubric read,
   and a fix pass that only revisits detector hits has not covered the rubric. The rubric tells
   and their boundaries are the catalog entries marked `v1: rubric`; cite the entry when
   reporting. Counter-signs (the catalog's "Signs of human writing") temper a verdict, never
   generate findings. Coverage is uniform: never trade the rubric away for budget on a
   repo-wide run. Make it affordable by fanning out instead, per
   [`context/rubric-fanout.md`](context/rubric-fanout.md), with `rubric-fanout.sh`: `plan`
   orders the step 2 list and packs it into batches of about 50,000 words, `extract` writes
   the rubric text to one file, one fresh-context subagent per batch gets that file's path and
   its batch list and writes its result file into the findings home (the scratchpad for a
   non-repository target) before it reports, `status` names the batches that still need a run,
   and `merge` joins the results once every batch is complete. A batch whose result file is
   bound to its current list is skipped on a re-run, so a rate limit or a crash costs one
   batch, not the pass, and a leftover result from an earlier scope is never accepted.
4. **Report.** Group findings by file in priority order: for script findings quote the rule id,
   line, and fired condition; for rubric findings quote the offending text and name the catalog
   entry. State the declined counts (marker/config/code-fence exemptions) and any disabled rules
   from the detector's `Summary` rows. State what was scanned and what the rubric did not cover.
5. **Persist the findings file** per [`context/persist-findings.md`](context/persist-findings.md)
   whenever the audit examined tracked files: fetch the producer contract first and refuse to
   write when unreachable (report-only is then the outcome, and say so). Script findings only.
   A run with any non-repository target writes no findings file.
6. **Recommend**, never auto-run: the `fix` action for the findings, or `/ai-slop:setup` when the
   run tripped over deliberate house style (heavy declined counts or a flooded rule).
   `review:fanout fix` routes the whole file: it hands every row but `rule-utm-params` to this
   skill's own `fix` action, which the crosswalk declares as their remediation owner. `rule-utm-params` is the one row the relay is *capable* of applying
   meaning-preservingly. Do not promise that it will. It takes its ordinary cleanup class and
   reaches the relay's cleanup route, which prefers `/simplify`, a code-simplification skill that
   reads no findings file, and applies rows itself only when `/simplify` is absent. Neither the
   relay's own applier nor `/simplify` loads this skill's rewrite guide. Recommend the relay when
   the operator is already running a fix pass; recommend this skill's `fix` directly
   when they are not, since it is the shorter path to the same rewrites. Name the condition that
   changes the answer: the relay can only hand the rows over when `/ai-slop:audit` is available
   in that session, and surfaces them otherwise.

### Non-repository targets

A target is outside a repository when `git -C <dir> rev-parse --is-inside-work-tree` fails or
does not print `true`, where `<dir>` is the target directory or a file target's parent. Check
the target, not the cwd. An empty target checks `CLAUDE_PROJECT_DIR`, else the cwd; when that is
not a repository, stop and ask for an explicit path instead of guessing a scope. If any target
is outside a repository, the whole run follows these rules:

- Pass targets to the detector as absolute paths, and use the `file=` path it reports as the
  path everywhere else in the run. It may be relative (to `CLAUDE_PROJECT_DIR`, else the git
  toplevel or cwd) when the target sits under that directory.
- A directory target expands to every `*.md` beneath it, untracked and vendored files included.
  The detector usually prints a "could not confirm a work tree" line on stderr; a target inside
  a `.git` directory is walked with no message. Both are expected.
- Order files by modification time, newest first, ties broken by path. Ordering never changes
  inclusion. `rubric-fanout.sh plan` picks this order for a target outside a repository; apply
  it to the report too.
- Config layers come from the session's project directory and the user-global file, not from
  the target. `--show-config` names the layers in effect. A path glob such as `excluded_paths`
  applies only when it matches the path as the detector sees it.
- No findings file: none is written, and the fix flow's closing re-emit is skipped.
- A `fix` run has no git history to undo an edit, so back up each file before editing it:
  - The backup path mirrors the file's full absolute path under the fix flow's run directory,
    with a drive letter as a directory. Never name a backup by basename alone: a target holds
    many files named `SKILL.md`.
  - If the backup path already exists, do not edit the file. Stop and report it.
  - If the backup cannot be written (the copy fails, or the mirrored path is not a valid path,
    as a `\\?\` or UNC source produces), do not edit the file. Stop and report it.
  - Next to each backup, write `<backup>.source` holding the file's absolute path.
  - Verification takes the backup as the "before" file. Before restoring any hunk, read
    `<backup>.source` and confirm it equals the file being restored; on a mismatch restore
    nothing and report it. Restore only the hunks verification flags; an edit that passes
    stays. Name the backup path in the per-file report.

  Example, run directory `R`, home directory `H` on drive `C:`:
  `H/.claude/skills/a/SKILL.md` backs up to `R/C/H/.claude/skills/a/SKILL.md`, and `H/.claude/skills/b/SKILL.md` to
  `R/C/H/.claude/skills/b/SKILL.md`, with `H` spelled out in full. The two never collide, and each `.source` file
  names its own original, so a restore meant for `a` can never write `b`'s content.
- Rubric batch lists and result files go under the session scratchpad, else the system temp
  directory, per [`context/rubric-fanout.md`](context/rubric-fanout.md).
- `rule-style-shift` is not evaluable, because there is no history to compare against. Report
  it under what the rubric did not cover.

## Fix flow (explicit invocation only)

Never runs on bare invocation. Requires the user's explicit `fix` (or a chained
"detect and rewrite" request).

Every fix run first creates one new run directory, `<scratchpad>/ai-slop-fix-<TS>/` (`TS` as
in [`context/persist-findings.md`](context/persist-findings.md)). A path "mirrored" under it
is the file's full absolute path with a drive letter as a directory, the same rule the
non-repository backups use.

**Concurrent-edit guard.** The flow assumes nothing else writes the files it fixes, and checks
that before each of its own writes. When the flow first reads a file, before it composes any
rewrite, record the file's digest: create the state file's parent directory, then run
`sha256sum <absolute path>` with its stdout redirected to `<run>/digests/<mirrored
path>.sha256`. Before every write the flow makes to that file, a rewrite or a restore, run
`sha256sum -c --status <that state file>`; after each of its own writes, record the digest
again the same way. On a mismatch, write nothing more to the file, stop work on it, and report
it. If the state file cannot be written, do not edit the file; stop and report it. On macOS use
`shasum -a 256` and `shasum -a 256 -c`. A write that lands between a check and
the re-record after the flow's own write is not detected.

Per file, worst-first:

1. **Apply** the file's findings per [`reference/rewrite-guide.md`](reference/rewrite-guide.md)
   (read it first; it owns the replacement forms, the plain-speech target, the legitimate-hit
   taxonomy, the risky-class disambiguation rules, and the voice guidance): rewrite each
   flagged line (em dashes to commas, periods, or restructured sentences, never parentheses
   or en dashes, which swap one tell for another; deflate stock phrases; collapse
   parallelisms; delete filler and chat residue; strip `utm_*` params; delete or source
   residue artifacts) and the rubric rewrites for tells the audit reported. Preserve meaning
   over style: when a rewrite would change what a sentence asserts, skip it and record why.
   **Triads collapse toward one**: for a rule-of-three rubric finding, prefer the single
   strongest item and cut the rest. Keep all three only when each item is needed (a complete
   set the reader needs, not rhetorical rhythm; enumerating three actual things is not a
   tell), and never collapse when the survivors would not entail the deleted items. Fewer
   parallel items is also less to maintain. Then run the guide's **voice pass** (its "Adding
   voice" section) on the file's authored-register prose: README narrative, changelog
   rationale, design tradeoffs; never operative instructions or reference tables. Close each
   file with the guide's self-audit pass ("what still makes this read machine-written?")
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

After the last file: build the fixed set's list with `detect.sh --list-targets`, run the
detector over it with `--paths-file`, redirecting both outputs to files in the run directory,
and re-emit the findings file per [`context/persist-findings.md`](context/persist-findings.md)
"Re-running", so no stale findings file survives its own remediation. Skip the re-emit for a
non-repository target, which never wrote one. Then run `cross-check.sh --targets <list>
--detector <detector output>`: it counts em-dash lines with its own parse, so an em dash the
detector's parse missed still shows up. It follows the detector's fence rules but not its
full parse, and compares a count per file, not which lines, so treat a `Disagree:` row as a
file to reread rather than a proven miss. Report every `Disagree:` row, then totals:
fixed, suppressed, reverted, remaining.

## Configuration

`.claude/ai-slop.json` per the config-cascade convention; keys, layers, and the in-file marker
forms are documented in the plugin README and managed by `/ai-slop:setup`. The detector's
`--show-config` names the layer supplying each effective value. When a whole document
legitimately needs em dashes, the remedy is `em_dash_allowed_paths` or the file marker, never a
threshold. The em-dash rule is zero-tolerance by design; the catalog's `rule-em-dash` entry
carries the reason.

## What this skill does NOT do

- **Does not fix on bare invocation.** `audit` and `scan` verbs are read-only in this
  marketplace; mutation rides only the explicit `fix` argument.
- **Does not put rubric findings in the findings file.** No crosswalk row, no relay: judgment
  verdicts reach the human report only (V1 boundary, revisit with field history).
- **Does not scan code comments** (`code-tidying:audit-comment-residue` owns them), commit
  messages, PR bodies, or text outside markdown files; structural markdown (heading
  hierarchy, multiple H1, title case) belongs to the markdown linter lane. Reshaping those
  commit messages, PR bodies and other text so they lead with the point and carry fewer words
  is `/writing:be-concise`,
  which owns that doctrine when the `writing` plugin is installed; without it, say the text
  sits outside this skill's regime rather than auditing it anyway.
- **Does not weaken rules to pass its own corpus**: a deliberate house style is config in the
  consuming repo, never a shipped-default change.
