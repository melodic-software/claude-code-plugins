---
description: "Report where verification artifacts land in this repository. check (read-only) names the memory root the verification skills resolve and whether the project's own instructions declare a different one; nothing is configured or written. Use when: 'set up verification', 'configure the verification plugin', 'is verification configured', 'verification setup', 'where do verification manifests / baselines land'. Action: check (read-only, default). Re-runnable. Safe to invoke again."
argument-hint: "[check]"
user-invocable: true
disable-model-invocation: true
---

## Purpose

The verification plugin has nothing to configure. Placement is fixed by the plugin's lifecycle artifact
protocol
([`${CLAUDE_PLUGIN_ROOT}/reference/artifact-protocol.md`](${CLAUDE_PLUGIN_ROOT}/reference/artifact-protocol.md)):
`/verification:confirm` writes its evidence manifest and `/verification:measure` its baselines and
raw captures into the memory slice `<memory_dir>/<slug>/`, never committed. `<memory_dir>` is `.work/`
unless the project's own instructions declare another root.

This is a check-only setup: the plugin owns no writable consumer artifact, declares no `userConfig`,
and has no external prerequisite, so there is nothing for an `apply` to write. Idempotent: re-running
reads the current state again.

## `check` (read-only)

Report a PASS/INFO table. Do not write anything.

1. **Memory root.** Look for a working-docs root declared in the repo's own `CLAUDE.md`, `AGENTS.md`,
   or `.claude/rules`. Report the declared root, or `.work/` when none is declared, as INFO.
2. **Ignore state.** Run `git check-ignore -v <memory_dir>/probe/baselines/x` on a representative
   file path (a bare directory misses `**` patterns). A match is PASS and names the rule. No match is
   INFO: the memory root's own self-ignoring `.gitignore` is created by the first memory-slice
   write, announced, so an absent guard before any run is expected.

## What this skill does NOT do

- Run a verification pass. That is the plugin's verification skills (`/verification:confirm`,
  `/verification:measure`).
- Write any file, edit any ignore file, or write the plugin directory or the plugin data directory
  (`${CLAUDE_PLUGIN_DATA}` is for caches and generated state only).
- Write Claude Code user settings or `pluginConfigs`.
