---
name: setup
description: "Configure where discovery artifacts land in this repository: interview the user and persist the tracked topic-docs concern file (.claude/topic-docs.yaml). Use when: 'set up discovery', 'configure the discovery plugin', 'discovery setup', 'where do EXPLORE.md / RESEARCH.md land', or a discovery skill reports missing or thin config. Re-runnable — safe to invoke again to reconfigure or to migrate off the deprecated notes_dir knob."
argument-hint: "(no arguments — interactive interview)"
user-invocable: true
disable-model-invocation: false
---

## Purpose

Settle the **topic-docs** seam for the consuming repo — the marketplace-wide convention for where
plugin-generated documents land. The discovery plugin writes memory-tier artifacts (`EXPLORE.md`,
`RESEARCH.md`, one `<slug>/` slice per topic) to `<memory_dir>/<slug>/`, never committed. The
consumer-side single source of truth is the tracked concern file `.claude/topic-docs.yaml`; its schema
is published in the marketplace repo at `docs/conventions/topic-docs/topic-docs.schema.json` — every
key optional, absent keys mean the documented defaults (`contract_dir: docs/topics`,
`memory_dir: .work`, `contract_tier: branch`). How the discovery skills consume what this skill
persists: [`${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md`](${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md).

Idempotent: re-running reads the current state and offers an update rather than overwriting blind.

## Task

1. **Read the current state first.** If `.claude/topic-docs.yaml` exists, report its effective values
   (absent keys = defaults); the interview proposes changes against that baseline. Then check for
   legacy state: `.claude/notes/` content on disk, and a `notes_dir` value under
   `pluginConfigs["discovery@melodic-software"].options` in any scope — **Local
   (`.claude/settings.local.json`) > Project (`.claude/settings.json`) > User
   (`~/.claude/settings.json`)**, local winning. Read each settings scope **narrowly** — query only the
   single `notes_dir` key (e.g. with `jq`), never loading `.claude/settings.local.json` wholesale: that
   overlay is secret-bearing (API tokens, env secrets), so do not read or echo unrelated settings
   content.
2. **Legacy state present → offer the guarded migration.** Until migrated, the discovery skills operate
   wholly on the old location — reads AND writes (old pins until migrated). Migration runs only on
   explicit confirmation: verify-or-create the memory root's self-ignoring `.gitignore` (containing
   `*`); move each old topic directory (`.claude/notes/<slug>/`, or `<notes_dir>/<slug>/` when the knob
   is set) to `<memory_dir>/<slug>/`, refusing to overwrite an existing target slice; then remove the
   `notes_dir` key from every settings scope that sets it. Never dual-write; never split one topic
   across roots. Emit the deprecation notice whether or not the user migrates now: `notes_dir` is
   superseded by `.claude/topic-docs.yaml` and is removed at this plugin's next major version.
3. **Infer before asking.** With no concern file, look for a working-docs convention declared in the
   repo's own `CLAUDE.md`, `AGENTS.md`, or `.claude/rules` (surface it as the recommended value — prose
   is an inference source; the concern file this skill writes is the runtime authority), or an existing
   conforming layout (`.work/` with a self-ignore, `docs/topics/`) that the proposed values would
   simply confirm.
4. **Interview — one question, recommendation first.** Present the inferred or documented defaults
   (`memory_dir: .work`, `contract_dir: docs/topics`, `contract_tier: branch` — RECOMMENDED) and let
   the user accept or edit. `contract_tier: local` is the solo/offline mode (contract kinds join the
   memory tier). Keep it to the concern file's schema keys; do not invent further options.
5. **Persist, then guard.** Write the chosen values to the tracked `.claude/topic-docs.yaml` (create or
   update; omit keys the user leaves at their defaults). Then run the conflict check:
   `git check-ignore -v` on the configured contract root — if a consumer ignore rule matches, surface
   the exact rule and stop rather than leaving an uncommittable "committed" tier configured.
   Verify-or-create the memory root's self-ignoring `.gitignore` (announce the creation). **Never edit
   the consumer's root `.gitignore`.**

## Output

A tracked `.claude/topic-docs.yaml` carrying the chosen values, plus a one-line summary of what was
written, any migration performed or deferred, and how to re-run this setup to reconfigure. Note in the
summary that the concern file governs where every discovery skill (`/discovery:explore`,
`/discovery:research`, and their `-deep` variants) lands handoff artifacts, and that legacy
`.claude/notes/<slug>` content or a set `notes_dir` keeps pinning those skills to the old location
until migrated.

## What this skill does NOT do

- Run an exploration or research pass — that is the plugin's discovery skills (`/discovery:explore`,
  `/discovery:research`, and their `-deep` variants).
- Write machine-local state — configuration lives in the consumer's tracked concern file, never in the
  plugin directory or the plugin data directory (`${CLAUDE_PLUGIN_DATA}` is for caches and generated
  state only).
- Set the deprecated `notes_dir` userConfig option — this skill only reads it, and removes it when the
  user confirms the migration.
