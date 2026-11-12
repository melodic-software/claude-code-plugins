# Remove: the workflow

The default action and `report`. Scripts below are in the skill's `scripts/` directory, cited here
as `<skill-dir>/scripts/<name>`, never through a substitution variable. Pointer for where those
variables resolve:
[Available string substitutions](https://code.claude.com/docs/en/skills#available-string-substitutions).
Postures, the floor and the hard rules are in `SKILL.md`.

With a subagent tool available, and unless you are `comment-reviewer` yourself, you run steps 1 and
2 and then dispatch `code-tidying:comment-reviewer` for steps 3 to 7 ("The comment-reviewer agent"
in `SKILL.md`), even when a missing tool means the run can only propose.

## Contents

- [The three-way triage](#the-three-way-triage)
- [Workflow](#workflow)
- [Encode a constraint](#encode-a-constraint)
- [Report mode](#report-mode)

## The three-way triage

Every comment in scope gets exactly one class. Doctrine, the earn-its-keep test, the line budget
and worked examples: [../reference/triage.md](../reference/triage.md).

| Class | Test | Treatment |
|---|---|---|
| **A, zero/negative information** | Restates adjacent code, obsolete, commented-out code, a comment on unreachable code | Delete outright, certified by the token proof. Unreachable code itself goes to `/code-tidying:audit-dead-code` |
| **B, information code could carry** | The comment compensates for a naming or structure deficiency. Empty by construction on a data or config file (TOML, YAML, JSON) | Refactor until the comment is superfluous, then delete; never delete first under `explanatory`. Under `necessary` a move whose gate fails, and under `none` every class-B comment, is deleted instead, narrative staged, with a reshape flag |
| **C, information code cannot carry** | Why or rationale, constraint, warning, contract, negative or operational information | Under `explanatory`: kept when load-bearing at the point of reading and not recoverable where a reader would look, held to the line budget once the floor check has cleared it, rewritten terser over it. Under `necessary` and `none`: the posture's keep list decides |
| **C, same test failed** | Inexpressible, but criterion 2 fails: recoverable from version control, an ADR or an external source | Under `explanatory`: deleted behind the token proof, narrative staged first; proposed under `safe`. Outside `explanatory` criterion 2 is not run on a comment off the keep list |

The two class-C rows are one class and one test, whose three criteria must **all** hold. A
criterion-1 failure is not this branch: expressible is class B, redundant with code that IS present
is class A. Class-B moves and their tiers: [../reference/dissolving-moves.md](../reference/dissolving-moves.md).

**Class B applies less than it looks**: 2 of 17 moves need no test net, none apply with tree-sitter
absent, and no move dissolves a *why* ("Apply capacity" in dissolving-moves.md).

## Workflow

1. **Scope.** An explicit `<path>` target is the whole scope: the pre-computed scope line is void,
   `scope-code-files.sh` is not run, and nothing outside the target is triaged or reported. With
   `--added-since <base>`, the scope is the files and lines `added-lines.sh` prints, inside the
   target when one is given. Empty argument: run `<skill-dir>/scripts/scope-code-files.sh` (never
   the truncated preview). On the `uncommitted` and `branch` rungs, `comment_edit_scope: diff`
   narrows the triage to comments on the lines the change adds (`added-lines.sh <base>` with the
   rung's base, `HEAD` on the `uncommitted` rung; an untracked file counts whole); `files` triages
   every comment in each listed file. Take a widening to the repository rung without asking, in
   every mode. Outside `report`, triage that rung in safe mode, **whatever the posture or token**,
   and report the rung, its file count, and the explicit-target re-run that narrows the scope or
   applies the full contract. **You are non-interactive whenever the `AskUserQuestion` tool is
   unavailable**; then, outside `report`, take any widened rung in safe mode the same way, say "safe
   mode, non-interactive widening" in the report, and name that re-run. The same holds when the
   ladder stops on a rung with no code files:
   report the rung and its count, say the session is non-interactive, name the explicit-target
   re-run, and stop. On the repository rung, run `<skill-dir>/scripts/rank-comment-targets.sh` and
   triage in its order, passing `--allow-path <glob>` for each path the `override` argument or the
   overrides file lifted, and `--override-exclusions` only for `hard_exclusions=advisory`. **Exit 3
   from the ranker or the census means the analysis layer is missing, never that there is nothing
   to rank**: relay the script's stderr, which names the install command, and stop. Resolve the
   override channels first, then drop excluded paths and floor surfaces, listing **every dropped path
   with its reason**: a silently dropped file is indistinguishable from one triaged and kept. Check
   survivors for SSOT/materialized-copy declarations (triage the source, run its sync, never touch a
   copy). Where a source has synced copies, report how many and whether the sync gate demands a
   release record per consuming plugin; a comment-only edit that would force release records on
   consumers is **proposed, never applied**, unless the user named the source as the target. A
   lifted file outside both grammar tables (`.json`) is neither scanned for commented-out code nor
   certified for deletion. Done when the file list, the per-path drop list, the tally, and the
   lifted set with each entry's channel are written down.
2. **Discover repo-local machine-read markers** before classifying any comment: a marker the
   repo's own gates read is compiler input that looks like prose. Whole-repository scan, test
   fixtures treated as live, query form varied before concluding absence
   ([../reference/safety.md](../reference/safety.md)). Then check whether an **external gate
   watches the target's content**: grep the repository for its path and basename in gate scripts,
   CI config, and incident or exemption lists. A gate pinning lines of it as exactly-once markers
   makes those lines part of the floor. Done when the discovered families (or an explicit "none
   found") and any pinning gate are in the report.
3. **Re-run `comment-tooling-probe.sh`** and state the layer it reports. The layer sets the
   ceiling: at grep precision a language with heredocs or block comments gets no applied edits,
   with tree-sitter absent no deletion or rename carries a proof, with `pwsh` absent no
   `.ps1`/`.psm1` edit does, and the 10 extensions neither backend reads stay proposals
   ([../reference/safety.md](../reference/safety.md)). Name each absent layer's lost capability as
   the probe phrases it. Done when it is in the report.
4. **Self-parse, then baseline the census.** Run `<skill-dir>/scripts/change-shape.sh <file> <file>`
   on each scoped file. A file that cannot prove itself unchanged against itself (exit 21,
   UNPROVABLE) has a construct the grammar rejects, so no deletion or rename in it can carry a
   proof: name those files and their count in the report **now** and triage them as proposals only.
   Then run `<skill-dir>/scripts/comment-census.sh --json` over the scope, writing it to
   `${TEMP:-${TMPDIR:-/tmp}}/remove-comments/<run-id>/baseline.json` with `<run-id>` unique per run;
   step 7 reads that exact path back. `TEMP` comes first because Git Bash on Windows sets
   `TMPDIR=/tmp`, which resolves to the drive root. **Exit 3 is a stop, not a zero:** neither `scc`
   nor pygments resolved, so there is no baseline and no step-7 delta. Report the layer, quote the
   script's install hint, and stop. Done when the file exists, or the run has stopped with the
   missing layer named.
5. **Triage.** Classify every remaining comment A/B/C per [../reference/triage.md](../reference/triage.md).
   Run `<skill-dir>/scripts/commented-out-code.sh` (and Ruff ERA001 on Python, via the repository's
   pinned wrapper where one exists) for **candidates, each verified by reading it before
   deletion**, never as settled class-A input: prose carrying backtick-quoted identifiers reparses
   as code. A hit whose text is a sentence is prose, and an indented usage example under a
   documentation block is documentation. **Test each class-C statement about the code against the
   code itself**: read the lines a constraint, warning, contract or thread-safety comment
   describes. If they now say otherwise, the comment is class A: list the lines that disagree. If
   the lines leave the question open, `/discovery:trace-intent`, run for the function or variable
   the comment names, settles it when that skill is among the available skills; a question still
   open after that is reported as unverified and goes on to the criteria. Under `necessary` an
   outside-constraint keep stays only when verified: the adjacent code depends on the named party and
   nothing in this repository could remove the reason. The outside fact itself need not be provable
   from here. Keeps under `necessary` and `none` are
   tested the same way. **Criterion 2 is decided on evidence, never on impression.** Under
   `explanatory`, for every class-C candidate whose content is rationale, run
   `git log -L <start>,<end>:<file>` over its own lines and check the repo's ADR or decision-log
   directory where one is declared; recoverable there **fails** the criterion, absent from both
   **passes**, unreadable history keeps the comment. Under `necessary` and `none` skip this check
   for every comment off the keep list. Done when every comment carries one class, and every
   class-C candidate the run still tests carries a criterion-2 verdict with its evidence.
6. **Apply**, one item at a time, each behind its tier's gate. Class A: delete, run
   `change-shape.sh` on before and after; anything but COMMENT-ONLY (exit 0) restores the comment.
   Class B: apply the named move, run the tier's gate, then delete the comment; under `necessary` a
   failed gate deletes the comment instead with a reshape flag, and under `none` no move is
   attempted. Class C: check the **floor and the public-API doc comments before the line budget**,
   never after. Under `explanatory` a comment that **failed** criterion 2 is staged then deleted
   behind the COMMENT-ONLY proof, and over budget it is rewritten to the budget; under `necessary`
   and `none` every comment off the keep list is staged and deleted behind that proof and is never
   rewritten, and a keep over budget is rewritten. Under `safe` every class-C edit is a proposal. A
   rewrite carries its narrative to the staged block and the COMMENT-ONLY proof; an over-budget
   keep left as it stands is a failed run. **A kept comment stays where it is and keeps its own
   words**: a rewrite shortens it, and never relocates it, merges two comments, or writes a new one.
   Every kept comment is named by file and line with its reason, written once for a group that
   enumerates its members. Under `explanatory`, where most of a file's class-C comments carry
   contract, negative or operational information, say so once as a whole-file verdict with its
   count and suspend the budget for that file. A failed gate reverts, restores, and demotes to a
   proposal quoting the verdict. Done when every item is applied with its verdict or proposed with
   a reason.
7. **Report.** First each setting with its layer, the tooling layer, discovered markers, the
   per-path drop list and every lifted HARD path with its channel; then per file: counts per class,
   applied versus proposed with each applied item's verdict (and the mapping for every
   RENAME-ONLY), the staged commit-message block, and the keeps and rewrites with one-line reasons,
   each `explanatory` keep naming its criterion-2 evidence and each `necessary` or `none` keep the
   rule that kept it. Name the block's landing place: the pending commit, the next commit touching
   already-committed code, or the `--notes` path, with a refused tracked path said plainly. Then the
   census delta, `comment-census.sh --baseline` pointed at the exact `baseline.json` step 4 wrote, in
   lines, bytes and estimated tokens; when the census could not run, say so and name the missing
   layer, never `+0`. Then these lists, each "none" when empty:
   - **Reshape flags**: each deleted our-code surprise or undissolved class-B comment, by file, line
     and symbol, with the move that would make it unnecessary.
   - **ADR candidates**: each deleted rationale for one of the repository's own decisions that names
     the alternative it beat, by file, line and symbol, with whether `/architecture:record-decision`
     recorded it, skipped it, or was not invoked (unattended, `report` mode, or no `architecture`
     plugin), per SKILL.md "ADR candidates". Running as `comment-reviewer`, list each candidate
     only; the orchestrator invokes `record-decision` and fills in the outcome.
   - **Open root-cause work**: each workaround comment removed or proposed for removal, and each
     correctness or safety suppression kept, by file and line with the comment's text. Deleting the
     comment leaves the workaround in the code. When `/corrections:codify` is among the available
     skills and nothing ran in `report`, record each workaround with `/corrections:codify note`.
   - **Encodings**: constraints encoded, offered, or left unenforced (the encode step below).
   - **Agent reruns**: each comment-reviewer report rejected, with its failure.
   The user reviews the diff; this skill does not commit.

## Encode a constraint

A class-C comment stating a constraint the code could enforce (a precondition, a required order, a
value range, a forbidden call or import, a required call form, an invariant a type could hold) gets
one offered encoding, the cheapest that pins it: a type, an assertion (Introduce Assertion, tier 2),
a regression test where one test can pin it at its use, or a lint rule where a static check can
match it across files.

- **Interactive** (`AskUserQuestion` available): ask before encoding. Unattended: encode only when
  `encode_constraints_unattended` is `true`, else offer it in the report.
- An encoding is an edit behind its tier's gate: a test or assertion needs the discovered test net,
  a lint rule goes to the findings file in [Report mode](#report-mode), and a type is tier 3,
  proposal-first.
- **`necessary` and `none`**: once the encoding lands, delete the comment; without one, delete it
  and list the constraint as unenforced. **`explanatory`**: keep the comment and propose the
  encoding.

## Report mode

`report` runs steps 1 to 5 as written, skips step 6, and reports in step 7 with every treatment as
a proposal. It is the mode pull-request prep runs over a change's added lines when unattended without
pre-approval (`report --pipeline --added-since <base>`), and these rules keep that run safe to
start unattended:

- **It never asks.** `report` takes any widened rung without asking, keeps the posture or token in
  effect there because it edits nothing, and names the rung and its file count. It never calls
  `AskUserQuestion` and never ends on a question.
- **Nothing in the repository changes.** No edit, no `--notes` append, no step 4 census or step 7
  delta; say "report mode: no edits, no delta" in place of the delta line. Step 4's self-parse still
  runs, so each proposal can say whether its proof would be available.
- **Each proposal names** the file and line, the class, the treatment the posture in effect would
  apply, and the gate that treatment would need.
- **A constraint comment gets an encoding proposal** per [Encode a constraint](#encode-a-constraint),
  never applied.
- **Lint-rule proposals go to a findings file** at
  `<memory_dir>/comment-pass/<branch-slug>/<YYYYMMDDTHHMMSSZ>-lint-proposals.md`. `<memory_dir>` is
  `.work/` unless the project's instructions declare another working-docs root. `<branch-slug>` is
  the current branch lowercased, with `/` and every character outside `[a-z0-9._-]` replaced by `-`;
  with no branch, write no file and list the rows in the report. Announce the path before writing.
  On the first write, check that the memory root holds a `.gitignore` containing `*`, and create it
  with the Write tool, announced, when absent; never edit the repository's own `.gitignore`, and
  write nothing when the memory root is the repository root. Never overwrite: an existing name takes
  `-2`, then `-3`. The file follows review's findings-file shape
  (<https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/plugins/review/reference/findings-file-shape.md>): frontmatter
  `type: review-findings`, `date:` the write instant, `branch:` the raw branch name, and one
  `## Findings` row per proposal with Tier `SUGGESTION`, Confidence left empty, Location the
  comment's repository-relative `path:line`, Surface(s) `code-tidying:remove-comments`, Finding the
  constraint, and Action the rule to add, with `|` escaped as `\|` and newlines replaced by spaces.
  A write the session's permissions refuse is not a stop: list the rows in the report and say the
  file was not written.
- **The report names that file** and, when `/corrections:codify` is among the available skills,
  offers `/corrections:codify findings <file>` as the next step. It never runs it.
