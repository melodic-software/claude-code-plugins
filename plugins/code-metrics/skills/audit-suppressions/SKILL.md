---
description: "List every lint and type-checker suppression in a change, a path, or the tree (`--all`): eslint-disable, @ts-expect-error, noqa, type: ignore, pylint, pyright, shellcheck disable, C# pragmas and SuppressMessage, nolint, PowerShell SuppressMessageAttribute, markdownlint, rubocop, @SuppressWarnings. Each row names its rule ids, its reason, and whether it is justified; listed correctness rules are marked. Reports, never gates. Use when: 'how many suppressions', 'find eslint-disable comments', 'which noqa have no reason', 'suppressions added in this change', 'audit lint suppressions', 'count suppressions to ratchet'. Complexity: /code-metrics:audit-complexity."
argument-hint: "[--json|--findings [--memory-dir <dir>]] [--all] [--base <ref>] [<path>...]"
user-invocable: true
disable-model-invocation: false
allowed-tools: ["Bash(${CLAUDE_SKILL_DIR}/scripts/audit-suppressions.sh:*)", "Bash(python3 ${CLAUDE_SKILL_DIR}/scripts/suppression-scan.py:*)", "Bash(git branch --show-current:*)"]
shell: bash
metadata:
  workflow-stage: anytime
  summary: Suppressions with their rule ids and reasons, no verdict
---

## Pre-computed context

Current branch: !`git branch --show-current 2>/dev/null || echo "unknown"`

## Purpose

A suppression turns a linter or type checker off for one line, one block or one file. Each one is
a decision someone made once; this skill lists them so a reader can see how many there are, which
explain themselves, and which switch off a rule the team counts as correctness rather than style.
It reports and stops: no pass or fail, and the report carries no severity (a `--findings` file
carries the tier its rule's row sets, below). Whether a suppression should go is the reader's call.

A suppression is **justified** when its line carries a reason and, for a tool whose syntax can name
a rule, at least one rule id. TypeScript's `@ts-ignore`, `@ts-expect-error` and `@ts-nocheck`
cannot name an error, so a reason alone justifies them. Where a tool has a reason slot of its own,
the text there is the reason (ESLint and RuboCop after `--`, a `Justification` argument in C# and
PowerShell); otherwise a further comment on the same line is (a TypeScript directive's trailing
text, a second `<!-- -->` after a markdownlint directive, a `//` comment after `@SuppressWarnings`,
a second `#` comment after a Python or shell pragma).

Only real comments, pragmas and attributes count. A marker inside a string literal, a Markdown code
span or a fenced code block in a Markdown file is not a suppression.

## Run it

```bash
"${CLAUDE_SKILL_DIR}/scripts/audit-suppressions.sh"                    # lines the commits since the merge-base add
"${CLAUDE_SKILL_DIR}/scripts/audit-suppressions.sh" --base release/2.0  # the merge-base with another branch
"${CLAUDE_SKILL_DIR}/scripts/audit-suppressions.sh" --all              # every suppression in the tree
"${CLAUDE_SKILL_DIR}/scripts/audit-suppressions.sh" src/ tools/build.sh # explicit paths, whole files
"${CLAUDE_SKILL_DIR}/scripts/audit-suppressions.sh" --json --all        # the document instead of markdown
"${CLAUDE_SKILL_DIR}/scripts/audit-suppressions.sh" --findings          # the report plus a findings file for /review:fanout fix
```

The change scope reads committed lines only: a suppression in an uncommitted edit is not in it until
it is committed, so name the file or use `--all` to see the working tree. `scope.exclude` and lane
opt-outs apply as in the other audits.

Present the markdown report as printed: the scope, the counts, the correctness list with the layer
that set it, then one row per suppression (correctness rules first, then lines without a reason),
capped at 200 rows with the kept document named for the rest. The `--json` document
(`code-metrics/suppressions/v1`) carries `scope`, `counts` (`suppressions`, `unjustified`,
`correctness`), `correctness_rules` (`rules`, `layer`) and `suppressions`, one object per row with
`file`, `line`, `tool`, `rules`, `justified`, `reason` and `correctness`.

## Findings for the review relay (`--findings`)

`--findings` runs the same scan in the same scope, prints the same report, then writes one findings
file in the shape `/review:fanout fix` reads and prints its path. It asks nothing, so a pipeline or
another skill can run it. Bare invocation and `--json` write no findings file.

- **Where it goes.** `<memory root>/reviews/<branch-slug>/<UTC stamp>-suppressions.md`, the
  directory `/review:fanout` "Shared inputs" names. The memory root is `.work` under the repository
  root; when the project's instructions name another memory root, pass it with `--memory-dir`. A
  memory root with no `.gitignore` gets one holding `*`, and the run says so. An existing file is
  never overwritten: a second run in the same second takes a `-2` suffix.
- **No branch, no file.** On a detached HEAD or outside a git repository the run stops with exit 2
  before scanning and says no findings file was written: the relay reads only a file whose
  `branch:` matches the current branch.
- **What becomes a row.** A justified suppression is no finding. An unjustified one is a row under
  one of two rules: `code-metrics/audit-suppressions/rule-no-reason` when the line carries no
  reason, and `code-metrics/audit-suppressions/rule-no-rule-id` when it carries a reason but no rule
  id and the tool can name one. Each `Finding` cell leads with the rule id and what fired (the tool,
  its rule ids, and the missing part); `Location` is the repo-relative `file:line`. `Tier`
  (`IMPORTANT`), `Confidence` (`high`) and the fact that neither rule is auto-applicable come from
  the two rules' rows in the detector-findings convention
  (<https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/conventions/detector-findings/README.md>,
  "The severity crosswalk"), never from the finding. The `Action` names where this tool keeps its
  reason, and asks for a rule id only where the tool can name one and the line names none.
- **Coverage.** `## Surfaces` names the scope and how many suppressions were examined, and counts
  each rule's declined candidates by the evidence that declined them: a reason on the line, a rule
  id on the line, or a TypeScript directive, which cannot name an error. A run whose scope holds no
  file writes no findings file.

Whether a suppression goes or gets its reason is a human's call, so no row is auto-applicable: the
fix pass surfaces the rows rather than applying them.

## Correctness rules

`suppressions.correctness_rules` lists the rule ids whose suppression the team wants to see first,
such as `no-floating-promises`, `SC2086` or `CA2000`. The plugin ships the list empty, because which
rules guard correctness is the repository's call. Set it in `docs/conventions/code-metrics.yaml`
(keys in `${CLAUDE_PLUGIN_ROOT}/reference/config.md`):

```yaml
suppressions:
  correctness_rules: [no-floating-promises, SC2086, CA2000]
```

A row is marked when one of its rule ids is listed, compared case-insensitively. A suppression that
names no rule is not matched; for a tool that can name one, it is already unjustified. An invalid
value (a scalar, a number in the list) is named with its file and key, and the key falls back to a
valid higher layer or the empty default; the run continues.

## Freezing the count

The scanner behind this skill, `scripts/suppression-scan.py`, prints the count on its own:

```bash
python3 "${CLAUDE_SKILL_DIR}/scripts/suppression-scan.py" --count
# suppressions=<n>
# unjustified=<n>
```

When `/review:ratchet` is among the available skills, it can hold that count as a CI ceiling: it
vendors a copy of the scanner into the repository and ratchets the `suppressions` or `unjustified`
field. Without it, keep the `--json` document and compare counts by hand.

## Upstream syntax

The marker catalog follows each tool's own directive syntax, read from these pages:

- **Pointer:** [ESLint, disabling rules](https://eslint.org/docs/latest/use/configure/rules#disabling-rules);
  [TypeScript 3.9, `@ts-expect-error`](https://www.typescriptlang.org/docs/handbook/release-notes/typescript-3-9.html);
  [flake8, in-line ignoring](https://flake8.pycqa.org/en/latest/user/violations.html);
  [Ruff, error suppression](https://docs.astral.sh/ruff/linter/#error-suppression);
  [mypy, silencing the checker](https://mypy.readthedocs.io/en/stable/common_issues.html);
  [pylint, message control](https://pylint.readthedocs.io/en/stable/user_guide/messages/message_control.html);
  [Pyright, comments](https://microsoft.github.io/pyright/#/comments);
  [ShellCheck, directives](https://www.shellcheck.net/wiki/Directive);
  [C# `#pragma warning`](https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/preprocessor-directives);
  [.NET, suppressing code analysis warnings](https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/suppress-warnings);
  [golangci-lint, false positives](https://golangci-lint.run/docs/linters/false-positives/);
  [PSScriptAnalyzer, suppressing rules](https://learn.microsoft.com/en-us/powershell/utility-modules/psscriptanalyzer/using-scriptanalyzer);
  [markdownlint, configuration](https://github.com/DavidAnson/markdownlint#configuration);
  [RuboCop, source code directives](https://docs.rubocop.org/rubocop/latest/usage/source_code_directives.html);
  [Java `SuppressWarnings`](https://docs.oracle.com/en/java/javase/21/docs/api/java.base/java/lang/SuppressWarnings.html).
- **As of:** 2026-10-04.
- **Recheck trigger:** a tool on the list adds a suppression form, a reason syntax, or a way to name
  a rule; or a team reports a real suppression the report missed.

## What this skill does not do

- It does not remove, rewrite or approve a suppression, and it runs no linter.
- It is not the finding-suppression record in `docs/conventions/finding-suppression/`, which holds
  review findings a team chose to dismiss; this skill reads source comments and attributes.
- It does not judge: no count here is a bar. `/code-metrics:principles` explains what each number
  in this plugin can and cannot tell you.

## Next

- Hold the count in CI so it only falls: /review:ratchet.
- Work through the rows a `--findings` run wrote: /review:fanout fix.
- A count needs reading before anyone acts on it: /code-metrics:principles.

## Gotchas

- The change scope needs a merge-base with the default branch; outside a git repository, or with no
  default-branch ancestor, pass paths or `--all` (the usage error says which).
- A multi-line C#, PowerShell or Java attribute is read up to ten lines past its opening line; a
  longer one is reported with the rule ids and reason it showed in that span.
- A tool not on the list (Stylelint, Clippy, SwiftLint) is not reported; nothing in the report says
  a file had none of its markers.
- The scanner needs Python 3.11 or later, above the plugin's 3.9 floor; below it the scanner
  exits 2 with a one-line message.
- File type comes from the extension, or the shebang for a file without one; a shell script named
  `*.txt` is not read as shell.
