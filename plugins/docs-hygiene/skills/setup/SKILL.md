---
description: "Verify or configure the docs-hygiene file-name skills for this repository: `check` resolves all three configuration layers, reports which layer supplied each key, and verifies that the casing regex compiles, every tier names a known form, every generated file's regenerator resolves, the team layer is tracked, and the personal overlay is ignored; `apply` writes the tracked `.claude/docs-hygiene.json` team layer per key, idempotently, and edits no other file. Use when: 'set up docs-hygiene', 'configure the file-name rule', 'is docs-hygiene configured', 'which casing rule is in effect', 'change the docs naming regex', 'add a frozen tier', 'docs-hygiene setup', or an audit reports a configuration layer it could not read."
argument-hint: "check | apply [--defaults] [<key>=<value> ...]"
user-invocable: true
disable-model-invocation: true
allowed-tools: ["Bash(${CLAUDE_SKILL_DIR}/scripts/setup-check.sh:*)", "Bash(${CLAUDE_SKILL_DIR}/scripts/setup-apply.sh:*)", "Bash(git check-ignore:*)", "Bash(git ls-files:*)", "Read"]
shell: bash
---

## Purpose

Every value the file-name skills act on comes from one consumer surface,
`.claude/docs-hygiene.json`, layered as user-global (`~/.claude/docs-hygiene.json`),
team (tracked), and personal overlay (`.claude/docs-hygiene.local.json`). All
three absent is a valid state: every key has a bundled default, and the defaults
are this marketplace's own values.

This skill is the check-centric setup for that surface: `check` inspects and
verifies, `apply` persists, and neither installs anything. Keys, defaults, layer
classes, and provenance live in
[`${CLAUDE_PLUGIN_ROOT}/reference/config.md`](${CLAUDE_PLUGIN_ROOT}/reference/config.md).

Action routing: no argument or `check` runs the check; `apply` runs the check
first, then persists. Both are non-interactive when the action is given. With
`apply` and no key, interview one key at a time, recommendation first, walking
the annotated template
[`${CLAUDE_SKILL_DIR}/templates/docs-hygiene.json`](templates/docs-hygiene.json).

## `check` (read-only)

Run it and present the table as printed:

```bash
${CLAUDE_SKILL_DIR}/scripts/setup-check.sh
```

Rows, each PASS, FAIL, WARN, or INFO:

1. **jq**, **git**: the prerequisites. A missing `jq` is FAIL and stops the
   table, because every skill in this plugin reads the concern file with it.
2. **layer user-global / team / overlay**: absent (INFO), or present with its
   path. A present file that does not parse, or that declares an unknown schema,
   surfaces at the **resolve** row with the file named.
3. **key shape**: every key carries the type the contract declares.
4. **rule**, **regex**, **regex quoting**: the casing rule is one this version
   implements, the regex compiles under `grep -E`, and it carries no single
   quote. The quote matters because the gate emitter inlines this value.
5. **tier names**, **tier forms**: names unique, forms drawn from `all`,
   `links-and-paths`, `none`.
6. **generated `<path>`**: the regenerate command's first real argument resolves
   on PATH or under the root. An interpreter at the front is stepped past, so
   what gets resolved is the script it runs.
7. **team layer tracked**: the team file is committed (PASS), written but
   uncommitted (WARN, it has reached nobody else yet), or gitignored (FAIL, an
   ignored team layer never reaches the team).
8. **overlay ignored**: the personal overlay is gitignored, else WARN naming the
   recommended line `.claude/**/*.local.*`. Recommend it; never edit the
   consumer's `.gitignore`.
9. **policy floor**: a personal layer that declared a key only the team layer
   supplies is reported here and was ignored.

Exit 0 with no FAIL row, 1 with one, 2 on a usage or environment error.

## `apply` (idempotent)

1. Run `check` and read its table.
2. **Resolve the values.** With complete `<key>=<value>` arguments, use them.
   Otherwise interview one key at a time from the template, recommendation
   first: the scope roots, the casing rule and its regex, the three exemption
   sets, the tiers and their forms, the sweep exclusions, and the generated
   files with their regenerate commands.
3. **Persist.** One call per run:

   ```bash
   ${CLAUDE_SKILL_DIR}/scripts/setup-apply.sh --defaults
   ${CLAUDE_SKILL_DIR}/scripts/setup-apply.sh roots=["docs"] rule=lower-kebab
   ```

   `--defaults` writes the bundled document when no team layer exists. A
   `<key>=<value>` merges one key: the value is parsed as JSON when it parses
   and taken as a string when it does not, so `roots=["docs","guide"]` sets a
   list and `rule=lower-kebab` sets a scalar. The script prints
   `already configured` without touching the file when nothing changes, and
   writes `.claude/docs-hygiene.json` and nothing else.
4. **Verify.** Re-run `check` and report the persisted values from its table,
   never from the write alone. A WARN saying the file is untracked means "commit
   it to share it", never success.

## Completion criteria

The run is done when `check` prints a table with no FAIL row and, for `apply`,
the re-run check shows the intended values with their supplying layer. A FAIL
row that the operator decides to accept is still a FAIL: say which row and why
it was accepted rather than reporting a clean table.

## Output

`check`: the table as printed. `apply`: the table before and after, the written
path, and one line on re-running this skill to reconfigure. Name the layer that
supplied any value differing from the bundled default.

## What this skill does NOT do

- Write the user-global or overlay layers. Those are the operator's own files.
- Edit the consumer's `.gitignore`. It recommends one line.
- Install anything, or fetch a regenerator a `generated` entry names.
- Run an audit, a rename, or a gate emission. Those skills read the same
  resolved document at their own run time.
- Bump a version. A repository whose units are versioned bumps them itself after
  a rename; no version of these skills writes a manifest.

## Next

`/docs-hygiene:audit-file-names`

## Gotchas

- The team file must be committed to reach the team. `apply` leaves it untracked
  on purpose, and the `check` row says so until it is committed.
- A personal layer cannot narrow a tier, a sweep exclusion, or an exemption; it
  can only add. Those keys decide what a realign does to a tree, so the team
  layer wins a direct conflict and the ignored declaration is reported.
- `generated` is team-layer only. A regenerate command is a shell command the
  realign executes, so a personal layer never supplies or replaces one.
- A regex carrying a single quote passes every check here except `regex
  quoting`, then breaks the emitted gate, which inlines the value into a shell
  script.
- `check` resolves the team and overlay layers against the repository root of
  the working directory. Inside a second worktree, run it from that worktree, or
  pass `--root`.
