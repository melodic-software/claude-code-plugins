---
name: setup
description: "Configure the review plugin for this repository: bootstrap the consumer's standards index per the standards convention — the index review criteria resolve through — persisting docs/standards/ and, on relocation, .claude/standards.yaml. Use when: 'set up review', 'configure the review plugin', 'review setup', 'set up standards', 'bootstrap the standards index', or a review skill reports a missing or version-skewed standards index. Re-runnable — safe to invoke again to reconfigure or migrate."
argument-hint: "(no arguments — interactive interview)"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Settle where the consumer's **standards** live — the adopted conventions and criteria this
plugin's review modes resolve through — by implementing the normative "Setup and migration"
section of the plugin's contract binding
[`${CLAUDE_PLUGIN_ROOT}/reference/standards-contract.md`](${CLAUDE_PLUGIN_ROOT}/reference/standards-contract.md).
The procedure (state reading via the index presence test, the conforming-index short-circuit, the
hand-authored-README confirmation gate, interview, skeleton write, row-path validation,
DIRECTIONAL version-delta detection with guided migration, idempotent re-run) lives there —
implement it by reference, do not restate it.

Idempotent: re-running reads the current state and offers an update rather than overwriting blind;
a re-run against a conforming, current-version index proposes no changes.

## Task

Plugin-side notes on top of the binding's procedure:

1. **State reading order:** `.claude/standards.yaml` → index presence test at the resolved
   `<standards_dir>/README.md` → inference sources (existing review docs such as a repo-root
   `REVIEW.md` or `docs/review*` directory, other docs directories, ecosystem configs, ambient
   `CLAUDE.md` content). Pre-existing review documentation is an inference source for proposing
   index rows — converting it requires the binding's explicit-confirmation gate.
2. **Bootstrap writes** (interactive, user-accepted — no silent writes): the skeleton index with
   its `standards-contract` frontmatter at the binding's version, and the setup-owned
   `<standards_dir>/.gitignore` containing `*.local.md` (the personal-overlay ignore). Write
   `.claude/standards.yaml` only when the user relocates the root from the documented default.
3. **Validate every index row path** on each run (external-row validation duty); surface broken
   rows with an offered fix.
4. **Optional offers, never demands:** reorganizing mixed or spread standards content toward the
   SRP + index shape.
5. **Migration is this skill re-run** — no separate action; direction and messaging per the
   binding.

## Output

A written (or confirmed-healthy) standards index and its overlay `.gitignore`, a one-line summary
of the effective standards root, the row-validation result, and how to re-run this setup to
reconfigure or migrate.

## What this skill does NOT do

- Run a review — that is `/review:quality-gate` and this plugin's reviewer agents; they resolve
  criteria through the index this setup bootstraps.
- Edit the consumer's root `.gitignore` or any ignore file it did not itself create — the single
  setup-owned ignore file is the standards root's bootstrap-shipped `<standards_dir>/.gitignore`.
- Write anything into the plugin directory or the plugin data directory
  (`${CLAUDE_PLUGIN_DATA}` is for caches and generated state only).
