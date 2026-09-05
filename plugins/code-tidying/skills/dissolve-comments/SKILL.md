---
description: "Enforce self-describing code over a resolved scope (diff, branch, or ranked repository): a three-way comment triage that deletes zero-information comments, dissolves code-expressible comments into names and structure via behavior-preserving refactoring, and keeps only terse, load-bearing comments code cannot express. Deletions and local renames apply behind a token-level proof, other refactors behind a discovered test net, else proposed; 'safe' mode restricts applied edits to removals. Use when: 'dissolve comments', 'remove comments', 'strip agent comments', 'too many comments', 'make it self-documenting', 'make the code expressive', 'comments must earn their keep', after an agent wrote over-commented code. Skip when: read-only residue classification (audit-comment-residue), lane-hunting structural tidyings (tidy), simplification waves (batch-simplify), markdown noise (docs-hygiene audit-noise), adding why-comments (tidy #14). Never touches public-API doc comments, license headers, or machine-read directives."
argument-hint: "[safe] [target]"
disable-model-invocation: false
user-invocable: true
shell: bash
metadata:
  workflow-stage: review
  summary: Dissolve comments into expressive code via triage. Delete, refactor-then-delete, or keep
---

## Repository context. Gather first

Collect these with **individual** Bash calls, one command per call, never combined into a single
invocation:

- Current branch, `git branch --show-current`

Treat a failure (not a repository, git unavailable) as an unknown value and carry on. Keep these as
separate body Bash calls rather than pre-compute lines: the harness runs a skill's whole pre-compute
block as one shell invocation, and a worktree-isolated session refuses a compound command that
contains git.

## Pre-computed context

Current branch: !`git branch --show-current 2>/dev/null || echo "unknown"`
Scope (rung, base, count, then a 10-path preview; re-run the script without `--max` for the full set): !`bash "${CLAUDE_PLUGIN_ROOT}/scripts/scope-code-files.sh" --max 10 2>/dev/null || echo "(not a git repository)"`
Tooling layer (present/absent per analysis layer; an absent row names the capability lost): !`bash "${CLAUDE_PLUGIN_ROOT}/scripts/comment-tooling-probe.sh" 2>/dev/null || echo "(probe unavailable)"`

## Variables

Arguments: `$ARGUMENTS`

Posture: `${user_config.comment_posture}` (unexpanded or empty means `strict`; any value outside
`strict`, `balanced`, `conservative` is read as `strict`).
Kept-comment line budget: `${user_config.class_c_max_lines}` (unexpanded or empty means `2`).
Apply proven local renames without a test net: `${user_config.apply_local_renames}` (unexpanded or
empty means `true`).

## Purpose

The enforcement counterpart to `/code-tidying:audit-comment-residue`: where that skill classifies
and reports, this one edits. It makes the code in scope self-describing and expressive, and it
removes every comment there that does not earn its keep, with "earn its keep" defined by the floor
the canonical sources jointly sign: *implementation code only needs comments when the code is
nonobvious* (Martin ⇄ Ousterhout debate). The prime driver is agent-written code, which
over-narrates by default; this is a **tidy-after-generation** pass, not a generation-time ban.

## The three-way triage

Every comment in scope gets exactly one classification. Full doctrine, the earn-its-keep test, the
line budget, and worked examples: [reference/triage.md](reference/triage.md).

| Class | Test | Treatment |
|---|---|---|
| **A, zero/negative information** | Restates adjacent code, obsolete, commented-out code | Delete outright, certified by the token proof |
| **B, information code could carry** | The comment compensates for a naming/structure deficiency | Refactor until the comment is superfluous, then delete, never delete first |
| **C, information code cannot carry** | Why/rationale, constraint, warning, contract, negative or operational information | Keep only if load-bearing at the point of reading; held to the line budget, rewritten terser when over it, narrative staged |

Class-B moves and their tiers: [reference/dissolving-moves.md](reference/dissolving-moves.md).

## Action router

| Argument | Action |
|---|---|
| *(empty)* | Triage the code files of the narrowest scope that resolves: uncommitted diff → branch diff → whole repository, resolved by `scope-code-files.sh` ([reference/scope.md](reference/scope.md)). On the repository rung, order the files with `rank-comment-targets.py` first. |
| `<path>` | Triage a single file or directory (already-committed code is fine here). |
| `safe [target]` | **Safe mode**: only class-A deletions are applied; every class-B treatment and class-C rewrite is emitted as a proposal. For codebases whose guardrails you do not know. |

Posture `conservative` is safe mode as a standing default; `balanced` keeps the full contract but
reports an over-budget class-C comment instead of rewriting it. In every posture and mode, doubt
keeps the comment: "when uncertain, keep or propose" is doctrine, not timidity.

Default mode applies the full contract: class A applies, each deletion certified by a token-level
proof that no code changed; class B applies **per its tier**: a function-local rename behind the
same proof (RENAME-ONLY), an additive move behind a discovered test net, an interface-creating
move behind the net and proposal-first. Whatever a tier's gate does not pass is proposed. Tiers,
the proof tool, the test-discovery procedure, and the mode ladder: [reference/safety.md](reference/safety.md).

## Hard rules

- **Never delete information without a landing place.** A class-B comment's information moves into
  code *before* the comment goes. Removed narrative (rationale, justification) is staged in the
  output as a proposed commit-message block for `/source-control:commit`. Text is never silently
  destroyed.
- **Every applied edit passes the gate its tier names; lint never opens one.** Deletions and
  function-local renames are certified by `${CLAUDE_PLUGIN_ROOT}/scripts/change-shape.py`
  (COMMENT-ONLY, RENAME-ONLY); additive and interface-creating moves need a discovered test net.
  Any other verdict reverts the edit and demotes it to a proposal.
- **RENAME-ONLY is a shape claim, not a safety claim.** It rejects a rename that misses a
  reference or lands on a name the file already uses, but cannot see other files, reflection, or
  string-keyed access. A rename applied on its strength is reported with its mapping, never silently.
- **Exempt surfaces are invisible to this skill** ([reference/safety.md](reference/safety.md)):
  public-API doc comments; legal headers; machine-read directives, universal and repo-local;
  units, sentinels and suppression justifications; negative and operational information;
  `TODO(#issue)` markers; lines carrying `dissolve-comments-ignore`.
- **Path exclusions are the plugin's standard tier**, tidy's
  [exclusions reference](${CLAUDE_PLUGIN_ROOT}/skills/tidy/reference/exclusions.md) GLOBAL HARD
  list. Agent/enforcement config, CI workflows, hook chains, lint config are never edited.
- **Code files only.** Markdown is `/docs-hygiene:audit-noise` territory.
- **Never add comments, never flag missing ones.** The add-side is `/code-tidying:tidy` #14.
- **Structure-only edits.** Class-B moves are behavior-preserving refactorings from the named
  catalog; any candidate edit that would change behavior is out of scope, whatever its comment.

## Workflow

1. **Scope.** Resolve targets from the action router. Empty argument: run `scope-code-files.sh`
   (never the truncated preview), confirm a widening to the repository rung interactively, and
   take any widened rung in safe mode when non-interactive. On the repository rung, run
   `rank-comment-targets.py` and triage in its order. Drop excluded paths and exempt surfaces with a
   per-reason tally; check survivors for SSOT/materialized-copy declarations (triage the source,
   run its sync, never touch a copy). Done when the file list and the tally are written down.
2. **Discover repo-local machine-read markers** before any comment is classified: a marker the
   repo's own gates read is compiler input that looks like prose. Whole-repository scan, test
   fixtures treated as live, query form varied before concluding absence
   ([reference/safety.md](reference/safety.md)). Done when the discovered families, or an explicit
   "none found", are in the report.
3. **Read the tooling layer** from the probe and state it. The layer sets the ceiling: at grep
   precision, a language with heredocs or block comments gets no applied edits. Name each absent
   layer's lost capability as the probe phrases it. Done when the layer line is in the report.
4. **Baseline the census.** Run `comment-census.py --json` over the scope and keep the output; it is
   the before-figure for the delta in step 7 and for the next pass. Done when the file exists.
5. **Triage.** Classify every remaining comment A/B/C per [reference/triage.md](reference/triage.md).
   Feed `commented-out-code.py` (and Ruff ERA001 on Python, via the repository's pinned wrapper
   where one exists) as class-A input. Done when every comment carries exactly one class.
6. **Apply**, one item at a time, each behind its tier's gate. Class A: delete, run
   `change-shape.py` on before and after; anything but COMMENT-ONLY (exit 0) restores the comment.
   Class B: apply the named move, run the tier's gate, then delete the comment. Class C over
   budget: rewrite to the budget under `strict`, stage the narrative; report only under `balanced`.
   A failed gate reverts, restores, and demotes to a proposal quoting the verdict. Done when every
   item is either applied with its verdict or listed as a proposal with its reason.
7. **Report.** Tooling layer and discovered markers first; then per file: counts per class, applied
   versus proposed with each applied item's verdict (and the mapping for every RENAME-ONLY), the
   staged commit-message block, the class-C keeps and rewrites with one-line reasons; then the
   census delta against step 4 (`comment-census.py --baseline`), in lines, bytes and estimated
   tokens. A scope whose every file was dropped reports the tally instead of exiting silently. The
   user reviews the diff; this skill does not commit. Done when the delta line is printed.

## What this skill is NOT

- **Not "delete all comments."** Class C survives on the earn-its-keep test; exempt surfaces are
  never touched.
- **Not `/code-tidying:audit-comment-residue`**, the read-only residue classifier. Run that for
  findings without changes.
- **Not `/code-tidying:tidy` or `/code-tidying:batch-simplify`.** No lane rotation, no scope
  budget, no wave machinery: one pass over one resolved scope.
- **Not a bug-hunter or general simplifier.** `/code-review` and `/simplify` own those.

## Gotchas

- A comment that *looks* like restatement can disambiguate genuinely ambiguous code. Misclassifying
  B as A is the information-destroying failure; when uncertain, keep or propose.
- Rationale for a *rejected* approach has no referent in the adjacent code, the same surface as a
  stale comment. It is class C by default ([reference/safety.md](reference/safety.md)).
- Extraction has a cost curve: a name that must grow megasyllabic to stay honest signals the
  information did not fit the name channel. Short name plus terse comment, or Inline Function,
  beats a dishonest long name ([reference/dissolving-moves.md](reference/dissolving-moves.md)).
- A tests/ directory near the target is not a net until it demonstrably covers the touched file.

## Sources

Doctrine, with what each source contributes and two misreadings corrected:
[reference/sources.md](reference/sources.md). Tooling, measurements and install commands:
[reference/tooling.md](reference/tooling.md).
