---
description: "Report where verification artifacts land and write the repository's docs/conventions/verification.yaml proof level. check (read-only) names the memory root the verification skills resolve and validates the settings file; apply writes proof_level after confirmation. Use when: 'set up verification', 'configure the verification plugin', 'is verification configured', 'verification setup', 'where do verification manifests / baselines land', 'set the proof level for this repo'. Actions: check (read-only, default) | apply proof_level=VALUE. Re-runnable."
argument-hint: "[check|apply] [proof_level=<path|live|strict>] [live_workers=<n>]"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Artifact placement is fixed by the plugin's lifecycle artifact protocol
([`${CLAUDE_PLUGIN_ROOT}/reference/artifact-protocol.md`](${CLAUDE_PLUGIN_ROOT}/reference/artifact-protocol.md)):
`/verification:confirm` writes its evidence manifest and `/verification:measure` its baselines and
raw captures into the memory slice `<memory_dir>/<slug>/`, never committed. `<memory_dir>` is `.work/`
unless the project's own instructions declare another root. Nothing about placement is configured.

The plugin owns one tracked settings file, `docs/conventions/verification.yaml`, the repository
layer of its settings, `proof_level` and `live_workers=<n>` (values, layers and the level rules:
[`${CLAUDE_PLUGIN_ROOT}/reference/config.md`](${CLAUDE_PLUGIN_ROOT}/reference/config.md); schema:
`${CLAUDE_PLUGIN_ROOT}/schemas/verification.schema.json`). `check` reports it; `apply` writes it
only when the operator names the key or asks to set the proof level. Idempotent: re-running reads
the current state again.

## `check` (read-only)

Report a PASS/INFO/WARN table. Do not write anything.

1. **Memory root.** Look for a working-docs root declared in the repo's own `CLAUDE.md`, `AGENTS.md`,
   or `.claude/rules`. Report the declared root, or `.work/` when none is declared, as INFO.
2. **Ignore state.** Run `git check-ignore -v <memory_dir>/probe/baselines/x` on a representative
   file path (a bare directory misses `**` patterns). A match is PASS and names the rule. No match is
   INFO: the memory root's own self-ignoring `.gitignore` is created by the first memory-slice
   write, announced, so an absent guard before any run is expected.
3. **Settings file.** Run `node "${CLAUDE_SKILL_DIR}/scripts/setup-apply.mjs" --check` from the
   project root and add each line it prints with its own prefix: INFO when the file is absent
   (`proof_level` comes from `userConfig` or its default), PASS with the value when it validates,
   WARN when it does not (a value outside `path`, `live`, `strict`, a key set twice, an empty value,
   null, an unknown key, a file that does not parse, a list or map, a symlink or hard link), quoting
   the file, key and value. A WARN never stops `/verification:confirm`: it names the value, drops
   the layer and resolves `path`. `apply` is the fix. `/verification:confirm` reads the default
   branch's committed copy, so say that a working-tree value takes effect once it is merged there.

## `apply`

1. **Resolve the value.** With a complete `proof_level=<value>` argument, use it. Otherwise ask
   once, recommendation first: `path`, the default, unless the team wants every runnable change
   driven live (`live`) or per-phase unit, live and performance proof (`strict`). Never invent a
   key the schema does not list. Before recommending `live` or `strict`, say that a member on an
   older verification release does not read this file, so the level only holds once every member
   has upgraded.
2. **Write.** One call:

   ```bash
   node "${CLAUDE_SKILL_DIR}/scripts/setup-apply.mjs" proof_level=live
   ```

   The script checks the value against the schema, refuses a key given twice, validates the
   existing file, and validates the whole resulting document before it writes. In the existing file
   it overwrites only a value outside the key's values, an empty value or null; it refuses a key set
   twice, a map or list in block or flow form, an empty quoted string, an unknown key, or a file
   that does not parse. It writes only `<git toplevel>/docs/conventions/verification.yaml`, and
   refuses a root that is `$HOME` or an ancestor of it, a symlink, a hard-linked target, or a
   `docs/conventions` that resolves outside the repository, checked again before each directory it
   creates and right before the write. Every refusal is one line, exits 1 and leaves the file as it
   was; a failed write removes only its own temp file. A missing file is created; a value already
   in place prints `already configured`.
3. **An existing file that would change** exits 3 and prints a unified diff without writing. Show
   the operator that diff and ask whether to write it. Only on an explicit yes, re-run the same call
   with `--yes`; on anything else, stop with the file unchanged.
4. **Verify.** Re-run the settings-file `check` row and report the value it prints, not the value
   written. Then run `git check-ignore -v docs/conventions/verification.yaml` (a match is FAIL with
   the pattern) and `git ls-files --error-unmatch docs/conventions/verification.yaml` (non-zero
   right after a fresh write means "written but untracked: commit it to share with the team").

## Output

The `check` table. After `apply`: the diff shown, the written path, the value `check` reads back,
and whether the file is tracked.

## Next

`/verification:confirm`, which resolves `proof_level` from this file on the default branch.

## What this skill does NOT do

- Run a verification pass. That is the plugin's verification skills (`/verification:confirm`,
  `/verification:measure`).
- Write any settings file other than `docs/conventions/verification.yaml`, edit any ignore file,
  or write the plugin directory or the plugin data directory (`${CLAUDE_PLUGIN_DATA}` is for caches
  and generated state only).
- Write Claude Code user settings or `pluginConfigs`. The per-user `proof_level` option is set
  through `/plugin configure`, not here.
