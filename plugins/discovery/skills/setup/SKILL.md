---
name: setup
description: "Verify or configure where discovery artifacts land in this repository: report the effective topic-docs concern, or persist it to the tracked .claude/topic-docs.yaml. Use when: 'set up discovery', 'configure the discovery plugin', 'is discovery configured', 'discovery setup', 'where do EXPLORE.md / RESEARCH.md land', or a discovery skill reports missing or thin config. Actions: check (read-only, default) | apply (persist the concern file). Re-runnable — safe to invoke again."
argument-hint: "check | apply [<key>=<value> ...]"
user-invocable: true
disable-model-invocation: true
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

Check-centric per the uniform contract: `check` inspects and reports, `apply` persists. Idempotent:
re-running reads the current state and offers an update rather than overwriting blind.

Action routing: no argument or `check` runs the check; `apply` runs the check first, then persists.
`apply` is non-interactive when complete `<key>=<value>` arguments are supplied
(`memory_dir=`, `contract_dir=`, `contract_tier=`, `vault_backend=`) — automation and headless use
pass the full set and are never prompted. With incomplete arguments, `apply` interviews one question
at a time, recommendation first.

## `check` (read-only)

Report the effective concern and the guard result as a PASS/FAIL/INFO table. Do not write anything.

1. **Current state.** If `.claude/topic-docs.yaml` exists, report its effective values (absent keys =
   defaults). If it does not exist, INFO: the plugin runs on the documented defaults; `apply` persists
   an explicit concern only if the consumer wants different values.
2. **Inferred convention.** Look for a working-docs convention declared in the repo's own `CLAUDE.md`,
   `AGENTS.md`, or `.claude/rules`, or an existing conforming layout (`.work/` with a self-ignore,
   `docs/topics/`). Surface it as INFO — prose is an inference source; the concern file is the runtime
   authority.
3. **Committed-tier guard.** Only when the effective `contract_tier` is `branch` (local mode has no
   committed tier to guard): run `git check-ignore -v` on a representative file path inside the
   contract root (e.g. `<contract_dir>/probe/PLAN.md` — a bare directory misses `**` patterns). FAIL
   if a consumer ignore rule matches — an uncommittable "committed" tier — and surface the exact rule
   and source line. Resolving the rule is the consumer's edit.
4. **Deferred backend.** If the effective `vault_backend` is `gitbook`, INFO: it is reserved but not
   enabled — git remains the storage layer because GitBook offers no concurrency-safe,
   lossless write path — so it is deferred and non-writable; durable writes still target `docs` until
   a later reviewed decision enables it.

## `apply` (idempotent)

Run `check`, then persist the chosen values. Re-running with the current values changes nothing and
reports "already configured".

1. **Resolve the values.** With complete `<key>=<value>` arguments, use them directly (non-interactive).
   Otherwise interview one question at a time, recommendation first: present the inferred or documented
   defaults (`memory_dir: .work`, `contract_dir: docs/topics`, `contract_tier: branch`,
   `vault_backend: docs` — RECOMMENDED) and let the user accept or edit. `contract_tier: local` is the
   solo/offline mode (contract kinds join the memory tier); a non-`docs` `vault_backend` names a
   consumer-documented knowledge-vault backend. Offer every schema key and preserve every key an
   existing file carries — a re-run never drops one; do not invent options beyond the schema. `gitbook`
   is reserved but not enabled as a `vault_backend` value — git remains the storage layer because
   GitBook offers no concurrency-safe, lossless write path. When offering or preserving it, report
   that it is deferred and non-writable — durable writes still target `docs` — and never configure or
   test a GitBook API, MCP, or Git Sync writer; offer to replace the key with `docs` only if the user
   chooses that change.
2. **Guard, then persist.** Re-run the committed-tier guard from `check` for the chosen tier; if a
   consumer ignore rule matches, STOP and surface the exact rule and source line rather than
   configuring an uncommittable "committed" tier. Only then write the chosen values to the tracked
   `.claude/topic-docs.yaml` (create or update; omit keys the user leaves at their defaults, but always
   write at least one explicit key — a comment-only YAML document parses as null and fails the contract
   schema's `type: object`). Verify-or-create the memory root's self-ignoring `.gitignore` (announce the
   creation). **Never edit the consumer's root `.gitignore`.**
3. **Verify.** Re-read `.claude/topic-docs.yaml` and report its effective values — never claim
   persisted on the write alone.

## Output

A tracked `.claude/topic-docs.yaml` carrying the chosen values, plus a one-line summary of what was
written and how to re-run this setup to reconfigure. Note in the summary that the concern file governs
where every discovery skill (`/discovery:explore`, `/discovery:research`, and their `-deep` variants)
lands handoff artifacts.

## What this skill does NOT do

- Run an exploration or research pass — that is the plugin's discovery skills (`/discovery:explore`,
  `/discovery:research`, and their `-deep` variants).
- Write machine-local state — configuration lives in the consumer's tracked concern file, never in the
  plugin directory or the plugin data directory (`${CLAUDE_PLUGIN_DATA}` is for caches and generated
  state only).
- Write Claude Code user settings or `pluginConfigs`.
