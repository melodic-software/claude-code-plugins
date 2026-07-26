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
consumer-side single source of truth is the tracked concern file `.claude/topic-docs.yaml`; its shape is
the convention's `topic-docs.schema.json` — every key optional, absent keys mean the documented defaults
(`contract_dir: docs/topics`, `memory_dir: .work`, `contract_tier: branch`, `vault_backend: docs`). This
plugin's binding — how the discovery skills consume what this skill persists, and the pointer to the
published convention that owns the schema — lives in
[`${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md`](${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md).

<!-- Maintainer note: the rules below restate the topic-docs and marketplace setup contracts as this
     skill's own runtime instructions. Matching a sibling plugin's setup skill byte-for-byte is a
     coincidence of scope, not a shared artifact — the topic-docs contract's "Implementers restate
     the rules" section records why this is not extracted, and what would reopen that. -->

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
5. **Dispatch capability.** `/discovery:explore` and `/discovery:research` dispatch a subagent by
   default, and that posture degrades rather than breaks on a session that cannot support all of it.
   Report these as PASS/INFO rows — **never FAIL, and never a blocker**:
   - **Harness version against the 2.1.219 floor** (`claude --version`). Below it, several behaviors
     the dispatch design relies on are false rather than merely absent: background became the default
     subagent execution mode in **2.1.198**, and below **2.1.218** a `context: fork` skill always
     blocked the invoking turn and the narrow background tool set did not apply to it. Report the
     observed version and, when it is under the floor, name which of those the session does not have.
     The skills still run — inline is always available — so this is INFO, not FAIL.
   - **`CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH`** — report the value, present or absent, and say what
     the running harness does with it rather than assuming. This default has moved three times:
     nesting shipped at a fixed five layers (2.1.172), went **off** by default (2.1.217), then
     returned at **a configurable default of three** (2.1.219) — so on 2.1.219 or later, absent
     means nesting is *available*, and the variable now lowers the ceiling (`"1"` disables nesting)
     as readily as it raises one. Read absent against the observed version, in four windows: below
     **2.1.172** nesting does not exist at all and the variable buys nothing; 2.1.172–2.1.216 absent
     meant available at a fixed five; 2.1.217–2.1.218 absent meant *off*, the only window where
     setting it was the way to turn nesting on; 2.1.219 and later absent means available at three.
     Report absent as INFO in every window: nesting buys
     **throughput**, not coverage — without it a dispatched agent fans out sequentially, slower for
     the same result. The variable is still only one of **two** conditions: it cannot add a tool an
     agent definition left out. The shipped `discovery:explorer` / `discovery:researcher` definitions
     list `Agent` for exactly this reason; a third-party agent that does not is unaffected by setting
     it. It is not a correctness prerequisite here, because the one control that needs a context
     which has not seen the work is the outcome-gate verifier, and the parent dispatches that as a
     **sibling** rather than the agent as a child. Note that env vars are read at session start, so a
     value set now takes effect next session.
   - **Fork availability.** Report it as a control, not a gate: forks have been enabled by default
     since **2.1.161**, and `CLAUDE_CODE_FORK_SUBAGENT` now only forces them on or off. Report it as
     a control, never as a prerequisite: older text that made forks conditional on setting that
     variable is stale, and it also attached the variable to skill-level `context: fork` rather than
     to the `fork` subagent type, which is a different mechanism. The user-facing command is
     `/subtask` as of **2.1.212**.

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
where every discovery skill (`/discovery:explore`, `/discovery:research`, `/discovery:research-deep`, and the agents they dispatch)
lands handoff artifacts.

## Gotchas

- **A comment-only YAML document parses as `null`** and fails the contract schema's `type: object`.
  When every chosen value is a default, still write at least one explicit key.
- **`git check-ignore` on a bare directory misses `**` patterns.** Probe a representative *file* path
  inside the contract root, or an uncommittable "committed" tier passes the guard.
- **Prose is an inference source, never the runtime authority.** A working-docs convention described
  in `CLAUDE.md` is reported as INFO; only `.claude/topic-docs.yaml` governs where artifacts land.
- **`apply` re-runs must preserve keys this invocation does not set.** Dropping an unmentioned key
  silently reconfigures a consumer that had chosen it deliberately.
- **Env vars are read at session start.** A capability the check reports as missing stays missing for
  the rest of this session even after it is set — the recommendation takes effect next session.
- **Never edit the consumer's root `.gitignore`.** The memory root gets its own self-ignoring guard.

## What this skill does NOT do

- Run an exploration or research pass — that is the plugin's discovery skills (`/discovery:explore`,
  `/discovery:research`, and `/discovery:research-deep`).
- Write machine-local state — configuration lives in the consumer's tracked concern file, never in the
  plugin directory or the plugin data directory (`${CLAUDE_PLUGIN_DATA}` is for caches and generated
  state only).
- Write Claude Code user settings or `pluginConfigs`.
