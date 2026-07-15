---
name: setup
description: "Configure where discovery artifacts land in this repository: interview the user and persist the tracked topic-docs concern file (.claude/topic-docs.yaml). Use when: 'set up discovery', 'configure the discovery plugin', 'discovery setup', 'where do EXPLORE.md / RESEARCH.md land', or a discovery skill reports missing or thin config. Re-runnable — safe to invoke again to reconfigure."
argument-hint: "(no arguments — interactive interview)"
user-invocable: true
disable-model-invocation: false
---

## Purpose

Settle the **topic-docs** seam for the consuming repo — the marketplace-wide convention for where
plugin-generated documents land. The discovery plugin writes memory-tier artifacts (`EXPLORE.md`,
`RESEARCH.md`, one `<slug>/` slice per topic) to `<memory_dir>/<slug>/`, never committed. The
consumer-side single source of truth is the tracked concern file `.claude/topic-docs.yaml`; its schema
is published at
<https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/conventions/topic-docs/topic-docs.schema.json> —
every key optional, absent keys mean the documented defaults (`contract_dir: docs/topics`,
`memory_dir: .work`, `contract_tier: branch`, `vault_backend: docs`). How the discovery skills consume what this skill
persists: [`${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md`](${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md).

Idempotent: re-running reads the current state and offers an update rather than overwriting blind.

## Task

1. **Read the current state first.** If `.claude/topic-docs.yaml` exists, report its effective values
   (absent keys = defaults); the interview proposes changes against that baseline.
2. **Infer before asking.** With no concern file, look for a working-docs convention declared in the
   repo's own `CLAUDE.md`, `AGENTS.md`, or `.claude/rules` (surface it as the recommended value — prose
   is an inference source; the concern file this skill writes is the runtime authority), or an existing
   conforming layout (`.work/` with a self-ignore, `docs/topics/`) that the proposed values would
   simply confirm.
3. **Interview — one question, recommendation first.** Present the inferred or documented defaults
   (`memory_dir: .work`, `contract_dir: docs/topics`, `contract_tier: branch`,
   `vault_backend: docs` — RECOMMENDED) and let the user accept or edit. `contract_tier: local` is the
   solo/offline mode (contract kinds join the memory tier); a non-`docs` `vault_backend` names a
   consumer-documented knowledge-vault backend. Offer every schema key and preserve every key an
   existing file carries — a re-run never drops one; do not invent options beyond the schema.
4. **Guard, then persist.** Run the conflict check first — only when the chosen tier is `branch`
   (local mode has no committed tier to guard): `git check-ignore -v` on a representative
   file path inside the chosen contract root (e.g. `<contract_dir>/probe/PLAN.md` — a bare directory
   misses `**` patterns) — if a consumer ignore rule matches, STOP and surface the exact rule and source line rather
   than configuring an uncommittable "committed" tier (resolving the rule is the user's edit). Only
   then write the chosen values to the tracked `.claude/topic-docs.yaml` (create or update; omit keys
   the user leaves at their defaults, but always write at least one explicit key — a comment-only
   YAML document parses as null and fails the contract schema's `type: object`). Verify-or-create
   the memory root's self-ignoring `.gitignore`
   (announce the creation). **Never edit the consumer's root `.gitignore`.**

## Output

A tracked `.claude/topic-docs.yaml` carrying the chosen values, plus a one-line summary of what was
written and how to re-run this setup to reconfigure. Note in the summary that the concern file
governs where every discovery skill (`/discovery:explore`, `/discovery:research`, and their `-deep`
variants) lands handoff artifacts.

## What this skill does NOT do

- Run an exploration or research pass — that is the plugin's discovery skills (`/discovery:explore`,
  `/discovery:research`, and their `-deep` variants).
- Write machine-local state — configuration lives in the consumer's tracked concern file, never in the
  plugin directory or the plugin data directory (`${CLAUDE_PLUGIN_DATA}` is for caches and generated
  state only).
