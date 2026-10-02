---
description: "Verify and configure the planning plugin for this repository. check inspects read-only the standards index presence and the interview-rendering toggle; apply bootstraps the standards index (docs/standards/ and, on relocation, .claude/standards.yaml). Use when: 'set up planning', 'is planning configured', 'configure the planning plugin', 'planning setup', 'set up standards', 'bootstrap the standards index', or a planning skill reports missing or thin config. Re-runnable. Safe to invoke again to reconfigure or migrate."
argument-hint: "[check|apply]"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Verify and settle the planning plugin's one consumer-side concern: where the consuming repo's
**standards** live, the adopted conventions and criteria the planning skills ground plans in. Where
planning artifacts land needs no configuration: the plugin's artifact protocol
([`${CLAUDE_PLUGIN_ROOT}/reference/artifact-protocol.md`](${CLAUDE_PLUGIN_ROOT}/reference/artifact-protocol.md))
fixes placement.

The standards concern is optional: with no index, the pipeline uses standard engineering defaults, so its
absence is a reported INFO, never a FAIL. `check` inspects read-only; `apply` resolves and persists, then
re-runs `check`. No argument or `check` runs the check; `apply` runs the check first, then the
bootstrap flow. Idempotent: re-running reads the current state and offers an update rather than
overwriting blind.

## `check` (read-only)

Report a PASS/FAIL/INFO table with one remediation line per FAIL. Modify nothing, and do NOT run a
planning stage. Those are the pipeline skills.

1. **Standards index**. The index presence test at the resolved `<standards_dir>/README.md`
   (`.claude/standards.yaml` may relocate the root from the documented default). Absent → INFO: the
   standards concern is not bootstrapped; `apply` offers to scaffold it. A present index whose
   `standards-contract` frontmatter version is behind the plugin binding's is INFO with the DIRECTIONAL
   version-delta noted (migration runs under `apply`). A present `README.md` that is hand-authored (not
   a conforming index) is INFO, flagged for the `apply` confirmation gate.
2. **Interview-rendering toggle**. INFO: report the effective `use_ask_user_question` value,
   `${user_config.use_ask_user_question}` (unexpanded or empty means the default `false`. The pipeline
   skills' question rounds render as inline prose). This is a native `userConfig` toggle, not a
   consumer-project file; `apply` gives the reconfigure guidance below.

## `apply` (idempotent)

Run `check`, then bootstrap the standards index. Proceed non-interactively where the invocation and
the repo make the values unambiguous; ask only where a choice genuinely needs the user. No silent
writes. Every bootstrap write is user-accepted.

### Standards bootstrap

Settle where the consumer's standards live by implementing the normative "Setup and migration" section
of the plugin's contract binding
[`${CLAUDE_PLUGIN_ROOT}/reference/standards-contract.md`](${CLAUDE_PLUGIN_ROOT}/reference/standards-contract.md).
The procedure (state reading via the index presence test, the conforming-index short-circuit, the
hand-authored-README confirmation gate, interview, skeleton write, row-path validation,
DIRECTIONAL version-delta detection with guided migration, idempotent re-run) lives there,
implement it by reference, do not restate it. Plugin-side notes only:

- **State reading order:** `.claude/standards.yaml` → index presence test at the resolved
  `<standards_dir>/README.md` → inference sources (existing docs directories, ecosystem configs,
  ambient `CLAUDE.md` content).
- **Bootstrap writes** (interactive, user-accepted. No silent writes): the skeleton index with
  its `standards-contract` frontmatter at the binding's version, and the setup-owned
  `<standards_dir>/.gitignore` containing `*.local.md` (the personal-overlay ignore). Write
  `.claude/standards.yaml` only when the user relocates the root from the documented default.
  After a bootstrap write, run the tracked-file pair on each written team file:
  `git check-ignore -v` reports no match (a match is FAIL with the pattern) AND
  `git ls-files --error-unmatch` exits 0 (non-zero right after a fresh write means "written but
  untracked: commit it to share with the team", never success).
- **Optional offers, never demands:** pointer-rule generation for indexed ecosystem surfaces
  (interactive only), and reorganizing mixed or spread standards content toward the SRP + index
  shape.
- **Migration is this skill re-run.** No separate action; direction and messaging per the
  binding. It is a versioned-contract upgrade under `apply`, the schema-evolution path the
  binding sanctions.

### Interview-rendering toggle

`use_ask_user_question` is a native `userConfig` boolean (default `false`) governing whether the
pipeline skills' question rounds render through `AskUserQuestion` or as inline prose. It is not a
consumer-project file this skill writes. Reconfigure through Claude Code's native flow, per the
marketplace's plugin-reconfiguration convention
(<https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/plugin-reconfiguration/README.md>,
which owns the verified-version record): interactive `/plugin configure planning@<marketplace>` any
time, or headless `claude plugin install planning@<marketplace> -s <scope> --config use_ask_user_question=true`
(repeatable per key). Against an already-installed plugin it prints `already installed` and still
writes the value. Do **not** uninstall to reconfigure: that drops the plugin's entire stored
`pluginConfigs` entry, resetting every option in the README's Options reference to its manifest
default. `-s` defaults to `user`; pass the scope `claude plugin list` reports, and run from that
project's directory for a `project`/`local` scope, or the rerun adds a second install record at the
scope passed and enables the plugin there; the value itself always lands in user settings. A
rejected value prints a warning yet exits 0, so read the output. This skill never writes Claude Code
user settings or `pluginConfigs`. Afterwards rerun `check` in a **fresh session**. The rendered `${user_config.*}`
and each hook's `CLAUDE_PLUGIN_OPTION_*` are fixed at session start, so a same-session `check`
still reports the OLD value; report the observed effective value, never an unobserved change.

### Verify after remediation

Re-run the `check` probes on what was written, the standards index presence/row-path validation, and
report the actual results, never success on the write alone.

Re-running `apply` after everything passes changes nothing and reports "already configured".

## Output

When the standards concern was exercised, a written (or confirmed-healthy) standards index and its
overlay `.gitignore`, a one-line summary of the effective values, the row-validation results, and how
to re-run this setup to reconfigure or migrate.

## What this skill does NOT do

- Run a planning stage. That is the pipeline skills (`/planning:brainstorm`, `/planning:prd`,
  `/planning:interview`, `/planning:design`, `/planning:design-handoff`,
  `/planning:devils-advocate`, `/planning:plan`). `check` only inspects config.
- Edit the consumer's root `.gitignore` or any ignore file it did not itself create. (The memory
  root's own self-ignoring `.gitignore` is created by the first memory-tier write, announced. Not by
  setup. The single setup-owned ignore file is the standards root's bootstrap-shipped
  `<standards_dir>/.gitignore`.)
- Write anything into the plugin directory or the plugin data directory
  (`${CLAUDE_PLUGIN_DATA}` is for caches and generated state only).
