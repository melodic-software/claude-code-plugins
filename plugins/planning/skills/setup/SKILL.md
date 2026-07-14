---
name: setup
description: "Configure the planning plugin for this repository: interview the user, resolve where topic documents land per the topic-docs convention, and persist the tracked concern file .claude/topic-docs.yaml. Use when: 'set up planning', 'configure the planning plugin', 'planning setup', 'where do planning artifacts land', or a planning skill reports missing or thin config. Re-runnable — safe to invoke again to reconfigure."
argument-hint: "(no arguments — interactive interview)"
user-invocable: true
---

## Purpose

Settle the topic-docs seam for the CONSUMING repo — where the planning pipeline's contract
documents (`PRD.md`, `PLAN.md`, `design/`) and working memory (checklists, baselines, scratch)
land — and persist it to the tracked concern file **`.claude/topic-docs.yaml`**, the
consumer-side single source of truth every consuming plugin resolves first. The file's shape is
the convention's `topic-docs.schema.json`; every key is optional and absent keys mean the
documented defaults (`contract_dir: docs/topics`, `memory_dir: .work`, `contract_tier: branch`,
`vault_backend: docs`).
This plugin's binding — its tier table and vault-seam close-out pointer — lives in
[`${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md`](${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md);
the contract it cites owns the resolution order and runtime guards.

Idempotent: re-running reads the current state and offers an update rather than overwriting blind.

## Task

1. **Read the current state first.** In order: an existing `.claude/topic-docs.yaml` (report its
   effective values as the baseline — the interview proposes changes against it); a working-docs
   convention declared in the consumer's `CLAUDE.md` / `.claude/rules` (an inference source —
   surface it as the recommended values and offer to persist it into the concern file).
2. **Infer before asking.** With no concern file and no declared convention, look for an existing
   conforming layout (a `docs/topics/`-shaped contract root, a self-ignoring `.work/`) and
   confirm it rather than guessing.
3. **Interview — one decision.** The load-bearing choice is `contract_tier`: **`branch`
   (RECOMMENDED)** — contract documents commit on the task branch, travel to worktrees and cloud
   clones, and are pruned before merge — vs `local` — solo/offline mode; contract kinds join the
   memory tier and the PR-description paste is the only publication surface. Keep `contract_dir`,
   `memory_dir`, and `vault_backend` at their defaults unless the repo's own conventions say
   otherwise — but offer every schema key and preserve every key an existing file carries (a
   re-run never drops one); do not invent knobs beyond the schema.
4. **Run the conflict check before writing** — only when the chosen tier is `branch` (local mode
   has no committed tier to guard). `git check-ignore -v` on a representative file path
   inside the chosen contract root (e.g. `<contract_dir>/probe/PLAN.md` — a bare directory misses
   `**` patterns): if a consumer ignore rule matches, STOP and surface the exact rule and
   source line — a "committed" tier that git ignores is the failure the guard exists to catch.
   Resolving the rule is the user's edit to make: **never modify the consumer's root
   `.gitignore`** (or any ignore file) yourself.
5. **Persist.** Write `.claude/topic-docs.yaml` (tracked, team-shared), recording only the keys
   the user chose — absent keys mean the documented defaults, so an all-defaults answer may
   yield a file with `contract_tier: branch` alone or nothing beyond a comment header. Preserve
   every schema key an existing file carries.

## Output

A written (or confirmed) `.claude/topic-docs.yaml`, plus a one-line summary of the effective
values, the conflict-check result, and how to re-run this setup to reconfigure.

## What this skill does NOT do

- Run a planning stage — that is the pipeline skills (`/planning:brainstorm`, `/planning:prd`,
  `/planning:interview`, `/planning:design`, `/planning:design-handoff`,
  `/planning:devils-advocate`, `/planning:architect`).
- Edit the consumer's root `.gitignore` or any ignore file — the conflict check surfaces rules;
  the user resolves them. (The memory root's own self-ignoring `.gitignore` is created by the
  first memory-tier write, announced — not by setup.)
- Write anything into the plugin directory or the plugin data directory
  (`${CLAUDE_PLUGIN_DATA}` is for caches and generated state only).
