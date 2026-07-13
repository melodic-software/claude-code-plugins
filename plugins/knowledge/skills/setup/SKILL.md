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
   `pluginConfigs["knowledge@melodic-software"].options` and resolve the *effective* value the way Claude
   Code does — the documented order, highest first, is **Managed (system-level `managed-settings.json`
   policy) > command-line `--settings` session override > Local (`.claude/settings.local.json`) > Project
   (`.claude/settings.json`) > User (`~/.claude/settings.json`)** (see the official precedence in the
   [Claude Code settings docs](https://code.claude.com/docs/en/settings)). Inspect each layer you can
   access; a Managed policy or a session launched with `--settings` sits **above** Local and, if it supplies
   `library_dir`, wins and cannot be overridden by the project value step 5 writes — when you cannot read
   those higher layers (managed policy is often outside the repo and OS-specific), **explicitly warn that
   they were not considered** rather than declaring the lower value authoritative. Report the effective
   value and which scope supplies it; the interview proposes a change against that baseline. If a Managed
   layer or a Local override is present, say so explicitly — step 5 writes the *project* (team) value, which
   stays shadowed by any higher-precedence layer until it is updated or removed, so a project-scope edit
   alone will not change what the plugin actually uses on that machine. Read each scope **narrowly** —
   query only the single `pluginConfigs["knowledge@melodic-software"].options.library_dir` key (e.g. with
   `jq`), never loading `.claude/settings.local.json` wholesale: that overlay is secret-bearing (API tokens,
   env secrets), so do not read or echo unrelated settings content.
2. **Always check for a declared convention — even when a value is set.** `library_dir` is authoritative at
   the pipelines' write time (they resolve the persisted seam directly), so unlike a runtime-override design
   there is no silent write-to-a-different-path trap here. The risk is a different one: the plugin's intent is
   that `library_dir` *tracks* the consuming repo's own working-notes/artifacts convention (declared in its
   `CLAUDE.md`, `AGENTS.md`, or `.claude/rules`), so a stored `library_dir` that disagrees with a declared
   convention is likely a stale or accidental value — setup would carry that divergence forward as the team
   destination. So whenever a value is present, still inspect the repo for a declared convention and, if it
   conflicts with the effective value, **surface the divergence explicitly** and offer to reconcile (align
   `library_dir` to the convention, or record that the divergence is intentional). Only skip this inspection
   when the effective value already matches the declared convention (or no convention is declared).
3. **Infer a default before asking.** If no value is set, explore the consuming repo for an existing
   artifact/notes convention rather than guessing:
   - A working-notes or artifacts directory declared in the repo's own `CLAUDE.md`, `AGENTS.md`, or
     `.claude/rules` (surface that declared convention as the recommended value, so the persisted
     `library_dir` tracks it).
   - An existing docs or knowledge directory (`docs/`, `knowledge/`, `.claude/notes/`) that synthesized
     artifacts would naturally join.
   - If nothing is found, the safe default is the repo root `.` (the plugin's declared `userConfig`
     default), meaning artifacts land at the top of the consuming repo unless a skill is told otherwise.
4. **Interview — one decision.** Present the inferred value with a recommendation and let the user accept
   or edit it. Keep it to the single `library_dir` knob; do not invent further options (Rule of Three — add
   a knob only when a real repeated repo-specific need surfaces).
5. **Persist — but only a portable value, and to the scope the user intends.** The default target is the
   project `.claude/settings.json` at `pluginConfigs["knowledge@melodic-software"].options.library_dir`, so
   it is tracked and shared with the team. Two guards before writing there:
   - **Never copy a personal/session value into team settings unexamined.** If the effective baseline from
     step 1 came from a higher-precedence *personal* layer (`.claude/settings.local.json` or a `--settings`
     session file), it may be machine-specific (e.g. an absolute path under one developer's home). Do not
     propagate that verbatim into tracked `.claude/settings.json` — teammates would inherit an unusable
     path while the original machine keeps its local override. Confirm the value is **portable**
     (project-relative, no user-specific absolute segment) before a project write; if it is not, ask for a
     portable form.
   - **Match the scope to intent.** If the user only wants a personal override (not a team default), write
     to the local overlay `.claude/settings.local.json` instead and skip the project write entirely. The
     portability requirement above applies **only to the shared project write** — a local-only override is
     machine-specific by nature, so store the user's value as given there (an absolute home-directory path is
     legitimate) without rewriting it toward portability.
   Create the `pluginConfigs` / options path if absent; do not disturb unrelated keys. The value is stored
   verbatim (Claude Code does not normalize a `directory` option to absolute or validate existence), so store
   it exactly as it should resolve — the portable form for a project write, the user's given value for a
   local-only override.
6. **Confirm the overlay convention.** A per-developer override lives in the local overlay
   `.claude/settings.local.json` (same `pluginConfigs` path); recommend the consumer keep
   `.claude/settings.local.json` gitignored if it is not already.

## Output

An updated `library_dir` in the consumer's settings — the project `.claude/settings.json` by default, or the
local overlay `.claude/settings.local.json` for a personal-only override (step 5) — plus a one-line summary
of the value written, its scope, and how to re-run this setup to reconfigure. Note in the summary that
`library_dir` is the destination seam the knowledge plugin declares for where synthesized artifacts should
land, and that it is meant to track any working-notes/artifacts convention the consuming project declares in
its own `CLAUDE.md` or rules — setup keeps the two aligned. Be accurate about current reach so the user is not
misled: `/knowledge:book-distill` ignores `library_dir` (it writes to the target skill you name at
invocation), and the `/knowledge:youtube` pipeline does not yet honor a non-default `library_dir` (its work
root falls back to the consuming project root), so when a non-default value is persisted, report it as
recorded for when the pipelines consume it — not as currently relocating artifacts.

## What this skill does NOT do

- Run a distillation or ingestion — that is the plugin's pipeline skills (e.g. `/knowledge:book-distill`).
- Write machine-local state — configuration lives in the consumer's tracked settings (project
  `.claude/settings.json`, or `.claude/settings.local.json` for a personal-only override per step 5), never
  in the plugin directory or the plugin data directory (`${CLAUDE_PLUGIN_DATA}` is for caches and generated
  state only).
