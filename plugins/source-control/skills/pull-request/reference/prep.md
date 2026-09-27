# Phase 1: Prep (review + verify + simplify)

Pre-PR quality phase: review, verify, and simplify changes before creating the PR.

## 1.1 Detect changed files and classify them

```bash
git diff --cached --name-only && git diff --name-only && git ls-files --others --exclude-standard
git diff --name-status "<remote>/<default-branch>"...HEAD
```

Classify the branch's changed files by the table below and run the steps each class owes.

| Class | Which files | What it owes | Where it runs |
|---|---|---|---|
| `code` | source files (`.sh`, `.bash`, `.py`, `.mjs`, `.js`, `.cjs`, `.ts`, `.ps1`, `.cs`, project files) | one fresh-context review (`review:quality-gate` under 50 changed lines, `review:fanout` above), then `simplify`, then `verification:confirm` | §1.2 to §1.5 |
| `markdown` | `.md` files | `ai-slop:audit` and `docs-hygiene:audit-noise` over the changed `.md` files | §1.2.1 |
| `renames` | any `R` line in the name-status output | a `docs-hygiene:rename-references` audit | §1.2.1 |
| `skills` | `plugins/*/skills/**`, `plugins/*/agents/**` | `skill-quality:check` over each changed skill | §1.2.1 |
| `rules` | `.claude/rules/**` | `instruction-placement:check` | §1.2.1 |
| `security` | any diff that is not docs-only | `review:security-review` over the pull request's diff | [ready-for-review.md](ready-for-review.md) §2.5.3 |

**The order of the steps is not this file's to set.** It is the fleet's pre-PR order, owned by [`docs/conventions/pre-pr-ordering/README.md`](https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/conventions/pre-pr-ordering/README.md). Read the order there; this file cites it rather than restating it.

Every skill named below is invoked through the Skill tool when its plugin is installed, and replaced by the inline fallback stated beside it when it is not. Report each fallback and what it covered.

**No `code` class?** Skip 1.2 to 1.4; the verify gate (1.5) reduces to lint. The other classes still owe their audits, so a docs-only branch is not exempt: it owes the prose audits in 1.2.1. If the consuming project layers extra prep requirements on PR creation (hooks, gates), satisfy those per its own docs.

## 1.2 Review the changes (the `code` class)

Run **one** fresh-context review over the branch diff: `/review:quality-gate` under 50 changed lines, `/review:fanout` above it, when the `review` plugin is installed.

- Without that plugin: review the diff inline for correctness, error handling, security-sensitive surfaces, test coverage for new logic, and convention adherence against the project's own rules. Review agents (code-reviewer, security-reviewer, architecture-reviewer) serve the same purpose when your environment ships them
- Auto-scale aspects to the diff: always check code errors; add test-focused review when test files changed; add type-design review for new type-heavy files. Collect findings

## 1.2.1 The other classes' audits

Run the audit each detected class owes, over the changed files of that class only:

- **`markdown`**: `/ai-slop:audit` when the `ai-slop` plugin is installed, otherwise read the changed markdown against the project's own prose rules; and `/docs-hygiene:audit-noise` when the `docs-hygiene` plugin is installed, otherwise read it for stale citations, dead references, and conversational residue
- **`renames`**: `/docs-hygiene:rename-references audit` when `docs-hygiene` is installed, otherwise grep the old path and the old name for every surviving reference. The class fires only when the diff reports a rename
- **`skills`**: `/skill-quality:check` when the `skill-quality` plugin is installed, otherwise run the project's own skill lint, or read each changed skill's frontmatter against the contract the project documents
- **`rules`**: `/instruction-placement:check` when the `instruction-placement` plugin is installed, otherwise confirm each changed rule's `paths:` glob still matches a tracked file
- **`security`**: not here. It reviews the pull request's own diff, so it runs in the ready step

Audits that persist findings hand them to one `/review:fanout fix` pass when the `review` plugin is installed, and are applied by hand otherwise. Either way each finding goes through 1.3 first.

## 1.3 Verify every finding

For each finding:

1. Extract the specific claim (API, pattern, behavior assertion)
2. Verify against official docs and actual source for the exact versions in use (dispatch parallel verification agents when your environment supports them, up to 3 at a time)
3. Cross-reference against the project's own conventions/rules
4. Classify: **VERIFIED** (evidence confirms), **INCORRECT** (evidence contradicts), **UNCERTAIN** (cannot confirm)

**Drop INCORRECT findings entirely.** Flag UNCERTAIN with a note.

Present the findings in a structured table, leading with the verified findings you would block the merge for, each with file:line, why it is wrong, and how to show it fails (a failing test, command, or input). The remaining verified and UNCERTAIN findings follow. Pause for user review and fixes.

## 1.4 Simplify, review, and verify

Unless `quick` or `review-only` scope:

1. Run `/simplify` over the branch diff when that capability resolves in your session; otherwise do a manual pass for dead code, needless indirection, and duplication introduced by the branch
2. **Show the simplify diff**: run `git diff` and present what changed. Automated simplification fixes are NOT research-verified; treat them like any code-review finding: inspect each change, approve or revert
3. **Pause for user review**: let the user approve/reject simplify changes before proceeding
4. Re-run tests on approved changes
5. Run the verify gate (1.5)

## 1.5 Verify gate (HARD: blocks PR creation)

Run the project's full build + test + lint surface, via `/verification:confirm` when the `verification` plugin is installed (or `/toolchain:check` for the mechanical half alone) and otherwise the ecosystem-native commands (`dotnet build && dotnet test`, `npm test`, `pytest`, shellcheck, markdownlint, …) for every ecosystem the branch touches. **All results must be clean before proceeding to PR creation.**

**Run the full cross-cutting surface, not just the "obvious" ecosystem.** A branch that "looks dotnet-only" can still break CI through a touched README, an unmarked `.sh` script, or a modified workflow file. Mirror locally whatever CI will run. The project's CI workflows are the canonical list of what must pass.

**Decision rule:**

- Any FAIL → STOP. Address each before reattempting. Do not proceed to PR creation
- Any skip due to "tool missing" → install the tool OR document why the skip is acceptable in this PR (rare, since it is almost always faster to install)
- All clean (or only non-applicable skips like "no `.md` changes") → proceed to PR creation

**This gate runs last**, so nothing that edits the tree may run after it.

**Why this gate is hard:** cost asymmetry. Each mechanical issue caught locally costs seconds; the same issue in CI burns a full multi-minute round trip plus rebase/repush overhead. A single sloppy PR can waste half a dozen CI cycles on issues that were all catchable locally.

## 1.6 Report

Report: findings verified/dropped, simplify ran/skipped, verify gate pass/fail per ecosystem, and which classes 1.1 detected. Proceed to PR creation.

**Prep before create is the developer loop.** The rebase in [create.md](create.md) §2.2 and the base merge in [ready-for-review.md](ready-for-review.md) §2.5.2 both move HEAD after prep, which is why the ready step re-runs the verify gate on the head it flips.
