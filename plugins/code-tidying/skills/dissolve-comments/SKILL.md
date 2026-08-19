---
description: "Enforce self-describing, expressive code over changed files: a three-way comment triage that deletes zero-information comments, dissolves code-expressible comments into names and structure via behavior-preserving refactoring and then deletes them, and keeps only terse, load-bearing comments code cannot express (why, constraints, contracts). Applies edits: deletions are near-mechanical; refactors apply only behind a discovered test net, else they are proposed; 'safe' mode restricts applied edits to removals. Use when: 'dissolve comments', 'remove comments', 'strip agent comments', 'too many comments', 'make it self-documenting', 'make the code expressive', 'comments must earn their keep', after an agent wrote over-commented code. Skip when: read-only residue classification (audit-comment-residue), lane-hunting structural tidyings (tidy), windowed or repo-wide batch sweeps (batch-simplify), markdown noise (docs-hygiene audit-noise), adding missing why-comments (tidy #14). Never touches public-API doc comments, license headers, or machine-read directives."
argument-hint: "[safe] [target]"
disable-model-invocation: false
user-invocable: true
shell: bash
metadata:
  workflow-stage: review
  summary: Dissolve comments into expressive code via triage — delete, refactor-then-delete, or keep
---

## Pre-computed context

Current branch: !`git branch --show-current 2>/dev/null || echo "unknown"`
Uncommitted code files (preview, first 10): !`git status --porcelain 2>/dev/null | awk '{print $NF}' | grep -Ei '\.(cs|ts|tsx|js|jsx|py|sh|ps1|go|rs|java|rb|lua|sql|c|h|cpp|hpp|yaml|yml|toml)$' | head -10 || echo "none"`

## Variables

Arguments: `$ARGUMENTS`

## Purpose

The enforcement counterpart to `/code-tidying:audit-comment-residue`: where that skill classifies
and reports, this one edits. It makes changed code self-describing and expressive, and it removes
every comment that does not earn its keep — with "earn its keep" defined by the doctrinal floor the
canonical sources jointly sign: *implementation code only needs comments when the code is
nonobvious* (Martin ⇄ Ousterhout debate), restated by Anthropic's own guidance as *"Only add
comments where the logic isn't self-evident."*

The prime driver is agent-written code, which over-narrates by default. This is deliberately a
**tidy-after-generation** pass, not a generation-time comment ban — comments are useful model
context while code is being written; they are dissolved after.

## The three-way triage

Every comment in scope gets exactly one classification. Full doctrine, the earn-its-keep test,
and worked examples: [reference/triage.md](reference/triage.md).

| Class | Test | Treatment |
|---|---|---|
| **A — zero/negative information** | Restates adjacent code, obsolete, commented-out code | Delete outright — deletion is the complete treatment |
| **B — information code could carry** | The comment compensates for a naming/structure deficiency | Refactor until the comment is superfluous, then delete — never delete first |
| **C — information code cannot carry** | Why/rationale, constraint, warning, contract (units, invariants, side effects) | Keep only if load-bearing at the point of reading; terse by default. Improve wording if needed |

Class-B refactoring vocabulary — comment shape → named Fowler-catalog move, with the
over-extraction cautions: [reference/dissolving-moves.md](reference/dissolving-moves.md).

## Action router

| Argument | Action |
|---|---|
| *(empty)* | Triage the uncommitted diff's code files. The pre-computed list is a truncated PREVIEW — re-enumerate the full set at scope time (`git status --porcelain -z` parses safely for any filename, including whitespace). No uncommitted code files → friendly no-op exit. |
| `<path>` | Triage a single file or directory (already-committed code is fine here). |
| `safe [target]` | **Safe mode**: only class-A deletions are applied; every class-B treatment is emitted as a proposal, no code-structure change is applied. For codebases whose guardrails you do not know. |

Default mode applies the full contract: class A applies; class B applies **only behind a
discovered test net**, else it is proposed. The gate, the test-discovery procedure, and the mode
ladder: [reference/safety.md](reference/safety.md).

## Hard rules

- **Never delete information without a landing place.** A class-B comment's information moves into
  code *before* the comment goes. A removed class-C-adjacent narrative (rationale, justification)
  is staged in the output as a proposed commit-message block — hand it to
  `/source-control:commit` — before the deletion is final. Text is never silently destroyed.
- **Tests gate class-B application; lint never does.** A linter cannot attest behavior
  preservation. No discovered runnable test coverage for the touched code → propose, don't apply.
- **Exempt surfaces are invisible to this skill** (full list in
  [reference/safety.md](reference/safety.md)): public-API doc comments (docstrings, C# XML docs,
  JSDoc on exported surfaces); legal/license headers; machine-read directives (lint pragmas,
  region markers, shebangs); `TODO(#issue)` markers tracking real work; lines carrying a
  `dissolve-comments-ignore` marker (on the line or the line before).
- **Path exclusions are the plugin's standard tier.** The canonical baseline is tidy's
  [exclusions reference](${CLAUDE_PLUGIN_ROOT}/skills/tidy/reference/exclusions.md) GLOBAL HARD
  list — agent/enforcement config, CI workflows, hook chains, lint config are never edited.
- **Code files only.** Markdown is `/docs-hygiene:audit-noise` territory; a `.md` target yields no
  findings here.
- **Never add comments, never flag missing ones.** The add-side belongs to `/code-tidying:tidy`
  (#14 Explaining Comments).
- **Structure-only edits.** Class-B moves are behavior-preserving refactorings from the named
  catalog; any candidate edit that would change behavior is out of scope, whatever its comment.

## Workflow

1. **Scope** — resolve targets from the action router, re-enumerating the full file set
   (never the truncated pre-computed preview); drop excluded paths and exempt surfaces.
2. **Triage** — classify every remaining comment A/B/C per [reference/triage.md](reference/triage.md).
3. **Apply** — class A deletions; class B per mode and gate ([reference/safety.md](reference/safety.md)):
   pick the named move, apply it, run the discovered tests, then delete the now-superfluous
   comment. A failing test run reverts the move and demotes the item to a proposal.
4. **Report** — per file: counts per class, applied vs proposed, the staged commit-message block
   for any removed narrative, and the class-C keeps with one-line reasons. The user reviews the
   diff; this skill does not commit.

## What this skill is NOT

- **Not "delete all comments."** Class C survives on the earn-its-keep test; the exempt surfaces
  are never touched at all.
- **Not `/code-tidying:audit-comment-residue`.** That is the read-only classifier for
  out-of-context residue; this applies edits across the full triage. Run the audit when you want
  findings without changes.
- **Not `/code-tidying:tidy` or `/code-tidying:batch-simplify`.** No lane rotation, no scope
  budget, no windowed or repo-wide waves — this is an on-demand enforcement pass over one diff or
  target.
- **Not a bug-hunter or general simplifier.** `/code-review` and `/simplify` own those.

## Gotchas

- A comment that *looks* like restatement can disambiguate genuinely ambiguous code — when the
  code seems to say the same thing but you are not certain, the comment is class B or C, not A.
  Misclassifying B as A is the information-destroying failure; when uncertain, keep or propose.
- Extraction has a cost curve: a name that must grow megasyllabic to stay honest signals the
  information did not fit the name channel — short name + terse comment (or Inline Function)
  beats a dishonest long name. See the cautions in
  [reference/dissolving-moves.md](reference/dissolving-moves.md).
- Introduce Assertion covers only machine-checkable state claims; a comment stating an
  unverifiable assumption about an external system stays a comment (class C).
- During scoping, check file headers for SSOT / do-not-edit declarations: a repo can ship
  materialized copies of one source file (sync scripts, CI drift gates). Triage the source,
  run its declared sync after editing, and never touch a copy — the path-exclusion tier
  alone does not catch this shape.
- A tests/ directory near the target is not a net until it demonstrably covers the touched
  file — import/source it, or exercise it via CLI. This fired on the first file of the
  skill's first live run.

## Sources

- [Fowler — Comments smell, Refactoring 2nd ed. excerpt](https://www.informit.com/articles/article.aspx?p=2952392&seqNum=24) — "refactor the code so that any comment becomes superfluous"
- [Fowler — refactoring catalog](https://refactoring.com/catalog/) — the named dissolving moves
- [Ousterhout ⇄ Martin debate](https://github.com/johnousterhout/aposd-vs-clean-code) — the jointly-signed floor and the class-C boundary
- [Google eng-practices — comments explain *why*, not *what*](https://google.github.io/eng-practices/review/reviewer/looking-for.html)
- [Anthropic prompting best practices — Overeagerness](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices) — "Only add comments where the logic isn't self-evident"
