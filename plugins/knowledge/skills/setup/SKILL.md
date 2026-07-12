---
name: setup
description: "Configure the knowledge plugin for this repository: interview the user, infer a sensible artifact-landing location from the repo layout, and persist the library_dir userConfig option. Use when: 'set up knowledge', 'configure the knowledge plugin', 'knowledge setup', 'where do knowledge artifacts land', or a knowledge skill reports missing or thin config. Re-runnable — safe to invoke again to reconfigure."
argument-hint: "(no arguments — interactive interview)"
user-invocable: true
---

## Purpose

Settle the `library_dir` seam — the project-relative directory where the knowledge plugin's synthesized
artifacts land in the CONSUMING repo — and persist it so the plugin's skills resolve it deterministically
instead of re-inferring every run. `library_dir` is a typed `directory` `userConfig` option (seam 1 of the
extensibility contract): its value lives in `pluginConfigs["knowledge@melodic-software"].options.library_dir`
and substitutes into skill content as `${user_config.library_dir}`.

Idempotent: re-running reads the current value and offers an update rather than overwriting blind.

## Task

Apply the convention-resolution ladder — config present → use it; absent → infer from the repo and persist;
cannot infer → ask and offer to persist; otherwise a safe generic default (repo root `.`).

1. **Read the current value first, in precedence order.** Look for `library_dir` under
   `pluginConfigs["knowledge@melodic-software"].options` in all three scopes and resolve the *effective*
   value the way Claude Code does — **Local (`.claude/settings.local.json`) > Project
   (`.claude/settings.json`) > User (`~/.claude/settings.json`)**, local winning. Report the effective
   value and which scope supplies it; the interview proposes a change against that baseline. If a local
   override is present, say so explicitly — step 4 writes the *project* (team) value, which stays shadowed
   by the local override until the developer updates or removes it, so a project-scope edit alone will not
   change what the plugin actually uses on that machine.
2. **Infer a default before asking.** If no value is set, explore the consuming repo for an existing
   artifact/notes convention rather than guessing:
   - A working-notes or artifacts directory declared in the repo's own `CLAUDE.md`, `AGENTS.md`, or
     `.claude/rules` (that declared convention wins — surface it as the recommended value).
   - An existing docs or knowledge directory (`docs/`, `knowledge/`, `.claude/notes/`) that synthesized
     artifacts would naturally join.
   - If nothing is found, the safe default is the repo root `.` (the plugin's declared `userConfig`
     default), meaning artifacts land at the top of the consuming repo unless a skill is told otherwise.
3. **Interview — one decision.** Present the inferred value with a recommendation and let the user accept
   or edit it. Keep it to the single `library_dir` knob; do not invent further options (Rule of Three — add
   a knob only when a real repeated repo-specific need surfaces).
4. **Persist to project scope.** Write the chosen value to the project `.claude/settings.json` at
   `pluginConfigs["knowledge@melodic-software"].options.library_dir` so it is tracked and shared with the
   team. Create the `pluginConfigs` / options path if absent; do not disturb unrelated keys. The value is
   stored verbatim (Claude Code does not normalize a `directory` option to absolute or validate existence),
   so store it exactly as the user intends it to resolve relative to their working directory.
5. **Offer the personal overlay.** A per-developer override goes in the local overlay
   `.claude/settings.local.json` (same `pluginConfigs` path); recommend the consumer keep
   `.claude/settings.local.json` gitignored if it is not already.

## Output

An updated project `.claude/settings.json` carrying `library_dir`, plus a one-line summary of the value
written, its scope, and how to re-run this setup to reconfigure. Note in the summary that `library_dir`
governs where the plugin's ingestion pipelines land synthesized artifacts — `/knowledge:book-distill`
is unaffected, since it always writes to the target skill you name at invocation.

## What this skill does NOT do

- Run a distillation or ingestion — that is the plugin's pipeline skills (e.g. `/knowledge:book-distill`).
- Write machine-local state — configuration lives in the consumer's tracked settings, never in the plugin
  directory or the plugin data directory (`${CLAUDE_PLUGIN_DATA}` is for caches and generated state only).
