---
name: unhobble
description: "Empirical bare-baseline experiment on a repo's standing instructions: reversibly strip project CLAUDE.md/rules/behavioral hooks/skills on a dedicated branch, work normally against the bare model logging observed stumbles to a ledger, then re-add ONLY instructions with repeated same-cause evidence, each restore citing its ledger rows. Measures the model where sibling audit-instructions judges the text. Use when: 'unhobble', 'run the bare experiment', 'delete my CLAUDE.md and see', 'does the model still need these instructions', 'new model dropped, re-baseline', 'instruction ablation experiment'. Human-gated mutations; resumable state."
argument-hint: "[phase] — snapshot|bare|observe|readd|status (default: guided full flow)"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: anytime
  summary: Strip instructions to a bare baseline, log real stumbles, re-add only what evidence earns
---

## Purpose

As models improve, instruction surfaces written for older models become the ceiling: the model reads
every standing line every session, and lines that correct mistakes it no longer makes cost context
and constrain behavior. Official doctrine says cut any line whose removal would not cause mistakes
([best-practices](https://code.claude.com/docs/en/best-practices)); the strongest form of that test
is empirical — delete, run, watch. This skill operationalizes the experiment its sibling
`audit-instructions` can only reason about: instead of judging instruction *text* against doctrine,
it measures the *model* against the repo with the instructions gone, and lets observed stumbles —
not guesses — decide what returns.

Rebuild rule (the whole contract in one line): **an instruction returns only after the bare model
repeatedly stumbles on the same thing, and the re-added line cites the evidence.**

## When to run

- A frontier model generation ships (the canonical trigger — instructions written for the previous
  generation are now suspect).
- The repo's instruction surface has grown past the point anyone can say which lines still earn
  their cost.
- On a cadence the operator chooses (see Cadence wiring below) — the talk-circuit heuristic is
  "every six months", but the model release is the real event.

## Scope and safety rails

- **Project scope by default.** The experiment strips the *project's* surfaces: project CLAUDE.md /
  CLAUDE.local.md, `.claude/rules/`, `.claude/skills/`, `.claude/agents/`, project-settings hooks,
  and project-enabled plugins. User-global surfaces (`~/.claude/**`) are included only when the
  operator explicitly opts in per phase-1 prompt — never by default.
- **Managed settings are never touched.** Org-managed policy is not the operator's to ablate.
- **Reversible by construction.** Tracked-file changes happen on a dedicated experiment branch;
  untracked/settings changes are backed up to plugin state before modification and restored from
  that manifest. Nothing is destroyed: git history and the snapshot manifest are the safety net.
- **Human-gated.** Every mutating step (strip, restore, re-add) presents its exact change set and
  waits for operator confirmation. Bare invocation of a phase never mutates silently.
- **Security posture is out of scope.** Hooks that enforce policy (secrets gates, PR-body contracts,
  permission guards) are classified `policy` at snapshot time and are NOT stripped by default —
  the experiment measures model capability, and policy gates are not model-era workarounds. The
  operator may force-include one explicitly; the manifest records that choice.

## State

`${CLAUDE_PLUGIN_DATA}/unhobble/<experiment-id>/` where `<experiment-id>` is
`<repo-basename>-<model-version>-<YYYYMMDD>-<nonce>` (a short random suffix minted at snapshot).
The basename is a convenience label, not the identity: `${CLAUDE_PLUGIN_DATA}` is machine-global,
so two checkouts sharing a basename (a fork, a same-named worktree) running the same model on the
same day would otherwise resolve to one directory and cross-restore each other's settings. The
manifest therefore records the canonical checkout identity — the resolved absolute worktree path
and, when a remote exists, the origin URL — and every later phase verifies it matches the current
checkout before acting; a mismatch aborts with the conflicting path named. `snapshot` never reuses
an existing experiment directory: a fresh run mints a fresh id, and resuming an open experiment
means passing its phase commands from inside the same checkout its manifest names.

- `manifest.json` — every surface found, its classification (`behavioral` | `policy` | `convention`),
  what was stripped, how to restore it (path, restore mechanism, backup location), branch name,
  target model, phase timestamps.
- `stumbles.md` — the observation ledger (one row per observed failure: date, task, what the model
  did, what was expected, suspected missing instruction, severity).
- `backups/` — pre-strip copies of any non-git-tracked file modified (e.g. settings hook entries).

`status` prints the manifest summary: phase, days elapsed, ledger row count, re-add candidates.

## Phase 1 — snapshot

1. Verify a clean working tree; refuse to start on a dirty tree or on the default branch. Create or
   confirm a dedicated branch (suggest `experiment/unhobble-<model-version>`).
2. Inventory the live project instruction surfaces (the same liveness discipline as
   `audit-instructions` Phase A, lighter: what actually loads in a session here, not what is merely
   on disk). Record line counts per surface.
3. Classify **every surface the strip plan will touch** — hooks, rules, instruction files
   (CLAUDE.md / CLAUDE.local.md, `.claude/skills/`, `.claude/agents/`), and project-enabled
   plugins alike: `policy` (enforces team/safety policy regardless of model — kept), `behavioral`
   (corrects or scaffolds model behavior — stripped), `convention` (team conventions in git —
   operator's call, default kept per the official carve-out). Classification is per unit that
   Phase 2 acts on: a hook entry, a rule file, a skill, an agent, a plugin. A **mixed** instruction
   file — a CLAUDE.md carrying both convention sections and behavioral lines is the common case —
   is not classified whole: split it in the strip plan, naming which sections are stripped and
   which are preserved (extracted to a retained file or left in place), so the convention
   carve-out holds at section granularity rather than being deleted wholesale with the file.
4. Write `manifest.json`; present the strip plan (what goes, what stays and why) and stop for
   confirmation.

## Phase 2 — bare

Apply the confirmed strip plan:

- Tracked instruction files: per the plan's per-file (and, for mixed files, per-section)
  classification — `git rm` / `git mv` a file classified behavioral whole; for a mixed file,
  remove the behavioral sections and keep the convention sections in place or in an extracted
  retained file. One commit, message
  `experiment: strip instruction surfaces for unhobble baseline`.
- Project-settings hook entries classified `behavioral`: back up the settings file to `backups/`,
  remove the entries, record the exact JSON paths removed in the manifest.
- Project-enabled plugins: record the current enabled set in the manifest, then disable the ones
  classified `behavioral` for this project (leave policy/tooling plugins the operator marked keep).
- Print the "you are bare" summary: what a fresh session will now load (ideally: nothing but the
  code) and how to restore everything (`readd` phase reads the manifest; `git` holds the files).

Start a **fresh session** after stripping — the current session already carries the old
instructions in context, so it cannot measure their absence.

## Phase 3 — observe

Work normally on real tasks for a meaningful window (days of real work, not one toy prompt). When
the model stumbles — does something an instruction used to prevent, misses a convention, breaks a
workflow — append a row to `stumbles.md`:

| Date | Task | What happened | Expected | Suspected missing instruction | Severity |

Log honestly, including surprises in the other direction (things the bare model now does *better* —
mark those `improvement`; they are the deletions proving themselves). The ledger is the experiment's
entire evidentiary output: an unlogged stumble cannot earn an instruction back, and a ledger with no
rows after real work is a licensed permanent deletion.

## Phase 4 — readd

1. Group ledger rows by suspected missing instruction. The gate: **at least two rows, same
   underlying cause.** One-off failures do not reopen a standing line — retry the task first.
2. For each group that clears the gate, restore the narrowest instruction that addresses the cause —
   a single line or rule file, not the whole pre-experiment surface — and cite the ledger rows in
   the restoring commit or an adjacent comment.
3. For instructions being rewritten rather than restored verbatim, route the text-level judgment to
   `audit-instructions` (same plugin) — it owns instruction-content-vs-doctrine analysis.
4. Everything the ledger did not defend stays deleted. Close the experiment: final manifest update
   (`phase: closed`, surfaces restored vs retired counts), and merge or fold the experiment branch
   per the repo's normal PR flow.

## Cadence wiring (optional)

The re-run trigger is the next frontier model release. To make that standing rather than
remembered: if the `work-items` plugin is installed, add a recurring item ("re-run
`/claude-config:unhobble` against the new model") rechecked on model upgrades; otherwise a note in
the repo's own conventions or a calendar reminder serves. This skill never wires a schedule itself —
scheduling surfaces vary per consumer and are the operator's choice.

## Gotchas

- **Do not run the observe phase inside this session.** Instructions already in context defeat the
  measurement; strip, then start fresh sessions for real work.
- **A plugin marketplace repo has two hats.** Running this skill in a plugin-publishing repo
  ablates that repo's *own* session surfaces only; the components it ships to consumers are its
  product, audited by their own acceptance gates, not stripped by this experiment.
- **`CLAUDE_CODE_SIMPLE=1` is not part of this contract.** The undocumented env var that strips
  Claude Code's own built-in prompts exists in the wild as an ablation experiment; it is
  undocumented and may vanish, so this skill neither sets it nor depends on it. The experiment here
  ablates *your* instructions, which is the part you own.
- **Windows:** restore paths in `manifest.json` are stored with forward slashes; git handles both.

## What this skill does NOT do

- Never strips managed settings, user-global surfaces (without explicit opt-in), or policy-classified
  hooks by default.
- Never mutates without presenting the change set and getting confirmation.
- Does not judge instruction text against doctrine — that is `audit-instructions`.
- Does not schedule its own re-runs; cadence wiring is the operator's, per above.
