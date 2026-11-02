---
description: "Verify the discovery plugin's runtime prerequisites for this session, print the gate allow rules for the operator to paste so the acceptance-gate scripts stop prompting, and write the repository's docs/conventions/discovery.yaml after confirmation. Use when: 'set up discovery', 'configure the discovery plugin', 'is discovery configured', 'discovery setup', 'the research gates keep prompting', 'set explore_output for this repo', or a discovery skill reports a missing capability. Actions: check (read-only, default), apply (writes docs/conventions/discovery.yaml only). Re-runnable."
argument-hint: "[check|apply] [<key>=<value> ...]"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Report whether this session can run the discovery plugin's dispatch design, and print the permission
rules that stop the acceptance-gate scripts prompting on every run. Artifact placement needs no
configuration: the plugin's artifact protocol
([`${CLAUDE_PLUGIN_ROOT}/reference/artifact-protocol.md`](${CLAUDE_PLUGIN_ROOT}/reference/artifact-protocol.md))
fixes where `EXPLORE.md`, `RESEARCH.md` and `INTENT.md` land, in the memory slice
`<memory_dir>/<slug>/`, never committed.

The plugin owns one tracked consumer file, `docs/conventions/discovery.yaml`, the repository layer
of its settings (keys, values and layers:
[`${CLAUDE_PLUGIN_ROOT}/reference/config.md`](${CLAUDE_PLUGIN_ROOT}/reference/config.md); schema:
`${CLAUDE_PLUGIN_ROOT}/schemas/discovery.schema.json`). `check` reports it; `apply` writes it and
nothing else. The harness rows and the operator's `~/.claude/settings.json` are reported only, never
written. Action routing: no argument or `check` runs the check; `apply` runs the check, then
writes. Re-running either reads the current state again.

## `check` (read-only)

Report a PASS/INFO/WARN table. Do not write anything. No row is ever a FAIL or a blocker.

1. **Dispatch capability.** `/discovery:explore` and `/discovery:research` dispatch a subagent by
   default, and that posture degrades rather than breaks on a session that cannot support all of it.
   Report these as PASS/INFO rows:
   - **Harness version against the 2.1.219 floor** (`claude --version`). Below it, several behaviors
     the dispatch design relies on are false rather than merely absent: background became the default
     subagent execution mode in **2.1.198**, and below **2.1.218** a `context: fork` skill always
     blocked the invoking turn and the narrow background tool set did not apply to it. The dated
     record for background as the default is
     [`${CLAUDE_PLUGIN_ROOT}/reference/parent-contract.md`](${CLAUDE_PLUGIN_ROOT}/reference/parent-contract.md),
     "Harness facts the dispatch design rests on". Report the
     observed version and, when it is under the floor, name which of those the session does not have.
     The skills still run, inline is always available, so this is INFO, not FAIL.
   - **`CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH`**. Report the value, present or absent, and say what
     the running harness does with it rather than assuming. Read absent against the observed
     version, in four windows: below **2.1.172** nesting does not exist and the variable buys
     nothing; **2.1.172** to **2.1.216** absent means available at a fixed five; **2.1.217** to
     **2.1.218** absent means *off*, and setting the variable is the only way to turn nesting on;
     **2.1.219** and later absent means available at a configurable default of three, and the
     variable lowers the ceiling (`"1"` disables nesting) as readily as it raises one. For the
     current default and the variable's version history, see
     [Let subagents spawn their own subagents](https://code.claude.com/docs/en/sub-agents#let-subagents-spawn-their-own-subagents)
     and the variable's row in [env vars](https://code.claude.com/docs/en/env-vars). As of
     2026-10-02; recheck when the default or the version history changes.
     Report absent as INFO in every window: nesting buys
     **throughput**, not coverage, without it a dispatched agent fans out sequentially, slower for
     the same result. The variable is still only one of **two** conditions: it cannot add a tool an
     agent definition left out. The shipped `discovery:explorer` / `discovery:researcher` definitions
     list `Agent` for exactly this reason; a third-party agent that does not is unaffected by setting
     it. It is not a correctness prerequisite here, because the one control that needs a context
     which has not seen the work is the outcome-gate verifier, and the parent dispatches that as a
     **sibling** rather than the agent as a child. Note that a shell env var is read at session start,
     so a value exported now takes effect next session. Whether a settings-file `env` value reaches
     a running session is
     [env vars: set variables in settings files](https://code.claude.com/docs/en/env-vars#set-variables-in-settings-files)'s
     to state. As of 2026-11-01; recheck when that section changes what a running session picks up.
   - **Fork availability.** Report it as a control, not a gate. Report `CLAUDE_CODE_FORK_SUBAGENT`
     when set; when unset, read the default for the observed version and session kind (interactive,
     `claude -p`, the SDK) from the pointer below and report that, never one remembered here. A
     default is not a runtime guarantee, so the only authoritative probe is still a live
     inheritance check (see `discipline:sweep-all`'s preflight); never claim forks are
     unconditionally available on every build. The user-facing command is `/subtask` as of
     **2.1.212**.
     - **Pointer**: [Turn fork mode off](https://code.claude.com/docs/en/sub-agents#turn-fork-mode-on-or-off)
       for the default and the versions it changed in, and the variable's row in
       [env vars](https://code.claude.com/docs/en/env-vars) for what each value does.
     - **As of**: 2026-11-01
     - **Recheck trigger**: that section states a different default or version, or a release note
       names fork mode.
2. **Gate allow rules.** The acceptance-gate scripts prompt on every run unless the operator's
   `~/.claude/settings.json` allows them. Read its `permissions.allow` (a missing file or key reads
   as no rules; read only, never write) and compare it with these eight rules for this install root:

   ```text
   Bash("${CLAUDE_PLUGIN_ROOT}/scripts/check-dispatch-artifact.sh" *)
   Bash("${CLAUDE_PLUGIN_ROOT}/scripts/check-coverage-complete.sh" *)
   Bash("${CLAUDE_PLUGIN_ROOT}/scripts/check-source-applicability.py" *)
   Bash("${CLAUDE_PLUGIN_ROOT}/scripts/check-restatement-labels.py" *)
   Bash(${CLAUDE_PLUGIN_ROOT}/scripts/check-dispatch-artifact.sh *)
   Bash(${CLAUDE_PLUGIN_ROOT}/scripts/check-coverage-complete.sh *)
   Bash(${CLAUDE_PLUGIN_ROOT}/scripts/check-source-applicability.py *)
   Bash(${CLAUDE_PLUGIN_ROOT}/scripts/check-restatement-labels.py *)
   ```

   Report one row, **never FAIL**: PASS when all eight are present for this install root; INFO "stale"
   when gate rules name a different `…/scripts/check-*` root (an earlier version's cache directory,
   which stops matching after an update), naming that root; INFO "absent" otherwise. On stale or
   absent, print the eight rules resolved to this install root and ready to paste, each as a JSON
   string for `permissions.allow` (the quoted forms escape their inner `"`). Applying them is the
   operator's job: this skill never writes user settings. The rules pin this version's cache
   directory on purpose, so a plugin update invalidates them and `check` reports them "stale" again;
   why a version wildcard is unsafe is in
   [`${CLAUDE_PLUGIN_ROOT}/reference/parent-contract.md`](${CLAUDE_PLUGIN_ROOT}/reference/parent-contract.md)
   ("Operator setup").
3. **Repository settings.** Run
   `"${CLAUDE_SKILL_DIR}/scripts/setup-apply.mjs" --check` from the project root and report each
   line it prints with its own INFO, PASS or WARN prefix. INFO when
   `docs/conventions/discovery.yaml` is absent (every key comes from `userConfig` or its default);
   PASS with each key's value when the file validates; WARN when it does not (a value outside the
   key's list, a key set twice, an empty value or empty string, or a map or list where one string
   belongs), quoting the file, key and value. An invalid value never stops a discovery skill: the
   skill names it and drops that layer, so the row is a WARN. `apply` fixes a value outside the list
   or an empty value; the other shapes are fixed by hand, and `apply` refuses the file until then.

## `apply` (writes `docs/conventions/discovery.yaml` only)

1. Run `check` and show its table.
2. **Resolve the values.** With complete `<key>=<value>` arguments, use them. Otherwise ask one key
   at a time, recommendation first, from the Keys table in `${CLAUDE_PLUGIN_ROOT}/reference/config.md`
   (`explore_output`: `auto`, the default, unless the team wants every run pinned to `change-prep`
   or `explain`). Never invent a key the schema does not list.
3. **Write.** One call with every value:

   ```bash
   "${CLAUDE_SKILL_DIR}/scripts/setup-apply.mjs" explore_output=explain
   ```

   Pass a key the operator accepts at the plugin default as `--default <key>` instead of
   `<key>=<value>`, so a later change to that default reaches it; `<key>=<value>` records the
   team's choice, which the script never changes. The script also records `written_against` and
   `provenance:`, so a file with no record, or one written against another plugin version, shows a
   diff even when no value changes.

   The script checks each value against the schema and validates the whole resulting document
   before it writes; an invalid value or key, or an existing file with a key set twice, an empty
   string, a map or a list, exits 1 with one line and writes nothing. It writes only
   `<git toplevel>/docs/conventions/discovery.yaml`. It resolves a symlinked root first, then
   refuses a root that is `$HOME` or an ancestor of it, a symlinked `docs`, `docs/conventions` or
   target, a hard-linked target, or a `docs/conventions` that resolves outside the repository,
   checked again right before the
   write, so nothing lands outside `docs/conventions/`. A missing file is created. A value already in place prints
   `already configured` and writes nothing.
4. **An existing file that would change** exits 3 and prints a unified diff without writing. Show
   the operator that diff and ask whether to write it. Only on an explicit yes, re-run the same
   call with `--yes`; on anything else, stop with the file unchanged. A request to "set it" is not
   a yes to a diff the operator has not seen.
   When the convention-home offer prints below the diff, ask about it too (the next step) before
   any re-run, since `--yes` writes both.
5. **The convention-home offer.** When the repository's `AGENTS.md` or `CLAUDE.md` binds no
   convention home, the script prints an offer: with the operator's confirmation it adds a
   convention-home pointer region to that instruction file (creating `AGENTS.md` when neither
   exists or `CLAUDE.md` only imports it) and the overlay ignore line
   `docs/conventions/**/*.local.*` to `.gitignore`, the only files `apply` writes outside
   `docs/conventions/`. It prints the offer at the end of an exit 0 run and below the diff of an
   exit 3 run, so show the operator stdout on exit 0 too. Ask whether to add the region and the
   ignore line. Only on an explicit yes, re-run the same call with `--yes`, which also writes any
   diff shown with it. On a no, run `"${CLAUDE_SKILL_DIR}/scripts/setup-apply.mjs" --decline`
   alone: it records the decline in the instruction file, and the next run does not offer again.
   To write a shown diff without the region, run `--decline` first, then the same call with
   `--yes`. When the instruction file or `.gitignore` is a symlink or hard link the script will
   not write through, it prints a one-line refusal in place of the offer, with the same exit
   code: show it, and do not re-run with `--yes`, which that refusal stops with exit 1. A refused
   instruction file refuses `--decline` too, so the operator fixes the link or adds the region by
   hand.
6. **Verify.** Re-run `check` and report the value from its table, not from the write. Then the
   tracked-file pair: `git check-ignore -v docs/conventions/discovery.yaml` reports no match (a
   match means the team never receives the file: say so, and leave `.gitignore` to the operator),
   and `git ls-files --error-unmatch docs/conventions/discovery.yaml` exits 0. Non-zero right after
   a fresh write means "written but untracked: commit it to share with the team", never success.

## Output

`check`: the table and, when the gate allow rules are stale or absent, the eight resolved rules as
JSON strings ready to paste. `apply`: the table before and after, the diff when one was shown, the
written path, and whether the file is tracked.

## Next

`/discovery:explore`

## Gotchas

- **Shell env vars are read at session start.** A capability the check reports as missing stays
  missing for the rest of this session even after it is exported in the shell; the recommendation
  takes effect next session. Whether a variable set in a settings file's `env` applies now is
  [env vars: set variables in settings files](https://code.claude.com/docs/en/env-vars#set-variables-in-settings-files)'s
  to state (as of 2026-11-01; recheck when that section changes).
- **The gate allow rules stop matching after a plugin update.** They name this version's cache
  directory, so the gates prompt again until the operator pastes the rules `check` prints; `check`
  reports them "stale".
- **The repository file reaches the team only once committed.** `apply` leaves it uncommitted on
  purpose, and the tracked-file pair says so.

## What this skill does NOT do

- Run an exploration, research, or intent-tracing pass. Those are the plugin's discovery skills
  (`/discovery:explore`, `/discovery:research`, `/discovery:trace-intent`).
- Write machine-local state. The plugin directory and the plugin data directory
  (`${CLAUDE_PLUGIN_DATA}`, for caches and generated state only) stay untouched.
- Write Claude Code user settings or `pluginConfigs`. `check` reads `~/.claude/settings.json` and
  prints the gate allow rules; the operator applies them.
- Write any file other than `docs/conventions/discovery.yaml`, or edit the consumer's `.gitignore`.
