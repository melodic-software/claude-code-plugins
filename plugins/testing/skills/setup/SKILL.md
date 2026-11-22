---
description: "Configure the testing plugin's can't-fail checks for this repository. check prints the resolved testing config cascade, which test-lint rules the repo's lint config turns on per language (a missing one is a finding), an optional instruction line to paste, and any test glob the shipped test-weaken hook skips; apply writes your answers to docs/conventions/testing.yaml (or to the docs/conventions/testing.md block or .claude/testing.yaml when that is the team file in use). Use when: 'set up testing', 'configure the test scan', 'exclude these tests from the audit', 'add a test glob', 'which test lint rules are missing', 'testing setup'. Re-runnable."
argument-hint: "[check|apply]"
user-invocable: true
disable-model-invocation: true
---

## Purpose

`/testing:audit` and the opt-in `test-weaken` hook find tests by the shipped adapters' filename globs
and judge them by the shipped rule levels. This skill shows what a repository changed about that
through the testing config, and writes it. `check` changes nothing; `apply` runs `check`,
asks, writes, and runs `check` again. No argument means `check`.

It never edits `CLAUDE.md` or `AGENTS.md`. The instruction line is printed for you to paste.

## The config

The testing config resolves across the config-cascade layers, in order: `~/.claude/testing.yaml`,
the team layer and `<root>/.claude/testing.local.yaml`, where `<root>` is the scanned file's git
toplevel, else `${CLAUDE_PROJECT_DIR}`. The team layer is `<root>/docs/conventions/testing.yaml`.
Without it, the team layer is the `yaml config` block in `<root>/docs/conventions/testing.md`
(read for one more release), else `<root>/.claude/testing.yaml`; the first present wins and the
resolver prints a warning naming each one it ignores. Lists concatenate across layers; a later
layer's scalar overrides. The format is the adapters' YAML subset in every file; a glob that starts
with `*` must be single-quoted. `docs/conventions/testing.yaml` also holds `/testing:run-e2e`'s
`e2e_driver`, `reuse_running_instance`, `browser_driver`, `map_unit`, `map_entry_points`,
`map_report_order`, `file_findings` and `file_findings_floor`, and `/testing:write`'s
`tdd_refactor_step` and `first_test`, which the scan ignores.

This plugin still reads, or reports as retired, the `.claude/` paths named here; until the plugin migrates, keep config where this page says it is read, then move it where [config locations](../../reference/config-locations.md) says.

The keys:

```yaml
adapters:
  disable: [py-unittest]         # wins over enable; a non-empty enable list is an allowlist
paths:
  exclude: ['legacy/**']         # relative to the repo root; ** crosses /, * does not
  include: ['build/**/*.test.ts'] # reaches pruned folders; an adapter must still claim the file
adapter_dirs: [tools/test-adapters]  # consumer adapters, same schema as the shipped ones
extend:
  js-vitest:
    files: ['*.it.ts']           # appended to that adapter's list field
rules:
  rule-weak-oracle: off          # off drops, warn reports without gating, error gates --check
  test-weaken-block: error       # test-weaken hook: deny an added skip or a removed test
```

The opt-in `test-weaken` hook runs before a Write or Edit to a test file and names what it removes:
test blocks, assertions, a changed expected value, or an added skip. By default it only tells the
agent. With `test-weaken-block: error`, an added skip or a removed test block is
denied until the edit carries a `test-change: <reason>` comment; removed assertions and changed
expected values are never denied. The agent can write that marker itself: it makes the reason
visible to reviewers, it does not prove the reason.

Removals (`adapters.disable`, `paths.exclude`, `rules ... off`) apply inside the scanner, so the
audit goes quiet with no plugin change; an excluded path or a disabled adapter silences
`test-weaken` too. Additions reach the audit at once; `test-weaken` covers only the shipped globs.

## The test judge

The judge that asks where each changed test's expected value came from runs on demand, as
`/testing:audit --judge`, and in `/source-control:pull-request` prep. It has no plugin option and
no hook.

## `check` (read-only)

Run the script and show its output as it prints:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/setup/scripts/setup.sh" check
```

It exits 0 with no finding, 1 when a test-lint rule is missing, 2 when a layer does not resolve
(the file and line are on stderr). Its five sections:

1. **config**: the resolved records, or the note that no layer exists.
2. **old paths**: each testing config file found at an old path, the location to move it to, and a
   preview of what a copy would write there. The old paths and their new locations:

   | Old path | New location |
   |---|---|
   | `.claude/testing.yaml` | `<home>/testing.yaml` |
   | `.claude/testing.local.yaml` | `<home>/testing.local.yaml` |
   | `~/.claude/testing.yaml` | each key's `userConfig` option, else `<home>/testing.local.yaml` |
   | `.claude/testing/e2e.md` | `<home>/testing/e2e.md` |
   | `.claude/testing/e2e.local.md` and `~/.claude/testing/e2e.md` | `<home>/testing/e2e.local.md` |
   | `.claude/testing/worst-case.md` | `<home>/testing/worst-case.md` |

   A copy writes a whole file into a new location that does not exist yet, else appends the old
   file's top-level YAML keys the new file lacks. A copy leaves out three things the section names
   for the user to handle by hand: a key both files set, a key of `~/.claude/testing.yaml` with a
   `userConfig` option (set the option), and a Markdown file whose new location exists. A personal (`.local.`) location must be
   gitignored before a copy. A user-global file (`~/.claude/testing.yaml`, `~/.claude/testing/e2e.md`)
   is not copied while its new location is absent and the repository's old personal file for that
   location exists: creating the location would stop that file being read, so copy it first. The
   old file always stays in place.
3. **lint**: one row per rule for each language the repository's tracked test files use. The script
   reads the lint config as text: a rule named there, or its plugin referenced beside a recommended
   config, reads as present. Treat a `PRESENT` row from the recommended-config path as likely rather
   than proven, and say so. A `FINDING` is a gap to report, not a neutral absence. The rules:
   - JS/TS: `jest/valid-expect` (eslint-plugin-jest), `vitest/valid-expect` (`@vitest/eslint-plugin`),
     `playwright/missing-playwright-await` and `playwright/no-focused-test` (eslint-plugin-playwright).
     Which config each sits in is its rule page's to state:
     [jest/valid-expect](https://github.com/jest-community/eslint-plugin-jest/blob/main/docs/rules/valid-expect.md),
     [vitest/valid-expect](https://github.com/vitest-dev/eslint-plugin-vitest/blob/main/docs/rules/valid-expect.md),
     [playwright/missing-playwright-await](https://github.com/playwright-community/eslint-plugin-playwright/blob/main/docs/rules/missing-playwright-await.md),
     [playwright/no-focused-test](https://github.com/playwright-community/eslint-plugin-playwright/blob/main/docs/rules/no-focused-test.md).
     As of 2026-11-10; recheck when a plugin release note moves one of these rules out of its
     recommended config or renames it.
   - C#: `xUnit2021` (xunit.analyzers, which the check counts as present through an `xunit` or
     `xunit.v3` reference) and `NUnit2009` (NUnit.Analyzers, which the check requires as its own
     reference). Packaging: [xUnit2021](https://xunit.net/xunit.analyzers/rules/xUnit2021) and
     [NUnit2009](https://docs.nunit.org/articles/nunit-analyzers/NUnit2009.html). As of 2026-11-10;
     recheck when an xunit or NUnit release note changes how the analyzers are packaged.
   - Python: ruff `PLR0124`, `PT011` and `F631`. The check counts `PLR0124` and `F631` as on with no
     `select`, `PT011` as off, and a `select` as replacing the defaults with prefix matching
     (`setup.sh` `ruff_rule`). Pointer: [ruff settings § lint.select](https://docs.astral.sh/ruff/settings/#lint_select)
     and the rule pages for [PLR0124](https://docs.astral.sh/ruff/rules/comparison-with-itself/),
     [PT011](https://docs.astral.sh/ruff/rules/pytest-raises-too-broad/) and
     [F631](https://docs.astral.sh/ruff/rules/assert-tuple/). As of 2026-11-10; recheck when a ruff
     release note changes the default rule set.
   - Bash, PowerShell and Go: no maintained rule. For a can't-fail test pattern in one of these
     languages, name the call `/corrections:codify "<the test pattern>"` for the user to run;
     `check` builds no mechanism. When `/corrections:codify` is among the available skills, hand
     it the choice of mechanism; it picks the strongest rung of the enforcement ladder that can
     decide the rule and proves the check. Otherwise, propose the strongest mechanism that can
     decide the rule: a change that makes the mistake impossible first, then a check that blocks
     it, then a test, and an instruction only when nothing a machine runs can decide it. Say that
     `/corrections:codify` was not available, so the proposal is unproven.
   - Any other detected language: named with `setup has no lint check for this language`, not a
     finding. For a can't-fail test pattern in that language, name the call
     `/corrections:codify "<the test pattern>"` for the user to run; `check` builds no mechanism.
     When `/corrections:codify` is among the available
     skills, hand it the choice of mechanism; it picks the strongest rung of the enforcement ladder
     that can decide the rule and proves the check. Otherwise, propose the strongest mechanism that
     can decide the rule: a change that makes the mistake impossible first, then a check that
     blocks it, then a test, and an instruction only when nothing a machine runs can decide it.
     Say that `/corrections:codify` was not available, so the proposal is unproven.
4. **instruction**: the optional line, naming one file Claude Code loads at the repository
   root: `CLAUDE.md`, else `.claude/CLAUDE.md`, else `CLAUDE.local.md`, else `AGENTS.md`, else `CLAUDE.md` in
   `${CLAUDE_CONFIG_DIR:-~/.claude}` (the script's order). Which files load, and when `AGENTS.md` is
   read: [memory § When Claude Code reads AGENTS.md](https://code.claude.com/docs/en/memory#when-claude-code-reads-agents-md). Offer it as a pointer: it
   names the `testing:test-value` skill and, when `docs/conventions/testing.md` exists, adds a line
   pointing at that team file; do not paste it anywhere. A test rule a check could decide goes to
   `/corrections:codify "<the test pattern>"` instead of the instruction line, named for the user
   behind the same availability gate and fallback as the lint rows above.
5. **hook-entry**: a `none:` line saying test-quality findings come from `/testing:audit`, not a
   per-edit hook, then, when a consumer glob matches no shipped `test-weaken` row, a line naming
   those globs: the audit scans them, `test-weaken` skips them. No settings entry is printed.

Then probe the hook launcher, which the script does not: run `command -v node` via Bash and report
`node` as a FAIL row when it is absent. Every hook row launches through `node hooks/exec-bash.mjs`,
so a missing `node` is a hook launch error, not a skip notice, and a hook cannot report its own
missing launcher.

## `apply`

1. Run `check` and summarize the effective config before proposing a change. Nothing already
   configured is dropped without the user confirming. For each file the old paths section names
   with a copy preview, show that preview and ask whether to copy it. On a yes, run the command
   the section prints for that file, one file per yes; `--copy-old` takes no answer flags and
   writes nothing else. Pass the old path exactly as the section prints it: it is already quoted
   for the shell.

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/skills/setup/scripts/setup.sh" apply --copy-old <old file as printed>
   ```

2. Ask only what the repository cannot answer: folders or files to leave out, test files the
   shipped globs miss (and which adapter reads them), adapters to turn off, rule levels.
3. Write the team layer with the answers. The script writes the team file in use:
   `docs/conventions/testing.yaml` whole (keeping its `e2e_driver`, `reuse_running_instance`, `browser_driver`,
   `map_unit`, `map_entry_points`, `map_report_order`, `file_findings`, `file_findings_floor`,
   `tdd_refactor_step` and `first_test` lines), else the body of the `yaml config` block in `docs/conventions/testing.md` (the rest of
   that file stays), else `.claude/testing.yaml` whole; with none, it creates
   `docs/conventions/testing.yaml`. It keeps the result only when it resolves and writes nothing
   else; pass every value the team layer should hold, the existing ones included:

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/skills/setup/scripts/setup.sh" apply \
     --exclude 'legacy/**' --extend js-vitest.files='*.it.ts' --rule weak-oracle=warn
   ```

   Flags: `--include`, `--exclude`, `--enable`, `--disable`, `--adapter-dir`,
   `--extend <id>.<field>=<value>`, `--rule <rule>=off|warn|error`, each repeatable.
4. Run `check` again. Offer `git add` for the file
   `apply` printed and a commit, and run each only when the user accepts. Personal overrides go in
   `<home>/testing.local.yaml`, which should be gitignored. `check` also prints the optional line
   to paste into `CLAUDE.md` or `AGENTS.md` that points at `docs/conventions/testing.md` when that
   file exists; a test rule a check could decide goes to `/corrections:codify` instead, as
   `check`'s instruction section says.

## Next

/testing:audit
Runs the scan with the config this skill wrote.

## What this skill does not do

- Edit `CLAUDE.md`, `AGENTS.md`, `.claude/settings.json`, or any lint config. It prints what to add.
- Install a lint plugin or analyzer.
- Run the audit. That is `/testing:audit`.
