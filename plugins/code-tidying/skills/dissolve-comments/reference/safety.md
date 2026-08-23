# Safety model — modes, gates, exclusions, staging

The risk being managed: class-B treatments are code changes, and a behavior-preserving refactor is
only verified behavior-preserving by tests. The layers below keep the default mode fully capable
for codebases with guardrails while giving an explicit reduced-blast-radius mode for the rest.

## Mode ladder

| Mode | Class A | Class B | Class C |
|---|---|---|---|
| **Default** | Applied | Applied behind the test gate below; otherwise proposed | Earn-its-keep triage; narrative staging |
| **`safe`** | Applied | Always proposed — no code-structure change is applied | Same triage; deletions of pure narrative still apply, with staging |

In **no mode** does the skill: apply a class-B refactor without a passing discovered test run,
touch an exempt surface or excluded path, or delete text without a landing place (staging rule
below).

## The class-B test gate

1. **Discover** a runnable test command for the touched code: the repo's declared conventions
   (`CLAUDE.md`, rules, a `test` script in the package manifest, `Makefile`/`justfile` targets,
   the ecosystem default — `dotnet test`, `npm test`, `pytest`, `go test ./...`, `bats`).
2. **Scope-check**: the discovered suite must plausibly exercise the touched code (same package/
   project/module). A repo-wide suite that cannot reach the touched file is not a net for it.
3. **Run before and after** the move. Red before the move → stop, report (the skill never fixes
   tests). Red after the move → revert the move, demote the item to a proposal.
4. **No discoverable command, or the run cannot execute** → class B is proposed, never applied.

Lint and formatters are supplementary hygiene (run them if the repo has them wired) — they never
open the apply path, because they cannot attest behavior preservation.

## Exempt surfaces (never touched, any mode)

- Public-API doc comments: docstrings, C# XML docs, JSDoc/TSDoc on exported/public surfaces
- Legal and license headers
- Machine-read directives: shebangs, lint pragmas (`# noqa`, `// eslint-disable`,
  `#pragma warning`), region markers, editor folds, encoding cookies
- `TODO(#issue)` / `FIXME(#issue)` markers tracking real work
- Lines carrying `dissolve-comments-ignore` (on the line or the line immediately before)

## Path exclusions

The canonical baseline is the plugin's standard tier — tidy's
[exclusions reference](${CLAUDE_PLUGIN_ROOT}/skills/tidy/reference/exclusions.md), GLOBAL HARD
list: the whole `.claude/**` tree plus any script wired as a hook command in
`.claude/settings.json` (wherever it lives), other agents' config bundles, `.github/workflows/**`
and CI surface, git-hook manager config, cross-ecosystem lint/style config. Consumer-declared
protections in the target repo's `CLAUDE.md`/rules extend the list. Excluded paths are dropped at
scoping time; they never reach triage.

## Narrative staging — text is never silently destroyed

When a removal takes real prose with it (a justification narrative, a why that routes to version
control), the run's report stages that text **before the deletion is final**:

```text
Proposed commit-message body (staged from removed comments):

  <file>:<line> — <the narrative, condensed but information-complete>
```

Hand the block to `/source-control:commit`, invoked via the Skill tool, when committing the tidied
diff, or fold it into the
PR description or an ADR when the repo keeps them. For explicit-target runs on already-committed
code, note in the report that the narrative belongs with the *next* commit touching that code —
or keep the comment if no vehicle exists (staging with no landing place is not a deletion
licence).
