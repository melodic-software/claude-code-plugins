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

1. **Read the current value first, across every scope, in precedence order.** Look for `output_dir` under
   `pluginConfigs["bug-report@melodic-software"].options` and resolve the *effective* value the way Claude
   Code does — the full precedence, highest wins:
   1. **Managed** (system `managed-settings.json`) — **read-only** to this skill.
   2. **Command-line** (a session launched with `--settings`) — **read-only**; a transient session override.
   3. **Local** (`.claude/settings.local.json`).
   4. **Project** (`.claude/settings.json`).
   5. **User** (`~/.claude/settings.json`).

   Report the effective value (or "unset → reports go to the plugin data directory") and which scope supplies
   it; the interview proposes a change against that baseline. Two consequences of the full ladder that a
   Local > Project > User model misses:
   - **A higher scope shadows a write.** Step 3 writes the *project* (team) value, but a Managed,
     command-line, or Local value above it will keep winning until that scope is changed or removed. When one
     is present, say so explicitly — a project-scope edit alone will not change what the plugin uses in that
     session. **Managed and command-line are read-only here** (a plugin setup cannot edit system policy or a
     session's CLI flags): if either supplies the effective value, report it as a hard blocker and do not
     claim any write or clear will change the `--file` destination.
   - **A lower scope can be revealed.** Because more than one scope may hold `output_dir` at once, note every
     scope that carries a value, not just the winning one — step 3's reset needs the full set.

   Read each scope **narrowly** — query only the single
   `pluginConfigs["bug-report@melodic-software"].options.output_dir` key (e.g. with `jq`), never loading
   `.claude/settings.local.json` (or any settings file) wholesale: that overlay is secret-bearing (API
   tokens, env secrets), so do not read or echo unrelated settings content.
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
3. **Persist or clear.** The *set* path writes the project scope; the *clear* path may span scopes:
   - **Repo-committed chosen:** set `pluginConfigs["bug-report@melodic-software"].options.output_dir` in the
     project `.claude/settings.json` to the chosen value so it is tracked and shared with the team. Create the
     `pluginConfigs` / options path if
     absent; do not disturb unrelated keys. The value is stored verbatim (Claude Code does not normalize a
     `directory` option to absolute or validate existence), so store it exactly as it should resolve relative
     to the working directory.
   - **Default (uncommitted) chosen and a prior value exists:** reaching the plugin-data default means **no
     scope may hold `output_dir`** — clearing only the winning scope just reveals the next value down. Using
     the full set of value-carrying scopes from step 1:
     - **A read-only scope (Managed or command-line) holds a value** → it cannot be cleared here. Report that
       the private default is unreachable until the administrator changes the managed policy (or the session
       drops the `--settings` override), and stop — do not pretend a writable-scope edit resets it.
     - **Otherwise clear every *writable* scope that carries a value** — Local (`.claude/settings.local.json`)
       and Project (`.claude/settings.json`) directly; User (`~/.claude/settings.json`) only with the
       developer's **explicit consent**, since it is their global config. For each, remove the single
       `output_dir` key and prune the emptied `options` / `pluginConfigs` containers, leaving unrelated
       entries untouched. Only when no writable scope holds a value does the plugin fall back to its data
       directory.
     - **If the user declines to clear their user-scope value**, tell them plainly that the repo will keep
       resolving that global value and name the file to edit. Never silently edit a user's global settings.

     A set-only reconfigure would trap a stale path; scope-complete clearing is part of "re-runnable".
   - **Default chosen and no value exists:** nothing to write — confirm the effective behavior.
4. **Offer the personal overlay.** A per-developer override goes in the local overlay
   `.claude/settings.local.json` (same `pluginConfigs` path); recommend the consumer keep
   `.claude/settings.local.json` gitignored if it is not already.

## Output

An updated (or unchanged) settings file in the appropriate scope(s) — project for a set, and whichever
writable scopes carried a value for a reset — plus a one-line summary of the effective `output_dir` behavior,
its scope, and how to re-run this setup to reconfigure or reset to the default. State the concrete path
`--file` will now write to.

## What this skill does NOT do

- Produce a bug report — that is `/bug-report:bug-report`. This skill only settles where `--file` writes.
- Store config in the plugin — the value lives in the consumer's Claude Code settings, never in the plugin
  directory or the plugin data directory (`${CLAUDE_PLUGIN_DATA}` is where reports themselves land when
  `output_dir` is unset, not where config is stored). The **set** path always writes the project (tracked,
  team) `.claude/settings.json`. The **reset** path is the one exception that may touch a machine-local scope
  — and only to remove a value the user asked to clear: it clears `.claude/settings.local.json` when the local
  overlay carries a value, or `~/.claude/settings.json` with explicit consent when user scope does, because a
  project-scope edit cannot reach either. It never edits read-only Managed or command-line scopes, and never
  writes machine-local state the plugin itself owns.
- Persist a value the user did not choose — unset is a valid, recommended outcome.
