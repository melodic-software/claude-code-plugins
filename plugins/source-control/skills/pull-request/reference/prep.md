# Phase 1: Prep (review + verify + simplify)

Pre-PR quality phase: review, verify, and simplify changes before creating the PR.

## 1.1 Detect changed files

```bash
git diff --cached --name-only && git diff --name-only && git ls-files --others --exclude-standard
```

Classify files: **code** (source files — `.cs`, `.py`, `.ts`, `.js`, `.sh`, `.ps1`, project files), **tests** (paths containing `/tests/`, `*Tests.*`, `*.test.*`), **config/doc** (`.md`, `.json`, `.yml`).

**Zero code files?** Skip review/simplify (1.2–1.4); the verify gate (1.5) reduces to lint. Proceed to PR creation. If the consuming project layers extra prep-evidence requirements on PR creation (hooks, gates), satisfy those per its own docs.

## 1.2 Review the changes

Run the strongest review capability your environment provides, scoped to the branch diff:

- A PR-review skill or plugin (e.g. a `review-pr` command), or review agents (code-reviewer, security-reviewer, architecture-reviewer) when installed
- Otherwise: review the diff inline — correctness, error handling, security-sensitive surfaces, test coverage for new logic, convention adherence against the project's own rules

Auto-scale aspects to the diff: always check code errors; add test-focused review when test files changed; add type-design review for new type-heavy files. Collect findings.

## 1.3 Verify EVERY finding (CRITICAL)

For each finding:

1. Extract the specific claim (API, pattern, behavior assertion)
2. Verify against official docs and actual source for the exact versions in use (dispatch parallel verification agents when your environment supports them — up to 3 at a time)
3. Cross-reference against the project's own conventions/rules
4. Classify: **VERIFIED** (evidence confirms), **INCORRECT** (evidence contradicts), **UNCERTAIN** (cannot confirm)

**Drop INCORRECT findings entirely.** Flag UNCERTAIN with a note.

Present verified findings in a structured table. Pause for user review and fixes.

## 1.4 Simplify, review, and verify

Unless `quick` or `review-only` scope:

1. Run your environment's simplify/refine capability over the branch diff when one exists (a `/simplify`-style skill); otherwise do a manual pass for dead code, needless indirection, and duplication introduced by the branch
2. **Show the simplify diff** — run `git diff` and present what changed. Automated simplification fixes are NOT research-verified; treat them like any code-review finding: inspect each change, approve or revert
3. **Pause for user review** — let the user approve/reject simplify changes before proceeding
4. Re-run tests on approved changes
5. Run the verify gate (1.5)

## 1.5 Verify gate (HARD — blocks PR creation)

Run the project's full build + test + lint surface — via its verify skill when one exists (e.g. a `/verification:confirm` or `/toolchain:build` command), otherwise the ecosystem-native commands (`dotnet build && dotnet test`, `npm test`, `pytest`, shellcheck, markdownlint, …) for every ecosystem the branch touches. **All results must be clean before proceeding to PR creation.**

**Run the full cross-cutting surface, not just the "obvious" ecosystem.** A branch that "looks dotnet-only" can still break CI through a touched README, an unmarked `.sh` script, or a modified workflow file. Mirror locally whatever CI will run — the project's CI workflows are the canonical list of what must pass.

**Decision rule:**

- Any FAIL → STOP. Address each before reattempting. Do not proceed to PR creation
- Any skip due to "tool missing" → install the tool OR document why the skip is acceptable in this PR (rare — almost always faster to install)
- All clean (or only non-applicable skips like "no `.md` changes") → proceed to PR creation

**Why this gate is hard:** cost asymmetry. Each mechanical issue caught locally costs seconds; the same issue in CI burns a full multi-minute round trip plus rebase/repush overhead. A single sloppy PR can waste half a dozen CI cycles on issues that were all catchable locally.

## 1.6 Report

Report: findings verified/dropped, simplify ran/skipped, verify gate pass/fail per ecosystem. Proceed to PR creation.
