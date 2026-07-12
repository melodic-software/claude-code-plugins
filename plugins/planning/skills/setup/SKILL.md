---
name: setup
description: "Configure the planning plugin for this repository: interview the user, infer a sensible artifact-landing location from the repo layout, and persist the notes_dir userConfig option. Use when: 'set up planning', 'configure the planning plugin', 'planning setup', 'where do planning artifacts land', or a planning skill reports missing or thin config. Re-runnable — safe to invoke again to reconfigure."
argument-hint: "(no arguments — interactive interview)"
user-invocable: true
---

## Purpose

Settle the `notes_dir` seam — the project-relative directory where the planning plugin's artifacts
(`PRD.md`, `PLAN.md`, design artifacts, checklists) land in the CONSUMING repo, one subdirectory per
topic — and persist it so the plugin's skills resolve it deterministically instead of re-inferring every
run. `notes_dir` is a typed `string` `userConfig` option (seam 1 of the extensibility contract): its value
lives in `pluginConfigs["planning@melodic-software"].options.notes_dir` and substitutes into skill content
as `${user_config.notes_dir}`.

Idempotent: re-running reads the current value and offers an update rather than overwriting blind.

## Task

Apply the convention-resolution ladder — config present → use it; absent → infer from the repo and persist;
cannot infer → ask and offer to persist; otherwise the safe documented default (`.claude/notes`).

1. **Read the current value first, in precedence order.** Look for `notes_dir` under
   `pluginConfigs["planning@melodic-software"].options` in all three scopes and resolve the *effective*
   value the way Claude Code does — **Local (`.claude/settings.local.json`) > Project
   (`.claude/settings.json`) > User (`~/.claude/settings.json`)**, local winning. Report the effective
   value and which scope supplies it; the interview proposes a change against that baseline. If a local
   override is present, say so explicitly — step 4 writes the *project* (team) value, which stays shadowed
   by the local override until the developer updates or removes it, so a project-scope edit alone will not
   change what the plugin actually uses on that machine. Read each scope **narrowly** — query only the
   single `pluginConfigs["planning@melodic-software"].options.notes_dir` key (e.g. with `jq`), never
   loading `.claude/settings.local.json` wholesale: that overlay is secret-bearing (API tokens, env
   secrets), so do not read or echo unrelated settings content.
2. **Infer a default before asking.** If no value is set, explore the consuming repo for an existing
   working-notes convention rather than guessing:
   - A working-notes or artifacts directory declared in the repo's own `CLAUDE.md`, `AGENTS.md`, or
     `.claude/rules` (that declared convention wins — surface it as the recommended value; the planning
     skills already honor this precedence at write time).
   - An existing notes or working-artifacts directory (`.claude/notes/`, `.work/`, `docs/planning/`) that
     PRD/PLAN/design artifacts would naturally join.
   - If nothing is found, the safe default is `.claude/notes` (the plugin's declared `userConfig` default),
     one subdirectory per topic beneath it.
3. **Interview — one decision.** Present the inferred value with a recommendation and let the user accept
   or edit it. Keep it to the single `notes_dir` knob; do not invent further options (Rule of Three — add
   a knob only when a real repeated repo-specific need surfaces).
4. **Persist to project scope.** Write the chosen value to the project `.claude/settings.json` at
   `pluginConfigs["planning@melodic-software"].options.notes_dir` so it is tracked and shared with the
   team. Create the `pluginConfigs` / options path if absent; do not disturb unrelated keys. The value is
   stored verbatim (Claude Code does not normalize a `string` option to absolute or validate existence),
   so store it exactly as the user intends it to resolve relative to their working directory.
5. **Offer the personal overlay.** A per-developer override goes in the local overlay
   `.claude/settings.local.json` (same `pluginConfigs` path); recommend the consumer keep
   `.claude/settings.local.json` gitignored if it is not already.

## Output

An updated project `.claude/settings.json` carrying `notes_dir`, plus a one-line summary of the value
written, its scope, and how to re-run this setup to reconfigure. Note in the summary that `notes_dir`
governs where the pipeline skills write their per-topic artifacts, and that a working-notes convention
declared in the consuming project's own `CLAUDE.md` or rules still takes precedence over this value at
write time.

## What this skill does NOT do

- Run a planning stage — that is the pipeline skills (`/planning:brainstorm`, `/planning:prd`,
  `/planning:interview`, `/planning:design`, `/planning:design-handoff`, `/planning:devils-advocate`,
  `/planning:architect`).
- Write machine-local state — configuration lives in the consumer's tracked settings, never in the plugin
  directory or the plugin data directory (`${CLAUDE_PLUGIN_DATA}` is for caches and generated state only).
