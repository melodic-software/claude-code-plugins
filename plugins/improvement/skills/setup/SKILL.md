---
description: "Verify and configure the improvement plugin for this repository. check (default) inspects the .claude/improvement.md config cascade read-only across all three layers — user-global, team, local overlay — and reports the effective evidence-source configuration: which layers exist, what churn window and exclusion patterns resolve, and which Tier 2 MCP telemetry sources are declared. apply interviews the user and writes the team file. Zero config is a valid state — Tier 0 evidence needs nothing configured. Use when: 'set up improvement', 'configure improvement', 'is improvement configured', 'improvement setup', 'declare a telemetry source for the improvement finder', 'tune churn exclusions', or /improvement:find reports Tier 2 as an evidence gap you want closed. Re-runnable — safe to invoke again to reconfigure."
argument-hint: "check | apply"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Verify and manage the consuming repo's tracked evidence-source config at
`.claude/improvement.md`, so `/improvement:find` resolves Tier 2 telemetry sources and churn
tuning from a declared contract instead of having nothing to consult.

The config is optional in every layer: with none, the finder runs fully on Tier 0 repo-native
evidence with the bundled churn defaults, and Tier 2 is a recorded evidence gap — so total
absence is a reported INFO, never a FAIL. The key contract, layer paths, and merge semantics
live in `${CLAUDE_PLUGIN_ROOT}/reference/config.md` (the single home — this skill implements
that contract and does not restate it).

## Actions

Two actions only. No argument or `check` runs the read-only check; `apply` runs the check first,
then the interview-and-write flow. Any other argument is an error naming these two actions.

## The config cascade

Three layers, resolved user-global (`~/.claude/improvement.md`) → team
(`.claude/improvement.md`, tracked) → local overlay (`.claude/improvement.local.md`,
gitignored), merged per the semantics declared in
`${CLAUDE_PLUGIN_ROOT}/reference/config.md`: per-key override for scalars, union for
`churn_exclude`, per-source-name merge for `evidence_sources` with an empty-body opt-out. This
skill writes only the **team** file; changes to the user-global layer or the overlay are the
user's to make. Anchor every repo-relative read at the repo root (`${CLAUDE_PROJECT_DIR}` when
set, otherwise `git rev-parse --show-toplevel`), never at the CWD.

## `check` (read-only)

Inspect the effective merged config and report a PASS/FAIL/INFO table with one remediation line
per FAIL. Modify nothing, and do NOT run a scan — that is `/improvement:find`.

1. **Layer presence.** Load every layer you can access and report which exist. All absent →
   INFO: the finder uses bundled defaults and records Tier 2 as an evidence gap; `apply` writes
   `.claude/improvement.md` to declare sources. When a layer outside the repo (the user-global
   base) cannot be read, WARN it was not considered rather than presenting the readable layers
   as the whole effective config.
2. **Effective configuration.** Report the merged result and which layer supplied each value:
   the effective `churn_window`, whether bundled exclusion defaults are on, declared
   `churn_exclude` additions, and every `evidence_sources` entry (name, `mcp_server`, `kind`,
   scope) — including entries a later layer opted out, reported as removed, not broken. A
   malformed layer degrades soft: name it, resolve as if absent, report the parse error.
3. **Key validity.** Each `evidence_sources` entry names an `mcp_server`; an entry missing it is
   FAIL, naming the entry. Where the session can enumerate available MCP servers, note (INFO)
   any declared server not currently available — at find-time that source becomes an
   evidence-gap line, which may be expected on this machine.
4. **Tracked, not ignored.** A present team file must be committed to be team-shared, and
   "not ignored" is not "tracked" — probe both: `git check-ignore -v .claude/improvement.md`
   (non-empty result is FAIL with the matching pattern) AND
   `git ls-files --error-unmatch .claude/improvement.md` (non-zero exit is FAIL: the file is
   present but untracked — the state immediately after `apply` writes it — so teammates will not
   receive it until it is committed; report "untracked, commit it" and, if it is staged but
   uncommitted, say that instead via `git diff --cached --name-only`). The `.local.md` overlay is
   expected to be gitignored — an overlay that is tracked or staged is FAIL (a personal deviation
   can reach team history); an ignored overlay is INFO.
5. **Overlay divergence.** INFO: when the overlay or user-global layer changes the team file's
   effect (a different window, extra exclusions, an added or opted-out source), say so
   explicitly, since `apply` writes only the team file.

## `apply` (idempotent)

Run `check`, then interview and write the team file. Proceed non-interactively where the
invocation and the repo make values unambiguous; ask only where a value genuinely needs the
user.

1. **Read the effective config first, across all layers**, and present the merged baseline with
   per-layer provenance — exactly as `check` step 2 reports it. When a higher layer's opt-out or
   override shapes the effective result, warn that editing the team file alone will not change
   what this machine resolves, and point at the owning layer. Nothing is dropped without the
   user confirming.
2. **Draft defaults from the repo.** Before asking: propose `churn_exclude` additions from what
   actually exists (generated/build output trees, snapshot or designer files not covered by the
   bundled defaults); keep `churn_window` at the bundled default unless the repo's history is
   young or the user says otherwise; and draft `evidence_sources` candidates from the MCP
   servers the consumer has configured that plausibly carry telemetry — a candidate is a
   proposal for the user to confirm, never an assumption. No plausible source and none volunteered
   is a fine outcome: write the churn keys only, and say Tier 2 stays a declared gap.
3. **Interview, one decision at a time**: window, exclusions, then each telemetry source (name,
   `mcp_server`, `kind`, scope, hints) with a recommendation the user accepts, edits, or
   declines.
4. **Write the team file** in the file format defined by
   `${CLAUDE_PLUGIN_ROOT}/reference/config.md` — a fenced YAML block holding only the keys the
   user confirmed. Never write a vendor-specific default the user did not declare.
5. **Verify after writing.** Re-run the `check` probes on the written file — BOTH
   `git check-ignore -v .claude/improvement.md` (surface a matching pattern and offer a
   `.gitignore` fix) AND `git ls-files --error-unmatch .claude/improvement.md` (non-zero exit
   means the file is un-ignored but still untracked — the guaranteed state right after this
   step writes it — so report "written but untracked: commit it to share with the team", never
   success). Then offer the overlay
   convention: personal overrides go in `.claude/improvement.local.md`; recommend the consumer
   add the recursive `.claude/**/*.local.*` line to `.gitignore` if not already covered — but
   never edit their `.gitignore` yourself.

Re-running `apply` after everything passes changes nothing and reports "already configured".

## Output

`check`: the PASS/FAIL/INFO table plus the effective evidence-source configuration with
per-layer provenance. `apply`: a tracked `.claude/improvement.md`, the re-run check result, and
one paragraph on what was written and how to re-run this setup to reconfigure.

## What this skill does NOT do

- Run an improvement scan — that is `/improvement:find`; `check` only inspects config.
- Install or configure MCP servers — it declares which configured server carries telemetry;
  provisioning the server is the consumer's own MCP setup.
- Write the user-global layer, the `.local.md` overlay, or the consumer's `.gitignore` — team
  file only; everything else is recommended, not written.
- Write machine-local state — configuration lives in the consumer's tracked file, never in the
  plugin directory or the plugin data directory.

## Gotchas

- **All layers absent is healthy.** Tier 0 evidence needs no config; do not manufacture a FAIL
  (or a config file) for a repo that has not opted into Tier 2 or churn tuning.
- **CWD is not the repo root.** Invoked from a subdirectory, a CWD-relative read finds a
  nonexistent `<subdir>/.claude/improvement.md` and silently reports an absent config — anchor
  at the root in every self-contained shell call.
- **The team file is the only thing `apply` writes.** An effective value contributed by the
  overlay or user-global layer cannot be changed here; say which layer owns it instead of
  writing a team value that the higher layer will keep overriding.
- **No git verdict on the user-global layer.** `git check-ignore` against a path outside the
  worktree is meaningless (or confidently wrong when the home directory is itself a repo) —
  the tracked/ignored probes apply to the two in-repo layers only.
