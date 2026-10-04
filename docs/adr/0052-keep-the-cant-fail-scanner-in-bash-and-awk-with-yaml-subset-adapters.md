# Keep the can't-fail scanner in bash and awk, with framework knowledge in YAML-subset adapters

- Status: accepted
- Date: 2026-09-28

## Context

`/testing:audit` and the testing hooks run one scanner, `cant-fail-scan.sh` and its awk engine,
over test files in every language the fleet writes tests in: JavaScript and TypeScript, Python,
C#, Go, Bash and PowerShell. The scanner runs on the hook path after each test-file edit, so its
cost per file and what it needs installed reach every consumer.

The choice was made on 2026-09-28, when the user asked for the scanner to take new languages and
frameworks without engine changes. It was recorded in the tautological-tests spec
([`docs/specs/tautological-tests.md` at `32553cf80`](https://github.com/melodic-software/claude-code-plugins/blob/32553cf80ed5210f6822f96f3fa0c01fa833e7b1/docs/specs/tautological-tests.md),
"Design contracts" and "Alternatives considered"). That spec has since been deleted from main, and
nothing else on main says why the alternatives lost: the loader's header
(`plugins/testing/skills/audit/scripts/adapter-load.awk:1-14`) states the file format and no
reason for it. This record was filed on 2026-10-04, after the spec's deletion, and carries the
decision's date.

Measured at decision time, the awk scanner took 4 to 5 ms per file and required nothing beyond
bash and a POSIX awk.

## Decision

1. The scanner engine stays bash plus POSIX awk. Rules, per-language lexers and block models are
   awk code and change only with a plugin release.
2. Everything specific to a test framework (file globs, detection, how a test starts, skip
   markers, assertion and mock vocabulary, snapshot and equality forms) lives in declarative
   adapter files under `plugins/testing/skills/audit/adapters/`. Thirteen ship today. Consumers add
   their own through `adapter_dirs`, in the same schema.
3. Adapter files use a restricted YAML subset, read by an awk loader (`adapter-load.awk`). The
   loader accepts only that subset and only regexes every supported awk (BSD awk, mawk, gawk)
   handles the same way; on anything else it stops with exit code 2 and reports the file and line
   number. The comment block at the top of `adapter-load.awk` defines the format.

## Alternatives considered

- **ast-grep as the engine.** Rejected: it ships no PowerShell grammar, and it would add an 8 to
  16 MB binary to every consumer. Revisit if a prebuilt PowerShell grammar appears or most fleet
  machines already have ast-grep.
- **Semgrep.** Rejected: roughly 1 s per file is too slow for a hook, the install is about 365 MB,
  and PowerShell support needs the paid edition. It remains an option for a rule that only runs in CI
  and reads several files at once, never for the hook path.
- **JSON adapter files read with `jq`.** Rejected because consumers would then write config in two
  formats: YAML for their testing settings and JSON for adapters. The `jq` dependency was not the
  reason, since sibling hooks already use it behind a missing-tool notice. Revisit if the awk loader
  stops passing its tests under mawk.

## Consequences

- A consumer needs nothing beyond bash and awk to run the scanner or the hooks, and the per-file
  cost stays in the low milliseconds.
- Supporting a new framework in a language the engine already lexes is an adapter file, with no
  plugin release. A new language, lexer or block model still needs one.
- The adapter format is narrower than YAML. Anchors, block scalars, double-quoted scalars and flow
  maps are errors, not silently misread, and the loader must keep working under all three awk
  implementations.
- Rules that need syntax-tree structure are limited to what a line-based lexer can see. A rule that
  awk cannot express is the trigger to revisit the ast-grep alternative for that rule alone.
- Scope: the rule that structured configuration is YAML validated by a JSON Schema
  ([standards `components/github-actions-conventions/README.md:133-136`](https://github.com/melodic-software/standards/blob/4974890822e6ef99ac695be25d2eb46398d7d68d/components/github-actions-conventions/README.md#L133-L136))
  governs a team's configuration files under `docs/conventions/`. It does not govern adapter data a
  plugin ships, and this ADR treats adapter files, shipped or consumer-added, as scanner input under
  the loader's own schema.
