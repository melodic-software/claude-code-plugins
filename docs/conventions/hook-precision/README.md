# Hook precision: false-positive discipline for plugin hooks

Owner doc for the precision discipline every plugin hook follows so it fires on what it targets and stays
quiet on everything else. The [plugin philosophy](../../plugin-philosophy.md) owns the posture rule: an
advisory hook is a nudge, a guard must not block legitimate work. This doc owns the *precision shape* that
keeps both true: the recurring ways a hook over-fires, and the discipline that turns each production false
positive into a regression test instead of a re-filed issue.

Guardrails hooks repeatedly shipped false-positive over-fires, each found by a babysit worker on a real
pass, hand-filed and fixed in isolation. The classes below are those over-fires
generalized; the discipline after them is what stops the pipeline from paying for the next one at production
time.

## The rules

Six rules for what a hook matches, how it reads its input, and which paths it acts on. The discipline after
them turns every next over-fire into a committed regression test. A hook is precise when it matches the
*structure* it targets, reads its input safely, and scopes its check to what actually changed.

1. **Diff-scope `PostToolUse:Edit` checks to the changed hunk.** An Edit hook that scans the whole file
   warns on pre-existing lines the edit never touched. Check only the edited region (the tool payload's new
   content); scan the whole file only for a new-file Write, where every line is genuinely new.
2. **Match structural producers, not token co-occurrence, and ignore tokens inside quoted arguments.** A
   guard that greps for `echo` and `>` anywhere in a command string fires on any command whose quoted
   arguments merely mention them. Parse the command's structure and treat quoted spans as inert data, not
   executable tokens.
3. **Bound every stdin read; never parse the inherited fd0 directly.** A hook that runs `jq` against fd0
   unbounded stalls when a Win32 pipe delivers EOF late, hanging the tool call along with it. Buffer stdin
   once through the bounded reader, then parse every field from the buffer.
4. **Prefer either/or marker logic where "already-canonical → stay quiet" is the intent.** When any one
   marker proves the input is already canonical, requiring a *conjunction* of markers makes the hook fire on
   canonical input that happens to omit an optional second marker. Gate on the single marker that proves
   canonicality, and prefer the one that survives literal-stripping.
5. **Gate path detection on the discovered checkout, not the raw project dir.** A repo-path branch that
   matches the project dir as a literal substring flags every absolute path under it when the project dir is
   (or is under) the user's home. Resolve the enclosing git toplevel and compare *that* against home;
   suppress the branch when the checkout root is home or an ancestor of it.
6. **Leave a gitignored path alone.** A format or lint hook neither rewrites nor reports on a file the
   repository gitignores, unless the plugin's `<plugin>_lint_gitignored` option is `true` (the spelling
   `markdown_format_lint_gitignored` set). A rewrite of an ignored file has no `git checkout` to undo it,
   and findings on a scratch tier the repository excluded are noise. Decide with `git check-ignore` from
   the file's own directory, so every `.gitignore`, `.git/info/exclude`, and the global excludes file
   apply. Let the index answer, so a tracked file matching an ignore pattern stays in scope. Clear an
   inherited `GIT_DIR`/`GIT_WORK_TREE` first, so a wrapper's repository cannot answer for the file's own.
   Fail toward acting: git absent, no repository, or a `check-ignore` error runs the hook as before,
   because a skip that fired on an error would disable the hook invisibly. The counter-case, a developer
   who wants an ignored local script formatted, is what the opt-in is for. The shared implementation for
   rewriting hooks is `hook::gitignored_out_of_scope` in `lib/hook-utils.sh`. The nine hooks skip a
   gitignored file by default and run on it only with the `<plugin>_lint_gitignored` opt-in; that is the
   maintainer's decision on #4671.

   This matches the tools' own defaults when they walk a tree. It does not match what they do for a path
   the hook names on the command line, which is how every one of these hooks invokes them: Ruff's
   `respect-gitignore` (default `true`) does not reach an explicitly passed path even under
   `--force-exclude`, and Biome honors an ignored explicit path only when the consumer enables
   `vcs.useIgnoreFile` (default off), so the hook has to decide. Verification record. Claim: as stated.
   Basis: <https://docs.astral.sh/ruff/settings/> (`respect-gitignore`, `force-exclude`),
   <https://biomejs.dev/reference/configuration/> (`vcs.useIgnoreFile`),
   <https://prettier.io/docs/ignore> (follows `.gitignore`), and runs of Ruff 0.16.7 and Biome 2.5.14 on
   an ignored `.work/` file passed explicitly. As of: 2026-09-28. Recheck: a formatter release that
   changes how an explicit path meets its ignore settings, or a hook that stops passing the path
   explicitly.

## The discipline

The rules prevent the classes already seen; the discipline prevents the next one. It has two halves, and
both are non-negotiable:

- **Every filed production false positive becomes a MUST-stay-quiet case in that hook's existing
  `*.test.sh`.** The co-located contract test *is* the fixture corpus. True-positive MUST-fire cases and
  false-positive MUST-stay-quiet cases live side by side and run in CI on any `plugins/guardrails/hooks/**`
  change. An over-fire that is fixed but not pinned by a committed stay-quiet case is left half-fixed: the
  next author can reopen it and nothing catches them.
- **Every fix lands repro-first.** The new stay-quiet case must *fail* against the unmodified hook
  (reproducing the over-fire) and pass after the fix. A stay-quiet assertion that is already green before the
  fix guards nothing. It only looks tested.

## Platform gap: `if` file rules on Windows

Hook `if` file rules do not match an absolute path outside the working directory on Windows
(Claude Code 2.1.258, Git Bash). That is an upstream matching bug, not a marketplace defect, and
it is not fixed here (#3680).

Any hook that must see a user-global or managed file (the context-budget settings checkpoint is
the in-repo case) stays unconditioned until upstream matching reaches those paths. Putting an
`if` gate on that row would drop the checks silently.

- **Claim:** this is an upstream candidate; this marketplace does not patch Claude Code's `if`
  matcher. Guard rows that target paths outside cwd stay unconditioned.
- **Basis:** the dated probe in `plugins/context-budget/README.md` (the paragraph starting "The
  registration carries no `if` filter") and #3680.
- **As of:** 2026-09-29.
- **Recheck:** a Claude Code release note saying hook `if` file rules match absolute paths outside
  cwd on Windows. Re-probe before adding an `if` gate to the context-budget row.

## What this convention is not

- **Not a new harness.** There is no separate golden-fixture system to build or wire. The existing per-hook
  `*.test.sh` beside each hook is the corpus, and `guardrails-test-helpers.sh` is its shared assertion
  library. A standalone fixture harness was considered and rejected. It would duplicate the harness that
  already ships next to every hook.
- **Not true-positive tuning.** These rules narrow *false* positives without weakening detection; a change
  that also drops real catches is out of scope and must keep its MUST-fire cases green.
- **Not a substitute for the philosophy's hook posture.** Advisory-versus-blocking, fail-open-versus-closed,
  and prerequisite visibility are owned upstream in the plugin philosophy; this doc assumes them.

## Conformance

Fleet audits check that each `plugins/guardrails/hooks/**` change carries the discipline: a fix pins the
over-fire it closes as a repro-first stay-quiet case in the co-located test, and no rule above regresses. CI
runs every `*.test.sh` on any hooks change.

Existing adopters conform by carrying the rule their over-fire needed:

- `block-hook-bypass` strips quoted literal spans before its executable-token scan, so a command that only
  *mentions* `echo` / `>` inside an argument stays quiet (rule 2).
- `cli-flag-verify` buffers stdin through `hook::buffer_stdin` instead of reading `fd0` directly (rule 3).
- `block-noncanonical-commit` gates on the canonical `-F -` marker alone, dropping the `--trailer`
  conjunct its advisory predecessor required (rule 4).

### Rule 6 conformance: the nine format and lint hooks

The harness `if` filter cannot express "gitignored", so it narrows spawn cost only and
never stands in for the gate.

| Hook | Acts on the file by | Gate | Verdict |
|---|---|---|---|
| `markdown-format` | rewriting (`markdownlint-cli2 --fix`) and reporting | shared, `markdown_format_lint_gitignored` | conforms (#4671); local `file_is_gitignored` removed |
| `bash-format` | rewriting (shfmt) and reporting (ShellCheck) | shared, `bash_format_lint_gitignored` | conforms (#4671) |
| `biome-format` | rewriting and reporting (Biome) | shared, `biome_format_lint_gitignored` | conforms (#4671) |
| `eol-normalizer` | rewriting line endings | shared, `eol_normalizer_lint_gitignored`, checked only when a rewrite is planned | conforms (#4671); registers with no `if` filter because its matcher is every write |
| `go-format` | rewriting (goimports) | shared, `go_format_lint_gitignored` | conforms (#4671) |
| `powershell-format` | rewriting (Invoke-Formatter) and reporting (PSScriptAnalyzer) | shared, `powershell_format_lint_gitignored` | conforms (#4671) |
| `ruff-format` | rewriting and reporting (Ruff) | shared, `ruff_format_lint_gitignored` | conforms (#4671) |
| `typos-format` | reporting, and rewriting when write mode is on | shared, `typos_format_lint_gitignored` | conforms (#4671); registers with no `if` filter because typos is language-agnostic |
| `actionlint` (`actionlint-check`) | reporting only | shared, `actionlint_lint_gitignored`; `hook::begin --no-membership`, `if`-bounded to `**/.github/workflows/*.y*ml` | conforms (#4671); lowest exposure, since it never rewrites and an ignored workflow file is rare |

The helpers live in `lib/hook-utils.sh`. The six rewriting hooks also carry `rewrite-guard.sh`, for the
snapshot and disclosure guard only; the three non-rewriting hooks do not.

The gitignore signal is kept separate from the two disposable-root lists the fleet already has:
guardrails' `block_hook_bypass_scratch_roots` and hook-utils' temp-root helpers. They answer different
questions. The first is an operator allowlist on a security guard, empty by default. The second marks
the host temp tree for project membership. `.gitignore` is the repository's own statement of what is out
of scope. Merging any two would let a formatter-scope setting widen a security exemption, so each stays
its own list.

The shared harness and a worked exemplar that co-locates both MUST-fire and MUST-stay-quiet cases:

- Assertion library: [`guardrails-test-helpers.sh`](../../../plugins/guardrails/hooks/guardrails-test-helpers.sh)
- Exemplar test: [`hardcoded-path-check.test.sh`](../../../plugins/guardrails/hooks/hardcoded-path-check.test.sh)
