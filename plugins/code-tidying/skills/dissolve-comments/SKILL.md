---
description: "Enforce self-describing code over a diff, branch, or ranked repo: a three-way triage: delete zero-information comments, dissolve code-expressible ones into names and structure by behavior-preserving refactors, keep only terse load-bearing comments code cannot express. Deletions and local renames need a token proof, other refactors a test net, else proposed; 'safe' removals only, 'aggressive' deletes non-exempt comments with narrative staged, 'strip' deletes all but exempt surfaces, no rewrite. Use when: 'dissolve comments', 'remove comments', 'strip all comments', 'strip agent comments', 'too many comments', 'aggressive comment removal', 'make it self-documenting', 'make the code expressive', 'comments must earn their keep', after an agent wrote over-commented code. Skip when: residue classification (audit-comment-residue), tidyings (tidy), simplification (batch-simplify), markdown noise (audit-noise), why-comments (tidy #14). Never touches public-API docs, license headers, or machine-read directives."
argument-hint: "[safe] [aggressive|strip] [override] [--notes <path>] [target]"
allowed-tools: ["Bash(${CLAUDE_SKILL_DIR}/scripts/scope-code-files.sh:*)", "Bash(${CLAUDE_SKILL_DIR}/scripts/comment-tooling-probe.sh:*)", "Bash(${CLAUDE_SKILL_DIR}/scripts/change-shape.sh:*)", "Bash(${CLAUDE_SKILL_DIR}/scripts/comment-census.sh:*)", "Bash(${CLAUDE_SKILL_DIR}/scripts/commented-out-code.sh:*)", "Bash(${CLAUDE_SKILL_DIR}/scripts/rank-comment-targets.sh:*)", "Bash(git branch:*)", "Bash(git log:*)", "Bash(git ls-files:*)", "Bash(grep:*)", "Bash(echo:*)"]
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

Both run before the argument is read, so each is a preview: the scope line is **void whenever the
argument names an explicit target**, and the tooling line is re-derived in step 3.

## Variables

Arguments: `$ARGUMENTS`

Posture: `${user_config.comment_posture}` (unexpanded or empty means `strict`; any value outside
`strict`, `balanced`, `conservative`, `aggressive` is read as `strict`).
Kept-comment line budget: `${user_config.class_c_max_lines}` (unexpanded or empty means `2`).
Apply proven local renames without a test net: `${user_config.apply_local_renames}` (unexpanded or
empty means `true`).
HARD path exclusions: `${user_config.hard_exclusions}` (unexpanded, empty, or any value outside
`enforce` and `advisory` means `enforce`).

## Purpose

The enforcement counterpart to `/code-tidying:audit-comment-residue`: where that skill classifies
and reports, this one edits. It makes the code in scope self-describing and expressive, and it
removes every comment there that does not earn its keep, with "earn its keep" defined by the floor
the canonical sources jointly sign: *implementation code only needs comments when the code is
nonobvious* (Martin ⇄ Ousterhout debate). The prime driver is agent-written code, which
over-narrates by default; this is a **tidy-after-generation** pass, not a generation-time ban. The
target is over-narration, not density: a hand-written contract-heavy file is legitimately
comment-dense, and a full pass over one can correctly end at zero edits.

## The three-way triage

Every comment in scope gets exactly one classification. Full doctrine, the earn-its-keep test, the
line budget, and worked examples: [reference/triage.md](reference/triage.md).

| Class | Test | Treatment |
|---|---|---|
| **A, zero/negative information** | Restates adjacent code, obsolete, commented-out code | Delete outright, certified by the token proof |
| **B, information code could carry** | The comment compensates for a naming/structure deficiency. Empty by construction on a data or config file (TOML, YAML, JSON), which has no naming channel, so the pass there degrades to A plus C | Refactor until the comment is superfluous, then delete, never delete first |
| **C, information code cannot carry** | Why/rationale, constraint, warning, contract, negative or operational information | **Kept** when load-bearing at the point of reading and not recoverable where a reader would look; held to the line budget once the exempt-surface check has cleared it, rewritten terser when over it, narrative staged. Under `aggressive` only a warning of consequence is kept, and under `strip` nothing in this class is |
| **C, same test failed** | Inexpressible, but the earn-its-keep test's criterion 2 fails: recoverable from version control, an ADR, or an external source | **Deleted** under `strict`, certified by the same token proof class A uses, narrative staged before the deletion is final; **proposed** under `safe` and `conservative`, which apply class-A deletions only. Under `aggressive` and `strip` criterion 2 is not run at all on a non-survivor: the comment is staged and deleted whether or not the reasoning is recoverable. The negative branch of the class-C test, not a fourth class |

The two class-C rows are one class and one test, whose three criteria must **all** hold, named on
each side, so a comment that fails it has somewhere to go. A criterion-1 failure is not this branch:
expressible is class B, redundant with code that IS present is class A.

Class-B moves and their tiers: [reference/dissolving-moves.md](reference/dissolving-moves.md).

## Action router

| Argument | Action |
|---|---|
| *(empty)* | Triage the code files of the narrowest scope that resolves: uncommitted diff → branch diff → whole repository, resolved by `scope-code-files.sh` ([reference/scope.md](reference/scope.md)). On the repository rung, order the files with `rank-comment-targets.py` first. Pass `--allow-path <glob>` for each path the `override` argument or the repository overrides file lifted, so the administrative gate does not re-drop those files and does not ungate every other administrative path. Pass `--override-exclusions` only when `hard_exclusions` is `advisory`, which lifts the whole HARD path list. |
| `<path>` | Triage a single file or directory (already-committed code is fine here). The pre-computed scope line above is **void** under an explicit target: that line runs the diff ladder unconditionally, so it names files this run is not triaging. Ignore it and do not run `scope-code-files.sh`. |
| `safe [target]` | **Safe mode**: only class-A deletions are applied; every class-B treatment and class-C rewrite is emitted as a proposal. For codebases whose guardrails you do not know. |
| `aggressive [target]` | **Aggressive dial**: the survivor list below is the whole of what stays. Every other comment goes, rationale included, with its narrative staged; a class-B comment is dissolved when its move's gate passes and otherwise kept with a proposal. Gates are unchanged. Combines with `override` and `--notes`; `safe` beats it. |
| `strip [target]` | **Strip**: delete every comment except the survivor list, rewrite no code, certify each deletion COMMENT-ONLY, and stage the narrative. A class-B comment is deleted rather than dissolved, so its information reaches the staged block instead of the code. `safe` beats it, and `strip` beats `aggressive`. |
| `--notes <path>` | Append the staged block to `<path>` as well as reporting it. The path must be untracked or outside the repository, checked with `git ls-files --error-unmatch <path>`; a tracked path is refused, the run continues, and the block is reported only. |
| `override [target]` | **Lift the GLOBAL HARD path list** for this run's target, so `/code-tidying:dissolve-comments override ruff.toml` triages a file the list would otherwise drop. Combines with `safe`. Strip the token before reading the target; match it whole, and treat `./override` as a path. Path entries only, and every lifted path is named in the step 7 report with the channel that lifted it. |

Posture `conservative` is safe mode as a standing default; `balanced` keeps the full contract but
reports an over-budget class-C comment instead of rewriting it; posture `aggressive` is the
`aggressive` row above as a standing default. A per-run token beats the standing posture, and
precedence among tokens is `safe`, then `strip`, then `aggressive`. `./safe`, `./aggressive`,
`./strip` and `./override` are paths, not tokens.

**No knob loosens a gate.** `aggressive` and `strip` widen *what is triaged away*; they change no
gate and no proof. Every applied deletion still carries the COMMENT-ONLY verdict, every applied
function-local rename still carries RENAME-ONLY, tier-2 and tier-3 moves still need a discovered
test net, and an UNPROVABLE file still yields proposals only. A `strict` run and an `aggressive` run
differ in what they decide to remove, never in what they are allowed to prove.

**What survives `aggressive` and `strip`** (the whole list; `reference/safety.md` carries the
detail):

- the exempt surfaces: public-API doc comments **in the language's structured doc-comment form**
  (a docstring, an XML doc, JSDoc or TSDoc, a GoDoc sentence) attached to a public declaration; a
  free-form comment block in a language with no doc-comment form, shell and make among them, is not
  a doc comment and takes the ordinary triage. Also legal headers, machine-read directives (universal
  and repo-local), units, sentinels, ownership, thread-safety and ordering **annotations on the
  adjacent declaration** (`# seconds`, `# -1 means unset`; a sentence explaining a choice is not an
  annotation), suppression justifications paired with their waiver, `TODO(#issue)` markers, and
  lines carrying `dissolve-comments-ignore`;
- a comment that is one half of a comment-plus-regression-test pair, because deleting half of a
  paired record is a correctness bug;
- under `aggressive` only, a **warning of consequence**: a comment naming a runtime failure a caller
  hits by using the code as written, such as a required call order, a precondition, or a required
  call form a caller would otherwise get wrong. The *reason a
  value was chosen*, another system's limit, an upstream's behavior, a past incident, is rationale
  rather than a warning: it is staged and deleted. A warning earns its keep only when the failure it
  names is **not visible in the adjacent code**: if the body a reader is already looking at shows
  the behavior (an `exit` in the function, a guard, a return), the comment restates code and goes; Held to `class_c_max_lines` and rewritten terser
  when over it. Every survivor must be succinct, clear, and justified in the report: name the
  consequence, not the history.

In `strict`, `balanced`, `conservative` and `safe`, doubt keeps the comment: "when uncertain, keep
or propose" is doctrine, not timidity. Doubt means an unresolved *classification*, not a resolved
one whose verdict is delete. A criterion-2 failure established by the step-5 evidence check is not
doubt, and the tie-break does not reinstate it; that rule is what stops the earn-its-keep test from
collapsing into "keep everything".

Under `aggressive` and `strip` the tie-break is narrower, because everything not on the survivor
list is leaving anyway: doubt whether a comment is an exempt surface, a paired record, or a
load-bearing warning **keeps it**. Doubt between classes does not keep it, and resolves to the
treatment that preserves the information: A-versus-B doubt resolves to B (dissolve when the gate
passes, else keep with a proposal under `aggressive`, delete with the narrative staged under
`strip`), and B-versus-C doubt resolves to B.

Default mode applies the full contract: class A applies, each deletion certified by a token-level
proof that no code changed; class B applies **per its tier**: a function-local rename behind the
same proof (RENAME-ONLY), an additive move behind a discovered test net, an interface-creating
move behind the net and proposal-first. Whatever a tier's gate does not pass is proposed. Tiers,
the proof tool, the test-discovery procedure, and the mode ladder: [reference/safety.md](reference/safety.md).

**Class B applies less than it looks like it does**, and a run planned around it should know that
first: 2 of 16 moves need no test net, 0 of 16 apply with tree-sitter absent, and no move dissolves
a *why*. Both limits are deliberate. See "Apply capacity" in
[reference/dissolving-moves.md](reference/dissolving-moves.md) for the numbers and what follows
from them.

## Hard rules

- **Never delete information without a landing place.** A class-B comment's information moves into
  code *before* the comment goes, except under `strip`, which rewrites nothing and sends that
  information to the staged block instead. Removed narrative (rationale, justification) is staged in
  the output as a proposed commit-message block for `/source-control:commit`, and `--notes <path>`
  appends it to an untracked or out-of-repo file as well. The block carries an
  `Intentional-removal:` line only when the target repository's own scripts or CI read that trailer
  (`grep -rl 'Intentional-removal:'` over its gate scripts and workflows); elsewhere the line is
  noise. On an explicit target over already-committed code the landing place is the next commit
  touching that code, named in the report. Text is never silently destroyed.
- **Every applied edit passes the gate its tier names; lint never opens one.** Deletions and
  function-local renames are certified by `${CLAUDE_SKILL_DIR}/scripts/change-shape.sh`
  (COMMENT-ONLY, RENAME-ONLY); additive and interface-creating moves need a discovered test net.
  Any other verdict reverts the edit and demotes it to a proposal. A Python docstring is a string
  token, not a comment, so removing one reads CODE-CHANGED and is always a proposal, private
  docstrings included.
- **RENAME-ONLY is a shape claim, not a safety claim.** It rejects a rename that misses a
  reference or lands on a name the file already uses, but cannot see other files, reflection, or
  string-keyed access. A rename applied on its strength is reported with its mapping, never silently.
- **Exempt surfaces are invisible to this skill** ([reference/safety.md](reference/safety.md)):
  public-API doc comments; legal headers; machine-read directives, universal and repo-local;
  unit, sentinel, ownership, thread-safety and ordering annotations on the adjacent declaration,
  never a sentence explaining a choice; suppression justifications; `TODO(#issue)` markers; lines
  carrying `dissolve-comments-ignore`. **Negative and operational information are not on that list.** They
  are class C with a raised evidence bar, held to the same test and budget as any class-C comment.
  Exempting the category outright would contradict this skill's own eval 13.
- **A paired record is never half-deleted.** A comment asserting something about code that is not
  present, paired with a regression test that pins it, is one artifact in two places; deleting the
  comment alone is a correctness bug. Kept in every mode, `strip` included.
- **An identifier named in a repo-local marker row is never renamed.** A gate that pins
  `<name>=` as an exactly-once marker (step 2 discovers these) turns that spelling into compiler
  input. Dissolve the comment if it earns dissolving, but leave the identifier alone.
- **Path exclusions are the plugin's standard tier**, tidy's
  [exclusions reference](${CLAUDE_PLUGIN_ROOT}/skills/tidy/reference/exclusions.md) GLOBAL HARD
  list. Agent/enforcement config, CI workflows, hook chains, lint config are not edited unless a
  path is lifted through one of that reference's section 4 channels: the `override` argument above,
  a glob in the repository's `.claude/code-tidying/exclusion-overrides.md`, or
  `hard_exclusions: advisory`. Precedence per path is argument, then repository file, then
  userConfig, then enforced. Lifting reaches path entries only; the behavioral guards below, the
  work-tracking entries, and SELF-UPDATE EXTRA HARD hold at every setting, and a lifted path that is
  edited without appearing in the report is the failure the channel exists to avoid.
- **A comment shape the repository uses at scale is proposed, never applied.** A shape recurring
  across dozens of files is a house convention one run does not overturn; propose it with the count.
- **Code files only.** Markdown is `/docs-hygiene:audit-noise` territory.
- **Never add comments, never flag missing ones.** The add-side is `/code-tidying:tidy` #14.
- **Structure-only edits.** Class-B moves are behavior-preserving refactorings from the named
  catalog; any candidate edit that would change behavior is out of scope, whatever its comment.

## Workflow

1. **Scope.** Resolve targets from the action router. An explicit `<path>` target is the whole scope:
   the pre-computed scope line is void, `scope-code-files.sh` is not run, and no file outside the
   target is triaged or reported. Empty argument: run `scope-code-files.sh` (never the truncated
   preview), confirm a widening to the repository rung interactively, and take any widened rung in
   safe mode when non-interactive, **whatever the posture or dial token**: `aggressive` and `strip`
   reach a widened rung only through an interactive confirmation, and an explicit target is the
   other way to mean it. **You are non-interactive whenever the `AskUserQuestion` tool is
   unavailable.** There, take the widened rung in safe mode, say "safe mode, non-interactive
   widening" in the report, and name the explicit-target re-run that would apply the full contract;
   do not end the turn on a question nobody can answer. The same holds when the ladder stops on a
   rung with no code files: report the rung and its count, say the session is non-interactive, name
   the explicit-target re-run, and stop there rather than asking. On the repository rung, run `${CLAUDE_SKILL_DIR}/scripts/rank-comment-targets.sh` and triage
   in its order. When an override channel is active, hand its resolved reach to the ranker so the
   administrative gate does not re-drop a lifted path: `--allow-path <glob>` per path the `override`
   argument or the repository overrides file lifted, and `--override-exclusions` only for
   `hard_exclusions=advisory`, whose reach genuinely is every path. The all-paths flag for a
   specific lift lets the whole administrative tree compete for the `--top` cutoff against the one
   file the operator named. **Exit 3
   from it or from the census means the analysis layer is missing, never that there is nothing to
   rank.** Relay the script's stderr, which names the install command, and stop rather than
   proceeding on an empty ranking. Resolve the section 4 override channels first, then drop excluded
   paths and exempt surfaces, listing **every dropped path with its reason**, not only a per-reason
   tally: a silently dropped file is indistinguishable from one triaged and kept. Check survivors for
   SSOT/materialized-copy declarations (triage the source, run its sync, never touch a copy). Where
   a source has synced copies, report how many and whether the sync gate demands a version bump per
   consuming plugin; a comment-only edit that would force version bumps on consumers is **proposed,
   never applied**, unless the user named the source as the target. The propagation cost is the
   decision, and it is the user's, not the run's. Done
   when the file list, the per-path drop list, the tally, and the lifted set with each entry's
   channel are written down. A lifted file outside both grammar tables (`.json`) is neither scanned
   for commented-out code nor certified for deletion.
2. **Discover repo-local machine-read markers** before any comment is classified: a marker the
   repo's own gates read is compiler input that looks like prose. Whole-repository scan, test
   fixtures treated as live, query form varied before concluding absence
   ([reference/safety.md](reference/safety.md)). Then check whether an **external gate watches the
   target's content**: grep the repository for its path and basename in gate scripts, CI config, and
   incident or exemption lists. A gate pinning lines of it as exactly-once markers makes those lines
   a per-line exempt surface. Done when the discovered families (or an explicit "none found") and
   any pinning gate are in the report.
3. **Re-run `comment-tooling-probe.sh`** here and state the layer it reports; the pre-computed line
   is a preview taken before the scope was known. The layer sets the ceiling: at grep precision a
   language with heredocs or block comments gets no applied edits, with tree-sitter absent no
   deletion or rename carries a proof, and the 12 extensions no grammar covers stay proposals even
   when it is present ([reference/safety.md](reference/safety.md)). Name each absent layer's lost
   capability as the probe phrases it. Done when it is in the report.
4. **Self-parse, then baseline the census.** First run `${CLAUDE_SKILL_DIR}/scripts/change-shape.sh <file> <file>` on each
   scoped file. A file that cannot prove itself unchanged against itself (exit 21, UNPROVABLE) has a
   construct the grammar rejects, so no deletion or rename anywhere in it can ever carry a proof.
   Name those files and their count in the report **now**, and triage them as proposals only, rather
   than discovering the closed gate one comment at a time at step 6. Then run
   `${CLAUDE_SKILL_DIR}/scripts/comment-census.sh --json` over the scope, writing it to
   `${TEMP:-${TMPDIR:-/tmp}}/dissolve-comments/<run-id>/baseline.json` with `<run-id>` unique per
   run; step 7 reads that exact path back. `TEMP` comes first because Git Bash on Windows sets
   `TMPDIR=/tmp`, which resolves to the drive root rather than the platform temp directory and
   accumulates there silently. **Exit 3 is a stop, not a zero:** neither `scc` nor pygments
   resolved, so there is no baseline and step 7's delta is unobtainable. Report the layer,
   quote the script's install hint, and stop; an all-zero baseline reports every later count as an
   improvement. Done when the file exists, or the run has stopped with the missing layer named.
5. **Triage.** Classify every remaining comment A/B/C per [reference/triage.md](reference/triage.md).
   Run `${CLAUDE_SKILL_DIR}/scripts/commented-out-code.sh` (and Ruff ERA001 on Python, via the repository's pinned wrapper where
   one exists) for **candidates, each verified by reading it before deletion**, never as settled
   class-A input: it calls a comment code whenever the body reparses, so prose carrying
   backtick-quoted identifiers hits. A hit whose text is a sentence, not a statement, is prose. That
   test does not settle an indented usage example under a documentation block
   (`#   hook::require_jq PostToolUse my-plugin "$INPUT"`), which is a statement and still
   documentation. Reading decides: a line demonstrating how to call the thing the block documents is
   prose, whatever it parses as.
   **Criterion 2 is decided on evidence, never on impression.** For every class-C candidate whose
   content is rationale, run `git log -L <start>,<end>:<file>` over its own lines and check the
   repo's ADR or decision-log directory where one is declared; recoverable there **fails** the
   criterion, absent from both **passes**, unreadable history is recorded as unavailable and keeps
   the comment. Under `aggressive` and `strip` this evidence check is skipped for every comment
   outside the survivor list: the verdict is the same either way, and the `git log -L` per comment
   is the expensive half of a run. Full procedure: [reference/triage.md](reference/triage.md). Done when every comment
   carries one class and every class-C candidate a criterion-2 verdict with its evidence.
6. **Apply**, one item at a time, each behind its tier's gate. Class A: delete, run
   `change-shape.py` on before and after; anything but COMMENT-ONLY (exit 0) restores the comment.
   Class B: apply the named move, run the tier's gate, then delete the comment. Class C: check the
   **exempt surfaces before the line budget**, never after, since an exempt comment is out of reach
   at any length. A non-exempt comment that **failed** criterion 2 is, under `strict`, staged then
   deleted behind the same COMMENT-ONLY proof class A uses; under `safe` or `conservative` it is
   proposed instead, since those modes apply class-A deletions only, and a rationale comment is not class
   A however its test resolved. Under `aggressive` and `strip` every non-survivor is staged and then
   deleted behind that same COMMENT-ONLY proof, class C included, and under `strip` a class-B
   comment takes that path rather than its move; under `aggressive` a class-B move still applies
   only when its tier's gate passes, and the comment stays with a proposal when it does not. A non-exempt comment over budget is rewritten to the budget under
   `strict` with the narrative staged, reported instead under `balanced`. **A kept comment stays
   where it is and keeps its own words**: rewriting shortens the comment that is there, and never
   relocates it, merges two comments, or writes a new one. A comment whose referent is gone is
   deleted, not re-authored. its carve-out reason names
   every kept comment by file and line, written once for a group that enumerates its members. Where
   most of a file's class-C comments carry contract, negative, or operational information, say so
   once as a whole-file verdict with its count and suspend the budget for that file. Criterion 2
   still runs on every comment in it. A failed gate reverts, restores, and demotes to a proposal
   quoting the verdict. Done when every item is applied with its verdict or proposed with a reason.
7. **Report.** Tooling layer, discovered markers, the per-path drop list from step 1, and every
   lifted HARD path with the channel that lifted it first; then per file: counts per class, applied
   versus proposed with each applied item's verdict (and the mapping for every RENAME-ONLY), the
   staged commit-message block, the class-C keeps and rewrites with one-line reasons (grouped where
   several share one, every member still named) and **each keep naming its criterion-2 evidence**
   from step 5, plus any whole-file budget suspension. Under `aggressive` and `strip` a keep names
   which survivor rule earned it (exempt surface, paired record, warning of consequence) in place of
   criterion-2 evidence, and the report names the block's landing place: the pending commit, the
   next commit touching already-committed code, or the `--notes` path, with a refused tracked path
   said plainly. Under a whole-file verdict, report that
   file's class-C keeps as a count per reason group rather than a line each; the per-keep evidence
   line is owed only for keeps the run actually searched. Then the census delta, `comment-census.py
   --baseline` pointed at the exact `baseline.json` step 4 wrote, in lines, bytes and estimated
   tokens. A scope whose every file was dropped reports the tally rather than exiting silently. When
   the census could not run, say so in place of the delta line and name the missing layer. An
   absent delta is never reported as `+0`. The user reviews the diff; this skill does not commit.
   Done when the delta line, or the explicit reason there is none, is printed.

## What this skill is NOT

- **Not "delete all comments."** `strip` comes closest and still keeps the survivor list: exempt
  surfaces and paired records are never touched, in any mode. Without a dial token, class C survives
  on the earn-its-keep test.
- **Not `/code-tidying:audit-comment-residue`**, the read-only residue classifier. Run that for
  findings without changes.
- **Not `/code-tidying:tidy` or `/code-tidying:batch-simplify`.** No lane rotation, no scope
  budget, no wave machinery: one pass over one resolved scope.
- **Not a bug-hunter or general simplifier.** `/code-review` and `/simplify` own those.

## Next

`/source-control:commit`, which takes the staged commit-message block this run printed and lands the
removed narrative with the diff that removed it.

## Gotchas

- A comment that *looks* like restatement can disambiguate genuinely ambiguous code. Misclassifying
  B as A is the information-destroying failure; when uncertain, keep or propose. Under `aggressive`
  and `strip` the same doubt resolves to B, which is why those modes stage before they delete.
- Rationale for a *rejected* approach has no referent in the adjacent code, the same surface as a
  stale comment. It is class C by default ([reference/safety.md](reference/safety.md)), and under
  `aggressive` and `strip` it is staged and deleted: rejected alternatives belong in the commit or
  PR that removed them.
- Extraction has a cost curve: a name that must grow megasyllabic to stay honest signals the
  information did not fit the name channel. Short name plus terse comment, or Inline Function,
  beats a dishonest long name ([reference/dissolving-moves.md](reference/dissolving-moves.md)).
- A tests/ directory near the target is not a net until it demonstrably covers the touched file.

## Sources

Doctrine, with what each source contributes and two misreadings corrected:
[reference/sources.md](reference/sources.md). Tooling, measurements and install commands:
[reference/tooling.md](reference/tooling.md).
