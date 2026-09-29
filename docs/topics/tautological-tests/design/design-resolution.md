---
outcome: early-exit
tier: A (light)
date: 2026-09-28
---

# Design resolution: test-value guards

The interview (Brief Q1-Q13) fixed the module boundaries: the work extends `testing`, with small
changes in `mutation-testing`, `review`, `implementation` and `debugging`. The user accepted an early
exit from full `/planning:design` on 2026-09-28 and asked for the plugin to be extensible to other
languages and frameworks. This file records the contracts the plan depends on. Evidence:
`.work/tautological-tests/extensibility/RESEARCH.md` (engine options, measured timings, adapter
schema) and the fleet language inventory taken the same day.

## 1. Scanner engine: awk rules, lexer families, block models, adapter data

The scanner stays pure bash plus POSIX awk. Measured at 4-5 ms per file, with nothing to install.
All knowledge of individual languages and frameworks moves out of the awk source and into
declarative adapter files.

| Layer | Form | Closed or open | Contents |
|---|---|---|---|
| Rules | awk, language-neutral | closed (plugin release) | zero-assertion, recomputed-expectation, mock-only-oracle, plus the new rules in section 4 |
| Lexer families | awk | closed | `c-like` (JS/TS, C#, Go, Rust, Java, Kotlin), `shell` (Bash, bats, PowerShell `<# #>`), `python` |
| Block models | awk | closed | `brace`, `indent`, `file` (hand-rolled Bash, which has no per-case marker) |
| Adapters | data files | open (consumers add) | globs, detection, test start, skips, assertion calls and idioms, delegation, mocks, snapshots, equality forms |

Adding a language means writing an adapter that names an existing lexer family and block model. A
new lexer family or block model needs a plugin release.

## 2. Adapter file contract

- Location: `plugins/testing/skills/audit/adapters/<id>.yaml`. Consumer adapters live in
  directories named by `adapter_dirs` and use the same schema.
- Format: a restricted YAML subset: block maps, block lists, one-line flow lists, plain or
  single-quoted scalars, and dotted keys. The loader strips `\r` and validates regexes against a
  portable ERE subset for gawk, mawk and BSD awk. The awk loader parses exactly that subset and
  rejects anything else with exit 2, naming the file and line. This adds no dependency (`jq`, `yq`,
  Python). The loader's header comment (`scripts/adapter-load.awk`) is the schema of record.
- Fields: `id`, `extends`, `language`, `block_model`, `files`, `detect.any_regex`, `test_start`,
  `test_skip`, `suite_skip`, `assertion.calls`, `assertion.idioms`, `mock.create`, `mock.verify`,
  `mock.strip`, `snapshot`, `equality.call2`, `equality.receiver`, `suppress_marker`.
  - `language` names the lexer and block state machine, one per language: `js`, `cs`, `python`.
    JS and C# need different comment/string maskers, so they do not share a family key. Phase 3
    adds a key per new lexer it needs.
  - `block_model` is `brace` or `indent`, and must suit the language.
  - Every list field is a list of EREs, except `files` (basename globs), `equality.call2` (helper
    names matched as substrings) and `equality.receiver` (`<wrapper>.<matcher>`, as in
    `expect.toBe`).
  - `extends: <id>` inherits every field the adapter does not set. When several adapters claim a
    file, the one whose `detect.any_regex` matches wins; otherwise the first in load order
    (sorted file names).
- `additional_test_blocks`, `delegation` and `equality.pipeline` are reserved: the loader rejects
  them until engine code reads them, so a value is never dropped silently.
- `astgrep_rules` is reserved and not implemented. It is switch S1 in the research: an optional
  ast-grep backend for one rule, added only when the fixture corpus shows awk missing
  argument-structure cases.

Wave-1 adapters, taken from the fleet inventory (Brief Q5 as amended 2026-09-28): `bash-harness`
(hand-rolled `*.test.sh`), `bash-bats`, `pwsh-pester`, `cs-xunit`, `cs-nunit`, `cs-mstest` (with
Shouldly, FluentAssertions, NSubstitute, Moq and Verify vocabulary), `js-vitest`, `js-jest`,
`js-node-test`, `js-playwright`, `py-pytest`, `py-unittest`, `go-testing`. Wave 2 is Rust,
Java/Kotlin and Go testify.

## 3. Test-file pattern list and `.claude/testing.yaml`

- One source: the union of every shipped adapter's `files:` globs. `hooks/hooks.json` `if` filters
  are generated from that union by `scripts/gen-hook-filters.sh`. A `--check` mode fails CI when the
  two drift. No bare `test/` or `tests/` folder pattern is allowed (Q6).
- `.claude/testing.yaml` resolves through the config-cascade layers: `~/.claude/testing.yaml`, then
  `${CLAUDE_PROJECT_DIR}/.claude/testing.yaml`, then `.claude/testing.local.yaml`. Merge semantics
  are additive: lists concatenate, and a scalar in a later layer overrides an earlier one. The
  resolver is a plugin-local script modeled on `plugins/docs-hygiene/scripts/resolve-config.sh`. It
  is not imported from that plugin (shell-test-helpers convention: no cross-plugin imports).
- Keys: `adapters.enable`, `adapters.disable`, `paths.include`, `paths.exclude`, `extend.<adapter>.<field>`,
  `adapter_dirs`, `rules.<rule-id>: off | warn | error`.
- Removals (`adapters.disable`, `paths.exclude`) apply inside the script, so hook and audit go silent
  with no plugin change.
- Additions (`paths.include`, consumer adapters with new globs) reach the audit at once. They reach
  the hook only through a consumer hook entry that `/testing:setup check` prints for pasting (Q6).
  The audit report lists any consumer glob that no hook filter covers, so a skip is never silent.

## 4. New scanner rules (release 1)

Rule IDs follow `testing/audit/rule-<name>` (detector-findings contract). Every new rule needs a
severity-crosswalk row and eval coverage.

| Rule | Detects | Posture in release 1 |
|---|---|---|
| `rule-inert-assertion` | Python tuple assert, bare `.Should()`, unawaited async matcher, `expect` only inside `catch` | advisory |
| `rule-constant-restatement` | expected value equals a literal defined in the production module the test imports | advisory |
| `rule-source-text-read` | test reads a production source file as text (`readFileSync`, `open(...).read()`, `File.ReadAllText`, `Get-Content`, `cat`) | advisory |
| `rule-snapshot-only` | snapshot or `Verify` is the only assertion in the block | advisory |
| existing `rule-zero-assertion`, `rule-recomputed-expectation` | as today, now driven by adapters | eligible to block after the precision run (D4) |

## 5. Hooks

Both hooks are gated by `userConfig.test_guards_enabled` (boolean, default `false`), read in the
script as `CLAUDE_PLUGIN_OPTION_TEST_GUARDS_ENABLED`. They are exec-form, with `if` filters
generated as described in section 3. A script error or timeout lets the edit proceed and logs the
failure.

| Hook | Event | Input | Output |
|---|---|---|---|
| `test-scan` | PostToolUse `Write\|Edit\|MultiEdit` | written file path; for Edit, the new hunk | findings whose test block overlaps the changed hunk (hook-precision rule 1), fed back through `additionalContext`. For a doubtful hit it asks the agent to state where the expected value comes from, in the same turn (Q7 tier 2). The first test-file write per file per session also injects the rules-skill note (Q2). |
| `test-weaken` | PreToolUse `Edit\|MultiEdit\|Write` | `old_string` and `new_string`, or the old file versus the new content | removed assertion, added skip, removed test block, or changed expected value. Release 1: allow and inject context that asks the agent for its reason. After the precision run, deleted or skipped tests may deny with a reason, and the agent retries with a `test-change: <reason>` marker (D5). |

Once-per-session state lives under `${CLAUDE_PLUGIN_DATA}`, keyed by `session_id`, `agent_id` and
the normalized file path. The marker is an atomic `mkdir`, and markers older than 7 days are pruned.
`test-weaken` returns `additionalContext` with no `permissionDecision` field while advisory.

Lint-rule presence (eslint-plugin-jest/vitest/playwright, xUnit2021, NUnit2009, ruff PLR0124) is
reported by `/testing:setup check`, not by the scanner. It reads lint config, not test bodies, and
Bash, Pester and Go have no maintained rule.

The option gate uses exec-form `--require-true TEST_GUARDS_ENABLED`. A hook `if` row cannot read a
userConfig value, so while the option is off each matching test-file write starts one launcher
process that exits at once. Non-test paths start none.

## 6. Rules skill

`testing:test-value` is model-invoked. It holds the one statement of what makes a test worth
keeping: where expected values come from, the taxonomy, and Pocock's examples. Three things load
it: auto-invocation, a `skills:` preload in `implementer`, `phase-verifier` and `code-reviewer`, and
the hook note. Other skills carry a one-line pointer.
