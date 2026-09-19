# Phase 1: Prep (review + verify + simplify)

Pre-PR quality phase: review, verify, and simplify changes before creating the PR.

## 1.1 Detect changed files and classify them

```bash
git diff --cached --name-only && git diff --name-only && git ls-files --others --exclude-standard
bash "${CLAUDE_PLUGIN_ROOT}/scripts/skill-evidence.sh" classes --base "<remote>/<default-branch>"
```

Each `class=<name>` line names a class of the repository's `pr_skill_evidence` map, and the map is what decides which skills this branch owes. That output is authoritative. The table below is what a map following the pre-PR order looks like; a repository's own map names its own classes and its own skills. No output at all means the map is absent or `none`, so classify by hand instead, **code** (source files: `.cs`, `.py`, `.ts`, `.js`, `.sh`, `.ps1`, project files), **tests** (paths containing `/tests/`, `*Tests.*`, `*.test.*`), **config/doc** (`.md`, `.json`, `.yml`), and run the steps that apply.

| Class | What it owes | Where it runs |
|---|---|---|
| `code` | one fresh-context review (`review:quality-gate` under 50 changed lines, `review:fanout` above), then `simplify`, then `verification:confirm` | §1.2 to §1.5 |
| `markdown` | `ai-slop:audit` and `docs-hygiene:audit-noise` over the changed `.md` files | §1.2.1 |
| `renames` | a `docs-hygiene:rename-references` audit | §1.2.1 |
| `skills` | `skill-quality:check` over each changed skill | §1.2.1 |
| `rules` | `instruction-placement:check` | §1.2.1 |
| `security` | `review:security-review` over the pull request's diff | [ready-for-review.md](ready-for-review.md) §2.5.4 |

**The order of the steps is not this file's to set.** It is the fleet's pre-PR order, owned by [`docs/conventions/pre-pr-ordering/README.md`](https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/conventions/pre-pr-ordering/README.md). Read the order there; this file cites it rather than restating it.

Every skill named below is invoked through the Skill tool when its plugin is installed, and replaced by the inline fallback stated beside it when it is not. A fallback does not write a ledger row, so it leaves that skill out of the evidence block a pull request carries; report the gap and what covered it instead of claiming the row.

**No `code` class?** Skip 1.2 to 1.4; the verify gate (1.5) reduces to lint. The other classes still owe their audits, so a docs-only branch is not exempt: it owes the prose audits in 1.2.1. If the consuming project layers extra prep-evidence requirements on PR creation (hooks, gates), satisfy those per its own docs.

## 1.2 Review the changes (the `code` class)

Run **one** fresh-context review over the branch diff: `/review:quality-gate` under 50 changed lines, `/review:fanout` above it, when the `review` plugin is installed. Either satisfies an any-of (`a,b`) token in the map, which is why only one of them runs.

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

Present verified findings in a structured table. Pause for user review and fixes.

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

**This is the map's terminal skill**, the one a `pr_skill_evidence` map marks with a trailing `!`. It runs last and its evidence row is checked at the head exactly, so nothing that edits the tree may run after it.

**Why this gate is hard:** cost asymmetry. Each mechanical issue caught locally costs seconds; the same issue in CI burns a full multi-minute round trip plus rebase/repush overhead. A single sloppy PR can waste half a dozen CI cycles on issues that were all catchable locally.

## 1.6 Report

Report: findings verified/dropped, simplify ran/skipped, verify gate pass/fail per ecosystem, and which classes 1.1 detected. Proceed to PR creation.

**Prep before create is the developer loop, not the evidence-bearing run.** Each skill run here leaves a ledger row stamped with whatever HEAD was at the moment it was invoked. The rebase in [create.md](create.md) §2.2 rewrites those SHAs, so any of those rows may be invalid by the time the PR exists. Nothing is lost by that: no pull request exists yet, so no evidence is owed yet. The run that owes it is [ready-for-review.md](ready-for-review.md), on a committed head with the base already merged in.
