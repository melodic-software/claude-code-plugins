---
description: "Verify or configure the docs-naming file-name skills for this repository: `check` resolves all three configuration layers, reports which layer supplied each key, and verifies that the casing regex compiles, every tier names a known form, every generated file's regenerator resolves, the team layer is tracked, and the personal override is ignored; `apply` writes the tracked `docs/conventions/docs-naming.yaml` team layer per key, idempotently, and edits no other file. Use when: 'set up docs-naming', 'configure the file-name rule', 'is docs-naming configured', 'which casing rule is in effect', 'change the docs naming regex', 'add a frozen tier', 'docs-naming setup', or an audit reports a configuration layer it could not read."
argument-hint: "[check|apply] [--defaults] [<key>=<value> ...]"
user-invocable: true
disable-model-invocation: true
allowed-tools: ["Bash(${CLAUDE_SKILL_DIR}/scripts/setup-check.sh:*)", "Bash(${CLAUDE_SKILL_DIR}/scripts/setup-apply.sh:*)", "Bash(git check-ignore:*)", "Bash(git ls-files:*)", "Read"]
shell: bash
---

## Purpose

Every value the file-name skills act on comes from one consumer surface,
layered as `userConfig` (this plugin's `file_names` option, one JSON object of
`file_names` keys), team (`docs/conventions/docs-naming.yaml`, tracked,
validated by `${CLAUDE_PLUGIN_ROOT}/schemas/docs-naming.schema.json`), and
personal override (`docs/conventions/docs-naming.local.yaml`). The convention
home is `docs/conventions` unless the repository's `AGENTS.md` or `CLAUDE.md`
binds another. All three absent is a valid state: every key has a bundled
default, and the defaults are this marketplace's own values, except `generated`,
which is empty. The old team and personal override JSON files under `.claude/`
are not read; `check` names each, and `apply` seeds an absent team YAML from the
old team file.

The old user files, `~/.claude/docs-naming.json` and
`~/.claude/docs-hygiene.json`, are still read in the option's place while the
option is unset or invalid (the first that exists), each run warns about them,
and `apply` previews copying their keys into the option.

The option's current value is `${user_config.file_names}`. Pass it to both
scripts as `--user-config '<that value>'`, one single-quoted argument (escape
any single quote in it): a Bash command never sees the option otherwise. An
empty value or the literal `${user_config.…}` placeholder means unset.

This skill is the check-centric setup for that surface: `check` inspects and
verifies, `apply` persists, and neither installs anything. Keys, defaults, layer
classes, and provenance live in
[`${CLAUDE_PLUGIN_ROOT}/reference/config.md`](${CLAUDE_PLUGIN_ROOT}/reference/config.md).

Action routing: no argument or `check` runs the check; `apply` runs the check
first, then persists. `check` asks nothing. With `apply` and no key, interview
one key at a time, recommendation first, walking the annotated template
[`${CLAUDE_SKILL_DIR}/templates/docs-naming.json`](templates/docs-naming.json).

## `check` (read-only)

Run it and present the table as printed:

```bash
${CLAUDE_SKILL_DIR}/scripts/setup-check.sh --user-config '<option>'
```

Rows, each PASS, FAIL, WARN, or INFO:

1. **jq**, **git**: the prerequisites. A missing `jq` is FAIL and stops the
   table, because every skill in this plugin reads the concern file with it.
2. **layer userConfig / team / personal-override**: absent (INFO), or present
   (the team and personal override rows name the file). The userConfig row is
   WARN when the option is not one JSON object, which is ignored. A present file
   that does not parse, or an old user file that declares an unknown schema,
   surfaces at the **resolve** row with the file named. **old user file**: WARN
   per file at an old user path, saying whether it is read and that `apply`
   previews copying its keys into the option. **old team file** and **old
   personal override file**: WARN per unread JSON file under `.claude/`, naming
   the next step (`apply` seeds an absent team YAML, else copy by hand; then
   delete).
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
8. **personal override ignored**: the personal override is gitignored, else WARN naming the
   recommended line, `<home>/*.local.*` (the row prints it). Recommend it; never
   edit the consumer's `.gitignore`.
9. **policy floor**: a personal layer that declared a key only the team layer
   supplies is reported here and was ignored.

Exit 0 with no FAIL row, 1 with one, 2 on a usage or environment error.

## Retired conventions

`check` also runs this step on every invocation:
`bash "${CLAUDE_PLUGIN_ROOT}/lib/check-retirements.sh" --manifest "${CLAUDE_PLUGIN_ROOT}/retirements.yaml"`.
Exit 0 → PASS. Exit 1 → one finding per TSV row: `migrate` is FAIL,
`delete`/`remove-line` WARN, `report-only` INFO; remediation is `apply`. Exit 2 →
FAIL, never silent. Bash unavailable → report the step UNKNOWN with remediation,
never green.

Both records here, `docs-naming-r001` (`.claude/docs-hygiene.json`) and
`docs-naming-r002` (`.claude/docs-hygiene.local.json`), are `report-only`: INFO,
no cleanup, since neither file is read; the old-file rows name the next step. The old
user files under `~/.claude/` sit outside the repository and have no record; the
**old user file** rows report them, and `apply` step 5 handles them.

This plugin still reads, or reports as retired, the `.claude/` paths named here; until the plugin migrates, keep config where this page says it is read, then move it where [config locations](../../reference/config-locations.md) says.

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
   writes `docs/conventions/docs-naming.yaml` (under the repository's convention
   home) and nothing else. When the YAML is absent and an old team JSON file
   exists (`.claude/docs-naming.json`, else `.claude/docs-hygiene.json`), the
   first write seeds the YAML from it, so its settings carry over; the resolver
   does not read that file. The JSON file stays until a person deletes it. A rewrite keeps the comment block at the top of the file
   and drops comments between keys.
4. **Clean up retired files.** After any agreed keys are written, re-run the
   retirement detection and handle each active finding behind its own
   confirmation (a `report-only` finding is INFO and has no cleanup). A
   retired file's `file_names` keys are carried into the YAML of its layer as
   top-level keys, adding only the ones that file lacks (step 3 already seeded a
   team YAML that did not exist). The old file's
   content is untrusted input, never executed or interpolated. When the operator
   confirms the result, run
   `bash "${CLAUDE_PLUGIN_ROOT}/lib/check-retirements.sh" --manifest "${CLAUDE_PLUGIN_ROOT}/retirements.yaml" --clean <id> --i-migrated`.
   Re-run detection last and report the final state.
5. **Copy old user files into the option.** When `check` printed an **old user
   file** row, run:

   ```bash
   ${CLAUDE_SKILL_DIR}/scripts/setup-apply.sh --user-config-value --user-config '<option>'
   ```

   It writes nothing. It prints a `from:` line per old file naming the keys it
   would add (only keys the option does not already set; `docs-naming.json`
   before `docs-hygiene.json`), the merged `value:`, and a `values.json:` line.
   Show that preview and ask whether to copy. On a yes, the operator saves it
   through Claude Code's native flow, `/plugin configure docs-naming@<marketplace>`
   interactively; this skill never writes user settings or `pluginConfigs`, and
   never uninstalls to reconfigure. Read
   [The routes](../../reference/plugin-reconfiguration.md#the-routes) and
   [Caveats every setup skill's short form carries](../../reference/plugin-reconfiguration.md#caveats-every-setup-skills-short-form-carries)
   and print what they give: the preferred `claude plugin configure` command in
   full first, with the `values.json:` text as its `values.json`, then the
   fallback route, its behavior on an already-installed plugin and the scope to
   pass. Leave the old file in place; the operator deletes it once a
   **fresh-session** `check` shows the option set and no key missing. Report
   only an observed value.

   - **Pointer**: for the headless command's flags and how it reports a saved
     or refused value, fetch
     [plugin CLI reference § plugin configure](https://code.claude.com/docs/en/plugins/cli-reference#plugin-configure)
     live.
6. **Verify.** Re-run `check` and report the persisted values from its table,
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

- Write the personal override, the `file_names` option, user settings, or
  `pluginConfigs`. Those are the operator's own; step 5 hands the option's value
  to Claude Code's native flow.
- Delete or edit an old user file.
- Edit the consumer's `.gitignore`. It recommends one line.
- Install anything, or fetch a regenerator a `generated` entry names.
- Run an audit, a rename, or a gate emission. Those skills read the same
  resolved document at their own run time.
- Bump a version. A repository whose units are versioned bumps them itself after
  a rename; no version of these skills writes a manifest.

## Next

`/docs-naming:audit-file-names`

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
- `check` resolves the team layer and personal override against the repository root of
  the working directory. Inside a second worktree, run it from that worktree, or
  pass `--root`.
