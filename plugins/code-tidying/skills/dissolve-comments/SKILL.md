---
description: "Enforce self-describing code over a diff, branch, or ranked repository: a three-way comment triage that deletes zero-information comments, dissolves code-expressible ones into names and structure by behavior-preserving refactoring, and keeps only terse, load-bearing comments code cannot express. Deletions and local renames apply behind a token-level proof, other refactors behind a test net, else proposed; 'safe' mode restricts applied edits to removals. Use when: 'dissolve comments', 'remove comments', 'strip agent comments', 'too many comments', 'make it self-documenting', 'make the code expressive', 'comments must earn their keep', after an agent wrote over-commented code. Skip when: read-only residue classification (audit-comment-residue), structural tidyings (tidy), simplification waves (batch-simplify), markdown noise (docs-hygiene audit-noise), adding why-comments (tidy #14). Never touches public-API doc comments, license headers, or machine-read directives."
argument-hint: "[safe] [target]"
allowed-tools: ["Bash(${CLAUDE_SKILL_DIR}/scripts/scope-code-files.sh:*)", "Bash(${CLAUDE_SKILL_DIR}/scripts/comment-tooling-probe.sh:*)", "Bash(git branch:*)", "Bash(git log:*)", "Bash(grep:*)", "Bash(echo:*)"]
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
contains git. The dated record for that composition claim is the `source-control` plugin's
[worktree/reference/gather-block.md](https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/plugins/source-control/skills/worktree/reference/gather-block.md),
"The pre-compute block runs as one shell invocation".

## Pre-computed context

Scope (rung, base, count, then a 10-path preview; re-run the script without `--max` for the full set): !`${CLAUDE_SKILL_DIR}/scripts/scope-code-files.sh --max 10 2>/dev/null || echo "(not a git repository)"`
Tooling layer (present/absent per analysis layer; an absent row names the capability lost): !`${CLAUDE_SKILL_DIR}/scripts/comment-tooling-probe.sh 2>/dev/null || echo "(probe unavailable)"`

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
| **C, information code cannot carry** | Why/rationale, constraint, warning, contract, negative or operational information | **Kept** when load-bearing at the point of reading and not recoverable where a reader would look; held to the line budget, rewritten terser when over it, narrative staged |
| **C, same test failed** | Inexpressible, but the earn-its-keep test's criterion 2 fails: recoverable from version control, an ADR, or an external source | **Deleted** under `strict`, certified by the same token proof class A uses, narrative staged before the deletion is final; **proposed** under `safe` and `conservative`, which apply class-A deletions only. The negative branch of the class-C test, not a fourth class |

The two class-C rows are one class and one test — three criteria that must **all** hold — named on
each side, so a comment that fails it has somewhere to go. A criterion-1 failure is not this branch:
expressible is class B, redundant with code that IS present is class A.

Class-B moves and their tiers: [reference/dissolving-moves.md](reference/dissolving-moves.md).

## Action router

| Argument | Action |
|---|---|
| *(empty)* | Triage the code files of the narrowest scope that resolves: uncommitted diff → branch diff → whole repository, resolved by `scope-code-files.sh` ([reference/scope.md](reference/scope.md)). On the repository rung, order the files with `rank-comment-targets.py` first. |
| `<path>` | Triage a single file or directory (already-committed code is fine here). |
| `safe [target]` | **Safe mode**: only class-A deletions are applied; every class-B treatment and class-C rewrite is emitted as a proposal. For codebases whose guardrails you do not know. |

Posture `conservative` is safe mode as a standing default; `balanced` keeps the full contract but
reports an over-budget class-C comment instead of rewriting it.

**The posture ladder only descends.** `strict` is both the default and the ceiling; `balanced`,
`conservative` and `safe` each narrow what gets applied, `class_c_max_lines` bottoms out at 1, and
nothing removes more than `strict` does. Deliberate — no knob loosens a gate
([reference/safety.md](reference/safety.md)) — and stated here because a user wanting a more
aggressive pass would otherwise hunt for a setting that does not exist.

In every posture and mode, doubt keeps the comment: "when uncertain, keep or propose" is doctrine,
not timidity. Doubt means an unresolved *classification*, not a resolved one whose verdict is
delete. A criterion-2 failure established by the step-5 evidence check is not doubt, and the tie-
break does not reinstate it; that rule is what stops the earn-its-keep test from collapsing into
"keep everything".

Default mode applies the full contract: class A applies, each deletion certified by a token-level
proof that no code changed; class B applies **per its tier**: a function-local rename behind the
same proof (RENAME-ONLY), an additive move behind a discovered test net, an interface-creating
move behind the net and proposal-first. Whatever a tier's gate does not pass is proposed. Tiers,
the proof tool, the test-discovery procedure, and the mode ladder: [reference/safety.md](reference/safety.md).

**Class B applies less than it looks like it does**, and a run planned around it should know that
first: 2 of 15 moves need no test net, 0 of 15 apply with tree-sitter absent, and no move dissolves
a *why*. Both limits are deliberate — see "Apply capacity" in
[reference/dissolving-moves.md](reference/dissolving-moves.md) for the numbers and what follows
from them.

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
  units, sentinels and suppression justifications; `TODO(#issue)` markers; lines carrying
  `dissolve-comments-ignore`. **Negative and operational information are not on that list** — they
  are class C with a raised evidence bar, held to the same test and budget as any class-C comment.
  Exempting the category outright would contradict this skill's own eval 13.
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
   `rank-comment-targets.py` and triage in its order; **exit 3 from it or from the census means the
   analysis layer is missing, never that there is nothing to rank** — relay the script's stderr,
   which names the install command, and stop rather than proceeding on an empty ranking. Drop
   excluded paths and exempt surfaces, listing **every dropped path with its reason**, not only a
   per-reason tally: a count cannot tell the user which file went, and a silently dropped file is
   indistinguishable from one that was triaged and kept. Check survivors for SSOT/materialized-copy
   declarations (triage the source, run its sync, never touch a copy). Done when the file list, the
   per-path drop list, and the tally are written down.
2. **Discover repo-local machine-read markers** before any comment is classified: a marker the
   repo's own gates read is compiler input that looks like prose. Whole-repository scan, test
   fixtures treated as live, query form varied before concluding absence
   ([reference/safety.md](reference/safety.md)). Done when the discovered families, or an explicit
   "none found", are in the report.
3. **Read the tooling layer** from the probe and state it. The layer sets the ceiling: at grep
   precision a language with heredocs or block comments gets no applied edits, with tree-sitter
   absent no deletion or rename carries a proof, and the 13 extensions no grammar covers stay
   proposals even when it is present ([reference/safety.md](reference/safety.md)). Name each absent
   layer's lost capability as the probe phrases it. Done when the layer line is in the report.
4. **Baseline the census.** Run `comment-census.py --json` over the scope and keep the output; it is
   the before-figure for the delta in step 7 and for the next pass. **Exit 3 is a stop, not a
   zero:** it means neither `scc` nor pygments resolved, so there is no baseline and step 7's delta
   is unobtainable. Report the layer, quote the script's install hint, and stop; never continue with
   an all-zero baseline, which would report every later count as an improvement. Done when the file
   exists, or the run has stopped with the missing layer named.
5. **Triage.** Classify every remaining comment A/B/C per [reference/triage.md](reference/triage.md).
   Feed `commented-out-code.py` (and Ruff ERA001 on Python, via the repository's pinned wrapper
   where one exists) as class-A input.
   **Criterion 2 is decided on evidence, never on impression.** For every class-C candidate whose
   content is rationale, run `git log -L <start>,<end>:<file>` over its own lines and check the
   repo's ADR or decision-log directory where one is declared; recoverable there **fails** the
   criterion, absent from both **passes**, unreadable history is recorded as unavailable and keeps
   the comment. Full procedure: [reference/triage.md](reference/triage.md). Done when every comment
   carries exactly one class and every class-C candidate carries a criterion-2 verdict with the
   evidence that produced it.
6. **Apply**, one item at a time, each behind its tier's gate. Class A: delete, run
   `change-shape.py` on before and after; anything but COMMENT-ONLY (exit 0) restores the comment.
   Class B: apply the named move, run the tier's gate, then delete the comment. Class C that
   **failed** the earn-its-keep test: under `strict`, stage the narrative then delete behind the
   same COMMENT-ONLY proof class A uses; under `safe` or `conservative`, propose it instead — those
   modes apply class-A deletions only, and a rationale comment is not class A however its test
   resolved. Class C over budget: rewrite to the budget under `strict`,
   stage the narrative; report only under `balanced`. A failed gate reverts, restores, and demotes
   to a proposal quoting the verdict. Done when every item is either applied with its verdict or
   listed as a proposal with its reason.
7. **Report.** Tooling layer and discovered markers first, then the per-path drop list from step 1;
   then per file: counts per class, applied versus proposed with each applied item's verdict (and
   the mapping for every RENAME-ONLY), the staged commit-message block, the class-C keeps and
   rewrites with one-line reasons, **each keep naming its criterion-2 evidence** from step 5; then
   the census delta against step 4 (`comment-census.py --baseline`), in lines, bytes and estimated
   tokens. A scope whose every file was dropped reports the tally instead of exiting silently. When
   the census could not run, say so in place of the delta line and name the missing layer — an
   absent delta is never reported as `+0`. The user reviews the diff; this skill does not commit.
   Done when the delta line, or the explicit reason there is none, is printed.

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
