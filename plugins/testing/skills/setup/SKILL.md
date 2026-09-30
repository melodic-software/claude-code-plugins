---
description: "Configure the testing plugin's can't-fail checks for this repository. check prints the resolved .claude/testing.yaml cascade, which test-lint rules the repo's lint config turns on per language (a missing one is a finding), an optional instruction line to paste, and a settings hook entry for any test glob the shipped test-scan hook skips; apply writes only .claude/testing.yaml from your answers. Use when: 'set up testing', 'configure the test scan', 'exclude these tests from the audit', 'add a test glob', 'which test lint rules are missing', 'testing setup'. Re-runnable."
argument-hint: "check | apply"
user-invocable: true
disable-model-invocation: true
---

## Purpose

`/testing:audit` and the opt-in `test-scan` hook find tests by the shipped adapters' filename globs
and judge them by the shipped rule levels. This skill shows what a repository changed about that
through `.claude/testing.yaml`, and writes that file. `check` changes nothing; `apply` runs `check`,
asks, writes, and runs `check` again. No argument means `check`.

It never edits `CLAUDE.md` or `AGENTS.md`. The instruction line is printed for you to paste.

## The config

`.claude/testing.yaml` resolves across the config-cascade layers, in order: `~/.claude/testing.yaml`,
`<root>/.claude/testing.yaml` (the team file this skill writes) and `<root>/.claude/testing.local.yaml`,
where `<root>` is the scanned file's git toplevel, else `${CLAUDE_PROJECT_DIR}`. Lists concatenate across layers; a later layer's scalar overrides.
The format is the adapters' YAML subset; a glob that starts with `*` must be single-quoted.

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
test blocks, assertions, a changed expected value, or an added skip. By default it only asks the
agent for its reason. With `test-weaken-block: error`, an added skip or a removed test block is
denied until the edit carries a `test-change: <reason>` comment; removed assertions and changed
expected values are never denied. The agent can write that marker itself: it makes the reason
visible to reviewers, it does not prove the reason.

Removals (`adapters.disable`, `paths.exclude`, `rules ... off`) apply inside the scanner, so the
audit and the `test-scan` hook go quiet with no plugin change; an excluded path or a disabled
adapter silences `test-weaken` too. Additions reach the audit at once, and the
hook only through the settings entry `check` prints.

## `check` (read-only)

Run the script and show its output as it prints:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/setup/scripts/setup.sh" check
```

It exits 0 with no finding, 1 when a test-lint rule is missing, 2 when a layer does not resolve
(the file and line are on stderr). Its four sections:

1. **config**: the resolved records, or the note that no layer exists.
2. **lint**: one row per rule for each language the repository's tracked test files use. The script
   reads the lint config as text: a rule named there, or its plugin referenced beside a recommended
   config, reads as present. Treat a `PRESENT` row from the recommended-config path as likely rather
   than proven, and say so. A `FINDING` is a gap to report, not a neutral absence. The rules:
   - JS/TS: `jest/valid-expect` (eslint-plugin-jest), `vitest/valid-expect` (`@vitest/eslint-plugin`),
     `playwright/missing-playwright-await` and `playwright/no-focused-test` (eslint-plugin-playwright).
     Each is in its plugin's recommended config. Verified 2026-09-29 against the plugins' README and
     rule pages (github.com/jest-community/eslint-plugin-jest, vitest-dev/eslint-plugin-vitest,
     playwright-community/eslint-plugin-playwright); recheck when a plugin release note moves one of
     these rules out of its recommended config or renames it.
   - C#: `xUnit2021` (xunit.analyzers, which the `xunit` 2.3+ and `xunit.v3` packages bring in;
     `xunit.core` alone does not) and `NUnit2009` (NUnit.Analyzers, a separate package the `nunit`
     template adds). Verified 2026-09-29 against xunit.net/xunit.analyzers/rules/xUnit2021, the
     xunit.analyzers README and the NUnit2009 page in nunit/docs; recheck when an xunit or NUnit
     release note changes how the analyzers are packaged.
   - Python: ruff `PLR0124`, `PT011` and `F631`. Ruff's default rule set holds `PLR0124` and `F631`
     but not `PT011`; a `select` replaces the defaults and selectors match by prefix. Verified
     2026-09-29 against docs.astral.sh/ruff/default-rules and /linter (only part of the default list
     was read); recheck when a ruff release note changes the default rule set.
   - Bash, PowerShell and Go: no maintained rule.
3. **instruction**: the optional line. Offer it; do not paste it anywhere.
4. **hook-entry**: `none`, or a `.claude/settings.json` snippet for each consumer glob no shipped
   hook row matches. A settings hook receives no `CLAUDE_PLUGIN_ROOT` or `CLAUDE_PLUGIN_OPTION_*`
   (probed on Claude Code 2.1.284, 2026-09-29, `docs/specs/tautological-tests/probes.md` in the
   marketplace repository; recheck when a Claude Code release note says settings hooks receive
   plugin variables), so the entry runs the highest installed version under
   `~/.claude/plugins/cache/<marketplace>/testing` and passes `--enabled`: adding the entry is the
   opt-in. It pins the marketplace `check` runs from; when `check` runs outside the plugin cache the
   entry holds a `<marketplace>` placeholder the user must replace. With no installed copy that takes
   `--enabled`, the entry says so on stderr and exits 0. Show it; the user merges it into their
   settings.

Then probe the hook launcher, which the script does not: run `command -v node` via Bash and report
`node` as a FAIL row when it is absent. Every hook row launches through `node hooks/exec-bash.mjs`,
so a missing `node` is a hook launch error, not a skip notice, and a hook cannot report its own
missing launcher.

## `apply`

1. Run `check` and summarize the effective config before proposing a change. Nothing already
   configured is dropped without the user confirming.
2. Ask only what the repository cannot answer: folders or files to leave out, test files the
   shipped globs miss (and which adapter reads them), adapters to turn off, rule levels.
3. Write the team file with the answers. The script writes `.claude/testing.yaml` whole, keeps it
   only when it resolves, and writes nothing else; pass every value the file should hold, the
   existing ones included:

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/skills/setup/scripts/setup.sh" apply \
     --exclude 'legacy/**' --extend js-vitest.files='*.it.ts' --rule weak-oracle=warn
   ```

   Flags: `--include`, `--exclude`, `--enable`, `--disable`, `--adapter-dir`,
   `--extend <id>.<field>=<value>`, `--rule <rule>=off|warn|error`, each repeatable.
4. Run `check` again and show the hook entry if one is printed. Offer `git add .claude/testing.yaml`
   and a commit, and run each only when the user accepts. Personal overrides go in
   `.claude/testing.local.yaml`, which should be gitignored.

## Next

/testing:audit
Runs the scan with the config this skill wrote.

## What this skill does NOT do

- Edit `CLAUDE.md`, `AGENTS.md`, `.claude/settings.json`, or any lint config. It prints what to add.
- Install a lint plugin or analyzer.
- Run the audit. That is `/testing:audit`.
