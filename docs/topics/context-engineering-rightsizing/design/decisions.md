# Locked decisions

Operator ratified the full recommendation set on 2026-07-25. Each row is binding on every lane that
follows. A lane that finds a locked decision wrong reports it and stops; it does not re-decide.

## Scope and posture

| # | Decision | Consequence |
|---|---|---|
| D-1 | **Incumbent-first gate is binding.** No remediation ships until it proves no existing skill already covers it | Every lane's first work item is an incumbent search with `path:line` evidence |
| D-2 | **`UNBACKED` claims are report-only and opt-in.** Never auto-applied | Roughly a third of the article's claims. They ship marked, disabled by default, with a severity ceiling |
| D-3 | **No bulk sweep of `plugins/**`.** Findings land as checks in the plugin that already owns each surface | `claude-config`, `claude-memory`, `skill-quality` are the homes. No new router |
| D-4 | **This effort ships two things**: the criteria catalog, and the cross-surface instruction-conflict detector | The conflict detector is the one finding with no incumbent and no existing ticket |
| D-5 | **Verifier-subagent pattern stays, narrowed.** Drop blanket dispatch on mechanical behavior-preserving work; keep it where the verdict is subjective or blast radius is wide | Resolves the three-way tension between Opus 5 guidance, Claude Code best practices, and 23 implementing skills |
| D-6 | **`plugins/playbooks/skills/fable-5/**` is excluded** from this pass | PR #1261 is actively rewriting it |

## Sequencing

| # | Decision | Consequence |
|---|---|---|
| D-7 | **Fold the listing-budget material into issue #1271**, and adopt its `when_to_use` lever | #1271 already measured the defect and found the field this effort's agents missed. No second ticket |
| D-8 | **Sequence behind PR #1096** for anything touching `check-skill.sh` or `docs/PLUGIN-PHILOSOPHY.md` | Check 21 is taken. New criteria pick a free number against the post-merge file |
| D-9 | **Sequence the user-scope work behind dotfiles PRs #318 and #312**, and read #312's Opus 5 re-derivation as an input before measuring | Measuring `dot_claude/CLAUDE.md` while two PRs edit it produces a diff that reverts newer rules |
| D-10 | **Drop the stale dotfiles branch** `docs/claude-md-github-conventions` (+13 lines to `CLAUDE.md`, last commit 2026-07-15, no PR) | One fewer writer on the contested file |
| D-11 | **Reconcile with issue #1225 before building anything sweep-shaped** | Two repo-wide sweeps become two routers |

## Machine health (from `/doctor`, 2026-07-24)

| # | Decision | Consequence |
|---|---|---|
| D-12 | **Fix the `guardrails` PreToolUse root cause.** p50 12–19s blocking every Bash call, ~1,464 runs in six days; a sibling guard in the same event class runs at 2ms | Not a matcher narrowing, not a disable. Root cause |
| D-13 | **Remove the zero-usage plugins** except `plugin-quality`, `context-guard` (both shipped the same day) and `visualization` (one hit under a different leaf name) | ~16 plugins, ~7.4k est. resident tokens |

## Operator-reserved calls (ratified 2026-07-25, second round)

These are the questions the section agents explicitly declined to answer, plus the scope boundary.

| # | Decision | Consequence |
|---|---|---|
| D-14 | **Execution scope is the collision set plus this effort** — the four sequencing blockers (#1096, #1261, dotfiles #318/#312), the two tickets folded into (#1271, #1225), the two machine-health fixes (D-12, D-13), and this effort's two deliverables. Roughly ten lanes | Not the 24-PR / 255-issue backlog. The 12 stale and draft PRs are **not** in scope; they need their own triage pass |
| D-15 | **Arbitration stays the repo's default posture.** Deletion is adopted only where a constraint has no current safety rationale | Overrides the article's blanket delete-constraints posture. A lane proposing a deletion must state the constraint's rationale and why it no longer holds |
| D-16 | **The fresh-docs mandate narrows in scope, not in substance** — it binds changes touching a plugin manifest, marketplace schema, hook contract, or documented harness behavior | Prose and mechanical edits are out. The mandate stays non-negotiable within its scope |
| D-17 | **Auto-memory: move `autoMemoryEnabled` from `claudeSettings.force` to `claudeSettings.seed`, seeded `false`** | Two decisions, both taken. The tier move ends the silent-revert trap; `seed` writes only when absent, so this machine keeps its current value and every fresh machine starts off. Overrides the S7 agent's `true` recommendation on tracked-drift grounds — the capability unlock is available per machine by toggle |
| D-18 | **Cut `CLAUDE.md:13-30`** (the doc-URL table) to a pointer at `docs/OFFICIAL-DOCS.md` | Verified strict subset; 29.6% of the file; line 30 already points at the superset. Accepted risk: the mandate's force must come from the rule, not from the URLs being pre-loaded |
| D-19 | **Vendored `skill-authoring` guidance governs authoring mechanics; this effort's carve-out governs what stays constrained** | Different axes. Where they genuinely collide, upstream wins and the divergence is recorded — a vendored file is never hand-edited |

## Standing constraints these decisions inherit

- **`~/.claude/settings.json` is chezmoi-managed** — verified: its source is
  `dot_claude/modify_settings.json`. D-13's plugin disables are therefore a **dotfiles change**, made
  on a feature-branch worktree of `melodic-software/dotfiles`, never an in-place edit. The same holds
  for `~/.claude/CLAUDE.md`.
- **`.work/` never leaves its checkout.** Anything a later lane must read is committed to
  `docs/topics/context-engineering-rightsizing/`.
- **The parallel branch** `docs/context-engineering-claude-5-topic` is still being worked by another
  session. This pass runs independently by operator ruling; the collision is resolved deliberately at
  merge, not by folding.

## Execution status and errata

Recorded 2026-07-25 at the end of the first execution pass. **The nineteen decisions above are
preserved verbatim as ratified.** Nothing in this section re-decides any of them. Where a decision's
supporting evidence did not survive first-hand verification, the correction is recorded here and the
decision's own text is left untouched.

Three decisions did not survive contact with measurement. In each case the lane reported and stopped
rather than re-deciding, which is what this contract requires of it.

### D-12 — errata: the supporting evidence is invalid; the directive stands

D-12 cites *"a sibling guard in the same event class runs at 2ms"* as its control. **That control
never ran.** Both disk-hygiene comparators failed at launch:

- `destructive_guard.py --mode engine-gate` — all 16 recorded runs are `hook_non_blocking_error`,
  `exitCode: 1`, stderr `Failed to run: Plugin option "disk_hygiene_enabled" isn't set.` The 2 ms is
  config validation refusing to launch, before any process is spawned. `python3 -c 'pass'` costs
  396 ms on this host, so 2 ms was never physically achievable.
- `destructive-guard.sh` — all 57 recorded runs are `hook_non_blocking_error`, stderr
  `execvpe(/bin/bash) failed: No such file or directory` (routed to WSL, which has no `/bin/bash`).

**The real root cause is worse than the decision assumed.** The guardrails hooks are not slow — they
never finish. They are killed at their declared `timeout`, and a killed PreToolUse hook yields
`outcome:"cancelled"` with no `permissionDecision`, so **the tool call proceeds unguarded**. Across
15,845 cancelled runs the fraction finishing under their declared timeout is `0.0000`. Guardrails
PreToolUse timeout rate is 94–100%; machine-wide it is 79.7%. `block-dangerous-git` enforced on ~0%
of calls.

**D-12's directive — fix the root cause, not a matcher narrowing, not a disable — is unaffected and
still binding.** Only its citation is corrected.

Two caveats: the fail-open behavior was read from the decompiled v2.1.219 binary and is **not yet
confirmed against official documentation**; and a second defect follows — **disk-hygiene's
destructive-operation guard has been silently unenforced for the entire measured window**, which
needs its own ticket and is not this effort's to fix.

Full evidence: `guardrails-latency-diagnosis.md`.

### D-13 — DEFERRED, not executed: the removal set is empty

Measured against 5,888 transcripts over 30 days — a corpus ~15× larger in file count than the one
behind the original `/doctor` pass, which makes a zero-usage finding stronger evidence, not weaker.

**No seeded plugin qualifies for removal.** All ten zero-invocation seeded plugins are
`PostToolUse` / `PreToolUse` / `Notification` hook plugins. A hook that succeeds silently writes
nothing to the transcript, so "zero usage" is the expected reading for a *correctly functioning,
heavily used* formatter. Their only skill is `setup`, invoked once at install time. Direct proof:
`guardrails` blocked three of the measuring agent's own tool calls during the run.

**Method objection.** The `/doctor` pass measured *invocation* and concluded *usage*. For hook
plugins those are unrelated quantities, and that single error accounts for ten of the sixteen.

**The stated saving does not hold either.** ~7.4k resident tokens versus a measured upper bound of
~0.9–1.1k, and likely ~0 — none of these plugins' `setup` skills appears in the session's skill
listing at all. Executing D-13 would have disabled formatting, linting, EOL normalization, desktop
notifications and the safety guard layer across every machine in exchange for approximately nothing.

**The prescribed mechanism also does not deliver the stated consequence.** `seed` writes only when a
key is absent, and every seeded plugin key already exists live, so editing the seed changes fresh
machines only — it would not have reclaimed a token on this machine. Confirmed against the installer
at `.chezmoiscripts/run_onchange_install-claude-plugins.ps1.tmpl:22-26`, which skips `false` entries
and never uninstalls.

**Status: deferred pending operator re-decision.** Nothing was committed. Any revival must classify
each plugin by **surface type** — hook versus skill/command — before treating a zero as meaningful.

### D-17 — DEFERRED, not executed: correct diagnosis, unexecutable prescription

The diagnosis is **confirmed**: `force` deep-merges with the repo value always winning
(`dot_claude/modify_settings.json:28`), and `seed` writes only when the key is absent
(`:175-182`). The silent-revert trap D-17 names is real.

**The prescribed move cannot be made.** `seed` is structurally two-level — the template ranges over
each section's entries, so every member must be a map — while `autoMemoryEnabled` is a **top-level
scalar** sibling of `model` and `env`. Reproducing the loop verbatim on chezmoi v2.70.5 yields:

```text
chezmoi: template: stdin:5:26: executing "stdin" at <$entries>: range can't iterate over false
```

That is a hard template error, not a silent no-op, and `modify_settings.json` is evaluated on every
`chezmoi apply` — so the move would **abort apply fleet-wide**, on the file carrying the permission
deny list and the destructive-removal guard.

**Status: deferred pending operator re-decision.** Delivering D-17's intent requires a root-cause fix
to the seed loop so it handles a top-level scalar; that changes merge behavior for every owned key
and is its own lane. **Urgency is low**: the live value is already `false`, so the move is a no-op on
this machine either way — D-17 was always a capability unlock, not a behavior change.

### D-6 — exclusion kept after its premise cleared

PR #1261, the reason `plugins/playbooks/skills/fable-5/**` was excluded, **merged 2026-07-25
00:38:24Z**. The operator ratified keeping the exclusion for this pass rather than lifting it
mid-fan-out. **The follow-up issue to cover that subtree afterward was not filed** — the lane
carrying it died first. Outstanding.

### D-9, D-10 — satisfied, with one permanent loss

D-9's blockers both merged (#318 at 00:08:55Z, #312 at 01:01:46Z), and `main` became #312's merge
commit, so the user-scope work was measured only after every competing writer landed. The
stacked-branch mechanism became unexecutable and was replaced by basing on `main`; the substance was
satisfied in full.

D-10's branch `docs/claude-md-github-conventions` was **already gone** from local refs and the remote
when the lane checked. The decision is satisfied — but the requirement to read its 13 lines before
dropping it could not be honored, so **that content is unrecoverable and its salvage value is
permanently unknown.** Recorded as a real loss, not a clean success.

### Corrections owed to `collision-register.md`

The register **under-counts writers** on `dot_claude/CLAUDE.md`. It lists three; **PR #319 was a
fourth**, open and editing that file mid-pass and absent from the register. It merged before
colliding. The generalizable point is the one that matters: **the register is a point-in-time
snapshot that was demonstrably incomplete while presented as complete. Re-derive from `gh pr list`
rather than trusting it.**

### Lane execution status

No lane merged. Five terminated on a session usage limit at 02:52–02:54 without reaching their own
stopping points.

| Lane | Decisions | Outcome |
|---|---|---|
| L0 | design docs | 6 commits, **not pushed**; errata and register correction unapplied |
| L1 | D-7 | **PR #1286 open**; two comments on #1271. Rewrite half unblocked by #1276 merging 02:13:33Z |
| L2 | D-4 | uncommitted work only; incumbent search must be redone (see below) |
| L3 | D-4, D-2 | uncommitted work only |
| L4 | D-12 | uncommitted work only |
| L5 | D-13, D-17 | **stopped by design**; nothing committed |
| L7 | D-9, D-10 | **dotfiles PR #321 open**, 34/34 CI green |
| L8 | D-18, D-16 | **PR #1282 open**, 26/26 CI green |
| L10 | D-11 | **PR #1280 open**, fresh-eyes verified, 8 corrections pending |

### Explicit deferrals — lanes that shipped nothing

Recorded so that no lane's status rests on an unwritten assumption. Each entry states what is
deferred, why, and the concrete trigger that unblocks it.

**L0 — design docs and contract.** Deferred with work committed but unpublished: 7 commits on
`feat/context-engineering-rightsizing`, working tree clean, branch **not pushed**, no PR. Consequence
already felt: the 13 digests are on no remote, so L2 could not point at `S2-unhobbling.md` and had to
duplicate its gate definition. **Trigger:** push the branch and open the PR, disclosing the deliberate
collision with `docs/context-engineering-claude-5-topic`. Still owed beyond that — file the D-6
fable-5 follow-up issue, and append the `#319` correction to `collision-register.md` itself, since it
currently exists only in this file.

**L2 — cross-surface conflict detector (D-4).** Deferred mid-build. Uncommitted work only:
`plugin.json`, `CHANGELOG.md` and `audit-instructions/SKILL.md` modified, plus three new untracked
files — `reference/conflict-criteria.md`, `scripts/conflict-scan.sh`, `scripts/conflict-scan.test.sh`.
**It carries a known error**: its report claims the no-incumbent result holds, but its search covered
`plugins/**/SKILL.md` only and so missed C6 for the same reason every prior search did.
**Trigger:** redo the incumbent search across `plugins/**` at all depths and file types, then rule on
reuse-versus-extension of C6 before continuing the build.

**L3 — criteria catalog (D-4, D-2).** Deferred mid-fold. Uncommitted work only, across
`plugin.json`, `CHANGELOG.md`, `README.md`, `audit-instructions/SKILL.md`, `evals/evals.json` and
`reference/criteria.md`. The fold verdict itself was independently verified sound, so the direction is
not in question. **Trigger:** none external — resume and finish.

**L4 — guardrails root-cause fix (D-12).** Deferred mid-implementation. Uncommitted work only:
`lib/hook-utils.sh` plus seven guardrails hooks. These are worktree copies, **not** the installed
plugins under `~/.claude/plugins/cache/`, so machine behavior is unchanged and the guards remain in
their current fail-open state. **Trigger:** the behavior-preservation testing the lane never reached —
each guard's verdicts captured before and after on representative payloads — plus confirmation of the
fail-open reading against official documentation. **Do not apply these edits without both.**

**Common cause.** All four terminated on a session usage limit at 02:52–02:54, not at a stopping point
of their own choosing. **Their worktrees must not be pruned**: L2, L3 and L4's work exists nowhere
else, and was deliberately left uncommitted rather than sealed behind a fabricated checkpoint.

**Verification debt.** Only L10 received the fresh-context review this effort's own D-5 requires.
PRs #1282, #321 and #1286 are unverified, and the four lanes above produced nothing to verify. That
debt is outstanding and is recorded here rather than assumed discharged.

### D-1's incumbent gate — the pass's dominant finding, and its blind spot

The gate fired hard, as this effort's own digests predicted. Its sharpest result: **D-4's criteria
catalog must fold**, because a complete incumbent already exists at
`plugins/claude-config/skills/audit-instructions/reference/criteria.md` v1.0.0, carrying exactly
D-2's three axes plus eleven seeded checks.

**But the gate itself has a demonstrated blind spot.** Three independent searches — the boundary
lane, two automated PR reviewers, and the building lane — all concluded "no incumbent" for the
conflict detector. All three were wrong: `claude-memory:audit` ships check **C6 Consistency [FAIL]**
at `plugins/claude-memory/skills/audit/reference/criteria.md:107-119`. Each search was scoped to
`SKILL.md` files or to frontmatter descriptions, and **C6 lives in a `reference/` catalog**, invisible
from the discovery surface — that skill's own `description` never mentions contradiction.

**Any future incumbent search under D-1 must cover `plugins/**` at all depths and all file types.**
Scoping to `SKILL.md` produces a false negative that looks conclusive.
