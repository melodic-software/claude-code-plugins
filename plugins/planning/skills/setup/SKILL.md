---
description: "Verify and configure the planning plugin for this repository. check inspects read-only the standards index, the interview-rendering toggle and docs/conventions/planning.yaml; apply bootstraps the standards index (docs/standards/ and, on relocation, .claude/standards.yaml), and apply with key=value pairs writes docs/conventions/planning.yaml after confirmation. Use when: 'set up planning', 'is planning configured', 'configure the planning plugin', 'planning setup', 'set up standards', 'bootstrap the standards index', 'set phase_order for this repo', 'set plan_store for the team', or a planning skill reports missing or thin config. Re-runnable."
argument-hint: "[check|apply] [<key>=<value> ...]"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Verify and settle the planning plugin's two consumer-side concerns: where the consuming repo's
**standards** live, the adopted conventions and criteria the planning skills ground plans in, and
the repository layer of the plugin's **settings**, `docs/conventions/planning.yaml` (keys, values
and layers: [`${CLAUDE_PLUGIN_ROOT}/reference/config.md`](${CLAUDE_PLUGIN_ROOT}/reference/config.md);
schema: `${CLAUDE_PLUGIN_ROOT}/schemas/planning.schema.json`). Where planning artifacts land needs
no configuration: the plugin's artifact protocol
([`${CLAUDE_PLUGIN_ROOT}/reference/artifact-protocol.md`](${CLAUDE_PLUGIN_ROOT}/reference/artifact-protocol.md))
fixes placement.

Both concerns are optional: with no index, the pipeline uses standard engineering defaults, and with
no settings file every key resolves from `userConfig` or its default, so either absence is a reported
INFO, never a FAIL. `check` inspects read-only; `apply` resolves and persists, then re-runs `check`.
Action routing: no argument or `check` runs the check; `apply <key>=<value> ...` runs the check,
then writes the settings file and nothing else; bare `apply` runs the check, then the standards
bootstrap, then offers the settings keys. Idempotent: re-running reads the current state and offers
an update rather than overwriting blind.

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
3. **Repository settings**. Run `"${CLAUDE_SKILL_DIR}/scripts/setup-apply.mjs" --check` from the
   project root and report each line it prints with its own prefix: INFO when
   `docs/conventions/planning.yaml` is absent, PASS with each key's value when it validates, WARN
   for each problem when it does not (a value outside the key's list, a key set twice, an empty
   value, a map or list where one value belongs, a key outside the schema), quoting the file, key
   and value. An invalid value never stops a planning skill: the skill names it and drops that
   layer, so the row is a WARN, not a FAIL, and `apply` is the fix. A one-line refusal (an unsafe
   path, or a root that is `$HOME` or above it) is reported as WARN with that line.

## `apply` (idempotent)

Run `check`, then, per the action routing above, write the settings file or bootstrap the standards
index. Proceed non-interactively where the invocation and the repo make the values unambiguous; ask
only where a choice genuinely needs the user. No silent writes. Every write is user-accepted.

### Repository settings (`docs/conventions/planning.yaml` only)

1. **Resolve the values.** With complete `<key>=<value>` arguments, use them. Otherwise (bare
   `apply`, after the standards bootstrap) ask one key at a time, recommendation first, from the Keys
   table in `${CLAUDE_PLUGIN_ROOT}/reference/config.md`, and skip a key the operator leaves to each
   user. Recommend each key's default unless the team named a reason for another value. Never invent
   a key the schema does not list.
2. **Write.** One call with every value:

   ```bash
   "${CLAUDE_SKILL_DIR}/scripts/setup-apply.mjs" phase_order=riskiest-first
   ```

   The script checks each value against the schema and validates the whole resulting document
   before it writes; an invalid value or key exits 1 and writes nothing. It writes only
   `<git toplevel>/docs/conventions/planning.yaml`, refuses a root that is `$HOME` or an ancestor of
   it, a symlink, a hard-linked target, or a `docs/conventions` that resolves outside the
   repository, checks the path again right before the write and the rename, and writes through a
   new temp file in the same directory. Every refusal is one line. A missing file is created; a
   value already in place prints `already configured` and writes nothing.
3. **An existing file that would change** exits 3 and prints a unified diff without writing. Show
   the operator that diff and ask whether to write it. Only on an explicit yes, re-run the same call
   with `--yes`; on anything else, stop with the file unchanged. A request to "set it" is not a yes
   to a diff the operator has not seen.
4. **Verify.** Re-run `check` and report the value from its table, not from the write. Then the
   tracked-file pair: `git check-ignore -v docs/conventions/planning.yaml` reports no match (a match
   means the team never receives the file: say so, and leave `.gitignore` to the operator), and
   `git ls-files --error-unmatch docs/conventions/planning.yaml` exits 0. Non-zero right after a
   fresh write means "written but untracked: commit it to share with the team", never success.

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
to re-run this setup to reconfigure or migrate. When the settings were exercised, the `check` table
before and after, the diff when one was shown, the written path, and whether the file is tracked.

## Next

`/planning:plan`

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
- Commit `docs/conventions/planning.yaml`. `apply` leaves it uncommitted, and the tracked-file pair
  says so.
