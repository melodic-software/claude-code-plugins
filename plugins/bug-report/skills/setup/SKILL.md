---
name: setup
description: "Configure the bug-report plugin for this repository: decide whether --file reports commit into the repo or stay in the plugin's uncommitted data directory, and persist (or clear) the output_dir userConfig option. Use when: 'set up bug-report', 'configure bug-report', 'bug-report setup', 'where do bug reports land', or you want --file reports committed alongside your code. Re-runnable — safe to invoke again to reconfigure or reset to the default."
argument-hint: "(no arguments — interactive interview)"
user-invocable: true
disable-model-invocation: false
---

## Purpose

Settle the `output_dir` seam — where `/bug-report:bug-report --file` writes reports — and persist it so the
skill resolves the location deterministically. `output_dir` is a typed `directory` `userConfig` option (seam 1
of the extensibility contract): its value lives in
`pluginConfigs["bug-report@melodic-software"].options.output_dir` and substitutes into skill content as
`${user_config.output_dir}`.

Unlike a plugin whose seam always wants a value, `output_dir` has **no default and unset is a legitimate,
recommended steady state**: when it is unset, `--file` reports land in the plugin's own persistent data
directory (`${CLAUDE_PLUGIN_DATA}/bug-reports/<project-slug>/`) — uncommitted, private to the machine.
Setting `output_dir` is an **opt-in** for teams that want bug reports committed into the repo alongside code.
So this skill's core decision is a yes/no, not a path hunt.

Idempotent: re-running reads the current value and offers to change or clear it rather than overwriting blind.

## Task

Apply the convention-resolution ladder — config present → use it; the consumer wants repo-committed reports →
infer a path and persist; the consumer wants the private default → ensure the key is absent. Absent is a valid
terminal state here; do not persist a value the user did not choose.

1. **Read the current value first, in precedence order.** Look for `output_dir` under
   `pluginConfigs["bug-report@melodic-software"].options` in all three scopes and resolve the *effective*
   value the way Claude Code does — **Local (`.claude/settings.local.json`) > Project
   (`.claude/settings.json`) > User (`~/.claude/settings.json`)**, local winning. Report the effective value
   (or "unset → reports go to the plugin data directory") and which scope supplies it; the interview proposes
   a change against that baseline. If a local override is present, say so explicitly — step 3 writes the
   *project* (team) value, which stays shadowed by the local override until the developer updates or removes
   it, so a project-scope edit alone will not change what the plugin uses on that machine. Read each scope
   **narrowly** — query only the single `pluginConfigs["bug-report@melodic-software"].options.output_dir` key
   (e.g. with `jq`), never loading `.claude/settings.local.json` wholesale: that overlay is secret-bearing
   (API tokens, env secrets), so do not read or echo unrelated settings content.
2. **Interview — one decision.** Ask whether `--file` bug reports should be **committed into this repo** or
   **kept in the plugin's private data directory (the default)**. Recommend the default (uncommitted) unless
   the repo already commits similar working artifacts — bug reports can name unfixed defects and are often
   better kept out of history until triaged. If the user chooses repo-committed, infer a sensible path before
   asking a second question:
   - A working-notes or reports convention declared in the repo's own `CLAUDE.md`, `AGENTS.md`, or
     `.claude/rules` (that declared convention wins — surface it as the recommended value).
   - An existing reports or docs directory a bug report would naturally join (e.g. `.bug-reports/`, `docs/`).
   - If nothing is found, recommend `.bug-reports/` at the repo root.

   Present the inferred path with a recommendation and let the user accept or edit it. Keep it to this single
   knob; do not invent further options (Rule of Three).
3. **Persist or clear to project scope.** Write to (or edit) the project `.claude/settings.json`:
   - **Repo-committed chosen:** set `pluginConfigs["bug-report@melodic-software"].options.output_dir` to the
     chosen value so it is tracked and shared with the team. Create the `pluginConfigs` / options path if
     absent; do not disturb unrelated keys. The value is stored verbatim (Claude Code does not normalize a
     `directory` option to absolute or validate existence), so store it exactly as it should resolve relative
     to the working directory.
   - **Default (uncommitted) chosen and a prior value exists:** **remove** the `output_dir` key so the plugin
     falls back to its data directory. Removing the last option under this plugin leaves an empty `options`
     (or `pluginConfigs` entry) — prune those empty containers too, and leave unrelated `pluginConfigs`
     entries untouched. A set-only reconfigure would trap a stale path; clearing is part of "re-runnable".
   - **Default chosen and no value exists:** nothing to write — confirm the effective behavior.
4. **Offer the personal overlay.** A per-developer override goes in the local overlay
   `.claude/settings.local.json` (same `pluginConfigs` path); recommend the consumer keep
   `.claude/settings.local.json` gitignored if it is not already.

## Output

An updated (or unchanged) project `.claude/settings.json`, plus a one-line summary of the effective
`output_dir` behavior, its scope, and how to re-run this setup to reconfigure or reset to the default. State
the concrete path `--file` will now write to.

## What this skill does NOT do

- Produce a bug report — that is `/bug-report:bug-report`. This skill only settles where `--file` writes.
- Write machine-local state — configuration lives in the consumer's tracked settings, never in the plugin
  directory or the plugin data directory (`${CLAUDE_PLUGIN_DATA}` is where reports themselves land when
  `output_dir` is unset, not where config is stored).
- Persist a value the user did not choose — unset is a valid, recommended outcome.
