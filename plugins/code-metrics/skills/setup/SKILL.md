---
description: "Verify or configure the code-metrics plugin for this repository: `check` probes the interpreter, every configuration layer (team, personal override, old files still read, and the consumer's ecosystem files) for the YAML subset and the tracked-file guard, prints every reference with the layer that supplied it, and runs each collector adapter's probe and one measure on a bundled fixture (a version and the measure, or missing with its install hint); `apply` writes the tracked `docs/conventions/code-metrics.yaml` team layer per key, carrying every declared key of a retired `.claude/code-metrics.yaml`, and copies old personal files after a preview, idempotently, never installing a tool and never editing `.gitignore`. Use when: 'set up code-metrics', 'configure code metrics', 'is code-metrics configured', 'which collectors are installed', 'set the cyclomatic reference', 'change the file length reference', 'code-metrics setup', or an audit skill reports a configuration layer it could not read."
argument-hint: "[check|apply] [<key>=<value> ...]"
user-invocable: true
disable-model-invocation: true
allowed-tools: ["Bash(${CLAUDE_SKILL_DIR}/scripts/setup-check.sh:*)", "Bash(${CLAUDE_SKILL_DIR}/scripts/setup-apply.py:*)", "Bash(git check-ignore:*)", "Bash(git ls-files:*)"]
shell: bash
---

## Purpose

Every reference the plugin prints, every lane's collector order, the scope exclusions, and the
coverage artifact paths resolve through one consumer surface whose layers, per-key override and
dual-read window `${CLAUDE_PLUGIN_ROOT}/reference/config.md` lists. The team file of earlier
releases, `.claude/code-metrics.yaml`, is retired and never read; `apply` moves its keys. The old
`~/.claude/code-metrics.yaml` (now the `userConfig` layer, the file the `config_file` option
names) and `.claude/code-metrics.local.yaml` (now `docs/conventions/code-metrics.local.yaml`) are
still read during the dual-read window, each named in a warning on every run; `apply --copy-old`
copies their keys. Every layer absent is a valid state: every key has a bundled default. This
skill is the check-centric setup for that surface and for the external collectors the audits probe:
`check` inspects and verifies, `apply` persists, and neither installs anything. Keys, defaults,
provenance, and the dual-read window: `${CLAUDE_PLUGIN_ROOT}/reference/config.md`.

Action routing: no argument or `check` runs the check; `apply` runs the check first, then
persists. `apply` is non-interactive when complete `<key>=<value>` arguments are supplied
(automation and headless use pass them and are never prompted); with none, it interviews one key
at a time, recommendation first.

## `check` (read-only)

Run and present the table as printed:

```bash
"${CLAUDE_SKILL_DIR}/scripts/setup-check.sh" --user-file '${user_config.config_file}'
```

Keep `--user-file` exactly as written here and on the `--copy-old` call below: it names the
`userConfig` layer's file, and an empty or unsubstituted value means the option is unset.

Rows, each PASS, FAIL, WARN, or INFO:

1. **python**: the interpreter resolved (`python3`, `python`, or `py -3`) and the plugin's floor.
   FAIL stops the table: Python is required for correctness, so name the remediation.
2. **layer userConfig / team / local**: `userConfig` is INFO `unset` when the `config_file`
   option names no file, and WARN when its value is not an absolute path. Each file layer is
   absent (INFO), or present and parsed in the YAML subset the plugin reads (block mappings, block
   sequences, flow sequences of scalars, scalars, comments). A flow mapping, anchor, tag, or block
   scalar is FAIL with its line; the operator rewrites the file in block style.
   **layer team location** is WARN when the retired `.claude/code-metrics.yaml` exists: the
   plugin does not read it, so `apply` moves its keys, or, once the docs file exists, the
   operator deletes it.
   **layer user-global location** is WARN when the old `~/.claude/code-metrics.yaml` exists,
   naming it, whether it is still read, and its new location: the file the `config_file` option
   names, or "set the option in /config" while it is unset. **layer local location** is WARN when
   the old `.claude/code-metrics.local.yaml` exists, naming it, whether it is still read, and
   `docs/conventions/code-metrics.local.yaml`. `apply --copy-old` copies each one's keys.
3. **layer team tracked**: `git check-ignore -v` on the team file reports no match (a match is
   FAIL with the rule: an ignored team layer never reaches the team) and `git ls-files
   --error-unmatch` sees it (untracked is WARN: written but uncommitted).
4. **layer local ignored**: the personal override is gitignored, else WARN with the recommended
   consumer line `docs/conventions/**/*.local.*` (`.claude/**/*.local.*` for an old personal file
   still read). Recommend the line; never edit the consumer's `.gitignore`.
5. **ecosystem `<lane>.yaml`**: each consumer ecosystem file parses. PASS when its lane is in the
   resolved `lanes` mapping (a bundled lane, or one a layer lists): its `globs` and `enabled`
   override lane detection. WARN naming the missing `lanes.<lane>` entry when no layer lists the
   lane: the resolver ignores that record. WARN asking for a rename when the file name is not a
   lowercase kebab-case lane id, since no `lanes` entry can name it. WARN when the configuration
   does not resolve, since the lane list is then unknown.
6. **reference `<measure>`**: the resolved value with the layer that supplied it and its
   provenance, so a personal layer that changed a value is visible.
7. **collector `<tool>`**: the adapter's probe, then one measure from the ladder run on a bundled
   fixture. PASS `<version>; measured <measure> on <fixture>` when the measure returns rows; FAIL
   when the probe passed but the measure exited non-zero or returned no rows, with the first
   stderr line (a tool that resolves but cannot measure); WARN `probe only: <reason>` when no
   bundled fixture can exercise it (a tool bound to the project's own configuration, or one with
   no fixture for its lane); INFO `missing` with the install hint when the probe fails. Missing
   is not a failure: the lane reports `unavailable` at audit time and the run continues.

Exit 0 with no FAIL row, 1 with one, 2 on a usage or environment error.

## `apply` (idempotent)

1. Run `check` and read its table.
2. **Resolve the values.** With complete `<key>=<value>` arguments, use them directly. Otherwise
   interview one key at a time, recommendation first, walking the annotated template
   `${CLAUDE_SKILL_DIR}/templates/config-template.yaml` (every key with its default and
   provenance, in the subset; the key reference is `${CLAUDE_PLUGIN_ROOT}/reference/config.md`):
   the cyclomatic reference (20, ISO/IEC 5055 §8.2.117; 10 and 15 are the cited alternatives),
   the file-length reference (1000, the plugin's own number; 500 selectable) and `size.mode`,
   scope exclusions, coverage artifact paths, per-lane opt-outs and collector order, duplication
   registries. Offer every declared key, preserve every key the existing file carries, and never
   invent a key beyond the contract. A key outside the contract is written but reported, because
   unknown keys are inert to the plugin.
3. **Persist.** One call per run, every value as `<key>=<value>` in the YAML subset:

   ```bash
   "${CLAUDE_SKILL_DIR}/scripts/setup-apply.py" size.file_lines=500 'scope.exclude=["vendor/**"]'
   ```

   The script merges per key into the repository root's `docs/conventions/code-metrics.yaml`
   (the root git reports from the current directory; `--dir <root>` or `--file <path>` overrides
   it), writes block style, and prints `already configured` without touching the file when
   nothing changes. When that file does not exist yet and `.claude/code-metrics.yaml` does, the
   first write carries every declared key of the retired file, so the docs file holds the values
   the retired one set, and drops and names any key the contract does not declare; with no
   `<key>=<value>` the run is that move alone. The retired file stays in place and is not read;
   tell the operator to delete it. A symlinked, hard-linked or non-regular target or retired
   file, or a symlinked `docs/`, `docs/conventions/` or `.claude/`, is refused with exit 1 and
   nothing written.
4. **Copy old files.** When `check` shows a **layer user-global location** or **layer local
   location** row, offer the copy. Preview it first and show the operator every line:

   ```bash
   "${CLAUDE_SKILL_DIR}/scripts/setup-apply.py" --copy-old --preview --user-file '${user_config.config_file}'
   ```

   Each key prints as `copy:` or `not copied:` with its source, target and reason. The old
   `~/.claude/code-metrics.yaml` goes to the `userConfig` file the `config_file` option names,
   never to the personal override; while the option is unset its keys are not copied and the run
   says to set the option in `/config` (Claude Code's own setting; this skill never writes it),
   then rerun. The old `.claude/code-metrics.local.yaml` goes to
   `docs/conventions/code-metrics.local.yaml`, and the run warns with the recommended
   `docs/conventions/**/*.local.*` line when git does not ignore that file. A key the target
   already sets is kept. On an explicit yes, run the same command without `--preview`, which
   writes the targets and leaves the old files in place for the operator to delete once `check`
   shows the values they expect; while the option is unset, the old user-global file stays until
   the option is set and a rerun has copied its keys. Without a yes, write nothing.
5. **Verify.** Re-run `check`; report the persisted values from its table, never from the write
   alone. The tracked-file pair decides the outcome: a WARN `written but untracked` means "commit
   it to share with the team", never success; an ignored team file is FAIL and the operator's
   `.gitignore` is theirs to fix.

## Output

`check`: the table. `apply`: the table before and after, the written path, and one line on how
to re-run this skill to reconfigure. Say which layer supplied each reference that differs from the
bundled default.

## What this skill does not do

- Install, download, or `npx`-fetch a collector. It prints install hints; the operator installs.
- Write the personal override or the `userConfig` file except through `apply --copy-old` after a
  preview and a yes, or touch an old file. Personal files are the operator's to edit and delete.
- Write Claude Code user settings or `pluginConfigs`; the operator sets `config_file` in `/config`.
- Edit the consumer's `.gitignore`; it recommends the one recursive line.
- Run an audit. The audit skills read the same resolved document at run time.

## Next

`/code-metrics:audit complexity`. The other `audit` actions and `audit-*` skills cover the rest.

## Gotchas

- The team file must be committed to reach the team; `apply` leaves it untracked on purpose and
  the `check` row says so until it is committed.
- `apply` judges idempotence on parsed content, so hand-written comments never force a rewrite
  by themselves; a value that differs does, and the file is rewritten in block style.
- A layer written with a flow mapping (`{ enabled: true }`) is outside the subset; every audit
  warns that the file was ignored, with the line, and `check` shows it as a FAIL row. A value of
  the wrong shape is dropped by file, key and value and the audit keeps running.
- `size.mode: iso-8.2.115` needs a collector that reports function ranges (`lizard`, `radon`);
  Bash has none, and its row says so.
