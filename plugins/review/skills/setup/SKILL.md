---
description: "Configure the review plugin for this repository: bootstrap the consumer's standards index per the standards convention, since review criteria resolve through that index, persisting docs/standards/ and, on relocation, .claude/standards.yaml; and write the repository's docs/conventions/review.yaml settings after confirmation. Use when: 'set up review', 'configure the review plugin', 'review setup', 'set up standards', 'bootstrap the standards index', 'turn off the ratchet offer for this repo', or a review skill reports a missing or version-skewed standards index. Actions: check (read-only verification, default) | apply (bootstrap, reconfigure, or migrate). Re-runnable."
argument-hint: "[check|apply] [<key>=<value> ...]"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Settle where the consumer's **standards** live, the adopted conventions and criteria this
plugin's review modes resolve through. By implementing the normative "Setup and migration"
section of the plugin's contract binding
[`${CLAUDE_PLUGIN_ROOT}/reference/standards-contract.md`](${CLAUDE_PLUGIN_ROOT}/reference/standards-contract.md).
The procedure (state reading via the index presence test, the conforming-index short-circuit, the
hand-authored-README confirmation gate, interview, skeleton write, row-path validation,
DIRECTIONAL version-delta detection with guided migration, idempotent re-run) lives there. Implement it by reference; do not restate it.

Idempotent: re-running reads the current state and offers an update rather than overwriting blind;
a re-run against a conforming, current-version index proposes no changes.

Action routing per the uniform setup contract
([`docs/plugin-philosophy.md`](https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/plugin-philosophy.md)
"Setup is explicit and repeatable"): no argument or `check` runs
the binding's state-reading procedure read-only and reports index presence and resolved
standards root, per-row path validation, and the DIRECTIONAL version delta as a PASS/FAIL/INFO
table with one remediation line per FAIL, writing nothing. `apply` runs `check` first, then the
binding's bootstrap / reconfigure / migration flow below; after any write it re-runs the relevant
probe and reports the actual result. Non-interactive when the state admits exactly one conforming
action (the conforming-index short-circuit); the binding's explicit-confirmation gates
(hand-authored README conversion, bootstrap writes) remain explicit user decisions, never silent.

The plugin also owns one tracked settings file, `docs/conventions/review.yaml`, the repository
layer of its settings (keys, values and layers:
[`${CLAUDE_PLUGIN_ROOT}/reference/config.md`](../../reference/config.md); schema:
`${CLAUDE_PLUGIN_ROOT}/schemas/review.schema.json`). `check` reports it; `apply` writes it only
when the operator names a key or asks to change a setting, as described under
[Repository settings](#repository-settings).

## Repository settings

**`check` row.** Run `node "${CLAUDE_SKILL_DIR}/scripts/setup-apply.mjs" --check` from the project
root and add each line it prints to the table with its own INFO, PASS or WARN prefix. INFO when the
file is absent (every key comes from `userConfig` or its default); PASS with each key's value when
it validates; WARN when it does not (a value outside the key's values, a quoted boolean, a key set
twice, an empty value, an unknown key, a file that does not parse, or a map or list where one value
belongs), quoting the file, key and value.
A WARN never stops a review skill: the skill names the value and drops that layer, and `apply` is
the fix.

**`apply`.**

1. **Resolve the values.** With complete `<key>=<value>` arguments, use them. Otherwise ask one key
   at a time, recommendation first, from the table in `${CLAUDE_PLUGIN_ROOT}/reference/config.md` (`ratchet_offer`:
   `true`, the default, unless the team does not want stubs to offer `/review:ratchet`). Never
   invent a key the schema does not list.
2. **Write.** One call with every value:

   ```bash
   node "${CLAUDE_SKILL_DIR}/scripts/setup-apply.mjs" ratchet_offer=false
   ```

   The script checks each value against the schema, refuses a key given twice, validates the
   existing file, and validates the whole resulting document before it writes. In the existing
   file it overwrites only a value outside the key's values, an empty value or null; it refuses a
   key set twice, a map or list in block or flow form, an empty quoted string, an unknown key, or
   a file that does not parse. It writes only `<git toplevel>/docs/conventions/review.yaml`, and
   refuses a root that is `$HOME` or an ancestor of it, a symlink, a hard-linked target, or a
   `docs/conventions` that resolves outside the repository, checked again before each directory it
   creates and right before the write. Every refusal is one line, exits 1 and leaves the file as it
   was; a failed write removes only its own temp file. A missing file is created; a value already
   in place prints `already configured`.
3. **An existing file that would change** exits 3 and prints a unified diff without writing. Show
   the operator that diff and ask whether to write it. Only on an explicit yes, re-run the same call
   with `--yes`; on anything else, stop with the file unchanged.
4. **Verify.** Re-run the `check` row and report the value it prints, not the value written. Then
   the tracked-file pair from the `apply` task below on `docs/conventions/review.yaml`.

## `apply` task

Plugin-side notes on top of the binding's procedure:

1. **State reading order:** `.claude/standards.yaml` → index presence test at the resolved
   `<standards_dir>/README.md` → inference sources (existing review docs such as a repo-root
   `REVIEW.md` or `docs/review*` directory, other docs directories, ecosystem configs, ambient
   `CLAUDE.md` content). Pre-existing review documentation is an inference source for proposing
   index rows. Converting it requires the binding's explicit-confirmation gate.
2. **Bootstrap writes** (interactive, user-accepted. No silent writes): the skeleton index with
   its `standards-contract` frontmatter at the binding's version, and the setup-owned
   `<standards_dir>/.gitignore` containing `*.local.md` (the personal-overlay ignore). Write
   `.claude/standards.yaml` only when the user relocates the root from the documented default.
   After a bootstrap write, run the tracked-file pair on each written team file:
   `git check-ignore -v` reports no match (a match is FAIL with the pattern) AND
   `git ls-files --error-unmatch` exits 0 (non-zero right after a fresh write means "written but
   untracked: commit it to share with the team", never success).
3. **Validate every index row path** on each run (external-row validation duty); surface broken
   rows with an offered fix.
4. **Optional offers, never demands:** reorganizing mixed or spread standards content toward the
   SRP + index shape.
5. **Migration is this skill re-run**. No separate action; direction and messaging per the
   binding.

## Output

A written (or confirmed-healthy) standards index and its overlay `.gitignore`, a one-line summary
of the effective standards root, the row-validation result, and how to re-run this setup to
reconfigure or migrate. When repository settings were written: the diff shown, the written path,
the value `check` reads back, and whether the file is tracked.

## Next

`/review:quality-gate`, which resolves review criteria through the index this setup bootstraps.

## What this skill does NOT do

- Run a review. That is `/review:quality-gate` and this plugin's reviewer agents; they resolve
  criteria through the index this setup bootstraps.
- Write the plugin cache, Claude Code user settings, or `pluginConfigs`. The per-user
  `ratchet_offer` option is set through `/plugin configure`, not here.
- Write any settings file other than `docs/conventions/review.yaml`.
- Edit the consumer's root `.gitignore` or any ignore file it did not itself create, the single
  setup-owned ignore file is the standards root's bootstrap-shipped `<standards_dir>/.gitignore`.
- Write anything into the plugin directory or the plugin data directory
  (`${CLAUDE_PLUGIN_DATA}` is for caches and generated state only).
