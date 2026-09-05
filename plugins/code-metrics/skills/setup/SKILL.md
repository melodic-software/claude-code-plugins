---
description: "Verify or configure the code-metrics plugin for this repository: `check` probes the interpreter, every configuration layer (user-global, team, local overlay, and the consumer's ecosystem files) for the YAML subset and the tracked-file guard, prints every reference with the layer that supplied it, and probes each collector adapter (a version, or missing with its install hint); `apply` writes the tracked `.claude/code-metrics.yaml` team layer per key, idempotently, never installing a tool and never editing `.gitignore`. Use when: 'set up code-metrics', 'configure code metrics', 'is code-metrics configured', 'which collectors are installed', 'set the cyclomatic reference', 'change the file length reference', 'code-metrics setup', or an audit skill reports a configuration layer it could not read."
argument-hint: "check | apply [<key>=<value> ...]"
user-invocable: true
disable-model-invocation: true
allowed-tools: ["Bash(${CLAUDE_SKILL_DIR}/scripts/setup-check.sh:*)", "Bash(${CLAUDE_SKILL_DIR}/scripts/setup-apply.py:*)", "Bash(git check-ignore:*)", "Bash(git ls-files:*)"]
shell: bash
---

## Purpose

Every reference the plugin prints, every lane's collector order, the scope exclusions, and the
coverage artifact paths resolve through one consumer surface, `.claude/code-metrics.yaml`,
layered as user-global (`~/.claude/code-metrics.yaml`), team (tracked), and local overlay
(`.claude/code-metrics.local.yaml`, gitignored) with per-key override. All three layers absent is
a valid state: every key has a bundled default. This skill is the check-centric setup for that
surface and for the external collectors the audits probe: `check` inspects and verifies, `apply`
persists, and neither installs anything. Keys, defaults, and provenance:
`${CLAUDE_PLUGIN_ROOT}/reference/config.md`.

Action routing: no argument or `check` runs the check; `apply` runs the check first, then
persists. `apply` is non-interactive when complete `<key>=<value>` arguments are supplied
(automation and headless use pass them and are never prompted); with none, it interviews one key
at a time, recommendation first.

## `check` (read-only)

Run and present the table as printed:

```bash
"${CLAUDE_SKILL_DIR}/scripts/setup-check.sh"
```

Rows, each PASS, FAIL, WARN, or INFO:

1. **python**: the interpreter resolved (`python3`, `python`, or `py -3`) and the plugin's floor.
   FAIL stops the table: Python is required for correctness, so name the remediation.
2. **layer user-global / team / local**: absent (INFO), or present and parsed in the YAML subset
   the plugin reads (block mappings, block sequences, flow sequences of scalars, scalars,
   comments). A flow mapping, anchor, tag, or block scalar is FAIL with its line; the operator
   rewrites the file in block style.
3. **layer team tracked**: `git check-ignore -v` on the team file reports no match (a match is
   FAIL with the rule: an ignored team layer never reaches the team) and `git ls-files
   --error-unmatch` sees it (untracked is WARN: written but uncommitted).
4. **layer local ignored**: the overlay is gitignored, else WARN with the recommended consumer
   line `.claude/**/*.local.*`. Recommend the line; never edit the consumer's `.gitignore`.
5. **ecosystem `<lane>.yaml`**: each consumer ecosystem file parses; its `globs` and `enabled`
   override lane detection.
6. **reference `<measure>`**: the resolved value with the layer that supplied it and its
   provenance, so a personal layer that changed a value is visible.
7. **collector `<tool>`**: PASS with the version when the adapter's probe resolves the tool on
   `PATH`; INFO `missing` with the install hint otherwise. Missing is not a failure: the lane
   reports `unavailable` at audit time and the run continues.

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
   "${CLAUDE_SKILL_DIR}/scripts/setup-apply.py" --dir "$(git rev-parse --show-toplevel)" size.file_lines=500 'scope.exclude=["vendor/**"]'
   ```

   The script merges per key into `.claude/code-metrics.yaml`, writes block style, and prints
   `already configured` without touching the file when nothing changes.
4. **Verify.** Re-run `check`; report the persisted values from its table, never from the write
   alone. The tracked-file pair decides the outcome: a WARN `written but untracked` means "commit
   it to share with the team", never success; an ignored team file is FAIL and the operator's
   `.gitignore` is theirs to fix.

## Output

`check`: the table. `apply`: the table before and after, the written path, and one line on how
to re-run this skill to reconfigure. Say which layer supplied each reference that differs from the
bundled default.

## What this skill does NOT do

- Install, download, or `npx`-fetch a collector. It prints install hints; the operator installs.
- Write the user-global or local layers. Those are personal files the operator edits.
- Write Claude Code user settings or `pluginConfigs`; the plugin has no `userConfig`.
- Edit the consumer's `.gitignore`; it recommends the one recursive line.
- Run an audit. The audit skills read the same resolved document at run time.

## Gotchas

- The team file must be committed to reach the team; `apply` leaves it untracked on purpose and
  the `check` row says so until it is committed.
- `apply` judges idempotence on parsed content, so hand-written comments never force a rewrite
  by themselves; a value that differs does, and the file is rewritten in block style.
- A layer written with a flow mapping (`{ enabled: true }`) is outside the subset; every audit
  reports the file as unreadable with the line, and `check` shows the same row.
- `size.mode: iso-8.2.115` needs a collector that reports function ranges (`lizard`, `radon`);
  Bash has none, and its row says so.
