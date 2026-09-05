# Safety model — modes, gates, exclusions, staging

The risk being managed: every applied edit is a code change, and each kind of change has a
different strongest available proof that it preserved behavior. The gates below match the proof to
the change instead of demanding one proof (a test run) for all of them. Demanding the test run for
everything is what left the skill inert on any repository without a test suite, which is most of
them, and it was never the strongest proof available for a deletion anyway: a test suite samples
behavior, while a token comparison is exhaustive over the file.

## Mode ladder

| Mode | Class A | Class B | Class C |
|---|---|---|---|
| **Default** | Applied, each deletion certified by the tier-0 proof | Applied per the tier table below; otherwise proposed | Earn-its-keep triage; narrative staging |
| **`safe`** | Applied, same certification | Always proposed — no code-structure change is applied | Same triage; deletions of pure narrative still apply, with staging |

In **no mode** does the skill: apply an edit whose tier gate did not pass, touch an exempt surface
or excluded path, or delete text without a landing place (staging rule below).

## The gates, by what each can prove

| Tier | Edit | Gate | Why this proof and not another |
|---|---|---|---|
| **0** | Class-A deletion | `change-shape.py` verdict **COMMENT-ONLY** | The comment-stripped token sequence is identical, so no code token moved. Exhaustive over the file; needs no tests, no build, no config |
| **1** | Rename Variable / Rename Field on a function-local identifier | verdict **RENAME-ONLY** under one consistent mapping, and the identifier is neither exported nor public | A shape claim: every differing token is an identifier under one injective old→new mapping, no old name survives at an unchanged position, and no new name was already in use in the file. It cannot see other files, reflection, or string-keyed access, so it earns application plus a flagged review line in the report, never silence |
| **2** | Additive local move: Extract Variable, Replace Magic Literal, Introduce Assertion, Slide Statements, Decompose Conditional | discovered test net, run before and after | These add tokens, so the token proof reports CODE-CHANGED by construction and cannot certify them. Only tests attest behavior preservation here |
| **3** | Interface-creating move: Extract Function, Change Function Declaration, Extract Class, Introduce Parameter Object, Move Statements into Function, Replace Inline Code with Function Call | discovered test net, and **always a proposal in a non-interactive run** | Creates or renames an interface other code depends on. Ousterhout (APOSD §9.8) and Anthropic's own overeagerness guidance both warn against automating exactly this; the test net is necessary, not sufficient |

`change-shape.py` is at `${CLAUDE_PLUGIN_ROOT}/scripts/change-shape.py` and carries its verdict in
the exit code: 0 COMMENT-ONLY, 10 RENAME-ONLY, 20 CODE-CHANGED, 21 UNPROVABLE, 3 tooling
unavailable. Run it against the file's content before and after each edit, and before the comment
is deleted. Any verdict other than the tier's required one reverts the edit and demotes the item to
a proposal that quotes the verdict, including which token kinds differed. UNPROVABLE (a parse
error on either side) is a revert, never a pass.

When tree-sitter is unavailable (exit 3), tier 0 falls back to whatever reading layer the tooling
probe reported: a pygments-level read may still apply deletions; a grep-level read applies nothing
in a language with heredocs or block comments, because it cannot tell a comment from string data.
Tier 1 without its proof is tier 2.

Two user-config knobs move tiers without changing any gate: `apply_local_renames=false` makes
tier 1 a proposal even when RENAME-ONLY holds, and posture `conservative` makes every tier above 0
a proposal (safe mode as a standing default). Nothing loosens a gate: no knob applies an edit its
tier's proof did not pass.

## The test net (tiers 2 and 3)

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
- **Repo-local machine-read markers**, discovered per run. See the section below. The universal
  pragmas above are the floor, not the list
- Units, ranges, boundary semantics, sentinel values, ownership and lifetime, thread-safety, and
  ordering guarantees. A comment naming what `-1` or `nullptr` means is a contract, not narration
- Suppression justifications: the reason attached to a lint waiver, a cast-safety claim, or a
  narrowing assertion (`@SuppressWarnings("unchecked") // safe because …`). The waiver is a
  directive and the reason is what makes it reviewable. Removing either breaks the pair
- **Negative information**: what the code deliberately does NOT do, and why an alternative was
  rejected. This class has no referent in the adjacent code, which gives it the same surface
  signature as a stale comment. It is the tool's most likely false positive. See the gotcha below
- **Operational information**: how this component fits the wider system. By construction it cannot
  live in the code of an encapsulated unit without breaking that encapsulation
- `TODO(#issue)` / `FIXME(#issue)` markers tracking real work
- Lines carrying `dissolve-comments-ignore` (on the line or the line immediately before)

### Repo-local machine-read markers: discover, never assume

A marker that a repo's own gates read is compiler input wearing the costume of prose.
`# silent-skip-ok: output discarded by design` reads exactly like a comment a triage pass would
delete, and deleting it turns a sanctioned quiet skip into a gate failure. A fixed list of
universal pragmas does not catch this class, because these markers are invented per repository.

Discover them at scope time, before triage:

1. Grep the target repo for comment-borne markers its own tooling consumes. Look in CI workflows,
   `scripts/`, git hooks, and lint/gate configuration for string literals matched against comment
   text. Marker names usually end in one of `-ok`, `-ignore`, `-allow`, `-skip`, `-disable`, and
   appear in `#`- or `//`-prefixed context. Search for those suffixes as literal text; keep the
   pattern POSIX-portable, since a GNU-only word boundary fails on BSD userland.
2. **Search the whole repository, not only the gate directory.** A marker is frequently read by
   more than the script that defines it.
3. **Treat a marker inside a plugin's or package's own test fixtures as live, not as an example.**
   Fixtures are how gates prove they still work; stripping them breaks the gate's own tests.
4. Add every marker family found to the exempt set for that run, and name them in the report so
   the reader can see what was protected and why.

**A single-form grep is not a search, and here a false negative deletes code.** Discovery failing
to find a marker is not the same as the marker not existing, but this step treats the two
identically unless you widen the query: a name can wrap across a line break in the gate that
documents it, be built by concatenation, differ in case or hyphenation, or be held in a variable
the matcher interpolates. Vary the form before concluding absence: hyphenated and underscored,
singular and plural, the bare suffix on its own, and the enclosing helper's name as well as the
marker's. Prefer finding the code that DOES the matching (the `grep`, `case`, or regex literal a
gate runs against comment text) over guessing the marker's spelling, because the matcher is
findable even when the marker's name is not.

Absence of a finding is a result, and it is the weakest result this step produces: report "no
repo-local markers discovered" rather than staying silent, so a reader can tell discovery ran from
discovery finding nothing. In an unfamiliar repository with gates the run could not enumerate,
treat an unexplained comment near a guard, an early `exit 0`, or a lint waiver as class C by
default rather than betting deletion on a clean discovery pass.

## Path exclusions

The canonical baseline is the plugin's standard tier — tidy's
[exclusions reference](${CLAUDE_PLUGIN_ROOT}/skills/tidy/reference/exclusions.md), GLOBAL HARD
list: the whole `.claude/**` tree plus any script wired as a hook command in
`.claude/settings.json` or `.claude/settings.local.json` (wherever it lives), other agents'
config bundles, `.github/workflows/**` and CI surface, git-hook manager config, cross-ecosystem
lint/style config. Consumer-declared
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

## Gotcha: rejected-alternative rationale reads exactly like residue

The highest-cost misclassification this skill can make is deleting a comment that records why an
approach was **not** taken. Two live examples from this marketplace's own hook tree:

- A guard's header explaining that `git branch -D` is deliberately left unblocked because the
  branch is reflog-recoverable.
- A dispatcher's header explaining why a helper is deliberately not named `dirname`, because a
  function of that name would shadow the real command for every sourced guard.

Neither has a referent in the adjacent code, because the whole content of the claim is an absence.
A classifier keyed on "does this restate the code?" sees the same surface as a stale comment and
scores both as class A. It is wrong in one of those two cases, and the failure is silent: the next
author reintroduces the bug the comment existed to prevent.

Where a repo pairs such a comment with a regression test (this marketplace's `hook-precision`
convention does exactly that), the comment is one half of a two-part artifact. Deleting half of a
paired record is a correctness bug, not a style change.

Test to apply: if a comment asserts something about code that is **not present**, it is class C by
default. Class-A deletion requires the comment to be redundant with code that IS present.

## Gotcha: the earn-its-keep bar is not a licence for a sweep

The empirical record does not support a blanket policy in either direction. An eye-tracking study
of comment effects on program comprehension (Abdelsalam et al., *Empirical Software Engineering*)
measured outcomes ranging from a 30% decrease to a 34% increase in performance depending on the
snippet, with no population-level effect. Comments help and hurt per-comment, not per-corpus.

Ousterhout's asymmetry is the operating reason for the conservative tie-break: *"For me the cost
of missing comments is easily 10-100x the cost of incorrect comments."* Martin does not concede
the ratio, but he does not rebut it either; he reports different experience. Under that asymmetry
a removal tool optimizes the cheap failure mode and worsens the expensive one, so **when uncertain,
keep or propose** is a doctrine requirement rather than timidity.
