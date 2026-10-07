---
description: "Run mutation analysis and report surviving mutants: on the diff, or with `--exercised` on the production code the changed tests call, judged against those tests. Restores the code under test and fails if tracked source is not byte-identical; writes no test. One mutant per line, then a fresh-context reviewer judges productive versus arid versus equivalent and says why each productive survivor lived; ranks files by oracle gap and hands survivors to the test-authoring lane. Use when: the user asks to run mutation testing or wants a mutation score for a change ('run mutation testing'), doubts a suite whose coverage report looks healthy ('my coverage is high but I do not trust it'), asks whether the tests actually check the code, asks to audit test quality, or asks for the survivors persisted for the fix pass; after tests go green and before review. Flags: `--exercised [TEST-PATH]`, `--full`, `--paths GLOBS`, `--max N`, `--no-suppress`, `--persist-findings`, `--record-mutants`, `--replay-mutants`."
argument-hint: "--exercised --full --paths --max --no-suppress --persist-findings --record-mutants --replay-mutants"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: test
  summary: Report surviving mutants on the diff or with --exercised, restoration verified, survivors triaged
---

## Repository context. Gather first

Collect these with **individual** Bash calls, one command per call, never combined into a single
invocation:

- Current branch, `git branch --show-current`
- Working tree status (empty = clean), `git status --porcelain | head -20`
- Changed files vs HEAD, `git diff --name-only HEAD`

The pipe is the bound and belongs in the command. A read-time cap ("read only the first 20 entries")
bounds nothing: the Bash tool returns the command's complete output into context before there is
anything to decide about.

Treat a failure (not a repository, git unavailable) as an unknown value and carry on. Keep these as
separate body Bash calls rather than pre-compute lines: the harness runs a skill's whole pre-compute
block as one shell invocation, and a worktree-isolated session refuses a compound command that
contains git.

## Variables

Arguments: `$ARGUMENTS`

## Argument parsing

- **Scope** (optional): a path limiting which changed files are considered. Default: every changed
  file inside the configured `mutate` globs. Under `--exercised` it narrows the changed tests
  considered, and it goes before the flag.
- **`--exercised [<test-path>]`**: mutate the production code the changed tests call, judged
  against those tests as one set ([The exercised scope](#the-exercised-scope---exercised)). The
  scope runs only when this flag is passed. The token right after the flag is the test path when it
  does not start with `--`, so `--exercised --max 5` takes no test path. Mutually exclusive with
  `--full` and `--paths`: refuse the combination and name both flags.
- **`--full`**: mutate the whole configured scope instead of the diff. Expensive and rarely correct,
  state the estimated cost from `baseline-suite-ms` and confirm before running.
- **`--paths <globs>`**: mutate these paths regardless of the diff.
- **`--max <n>`**: cap generated mutants for this run, overriding `max-mutants`.
- **`--no-suppress`**: include mutants that the arid-node record would otherwise suppress, marked as
  suppressed. Read-only inspection of the suppression policy; it never edits the record.
- **`--persist-findings`**: after reporting, also write the survivors as a findings file the
  `review:fanout` `fix` action consumes ([Phase 6](#phase-6-persist-opt-in)). Off by default.
- **`--record-mutants <file>`**: with `--exercised`, write the mutants this run applied and their
  states to a record outside tracked space ([Record and replay](#record-and-replay)).
- **`--replay-mutants <file>`**: with `--exercised <test-path>` and `--record-mutants <after>`,
  apply exactly the recorded mutants and gate on lost kills ([Record and replay](#record-and-replay)).

### Effort, the mutant cap of last resort

Caller effort for this run is `${CLAUDE_EFFORT}`. If that still reads as a literal placeholder (a dollar sign and braces around
the variable name) rather than an effort level, this body was read directly instead of
skill-loaded, so the substitution never ran: treat the run as `high` and leave the cap to the config.

Effort supplies a **default cap only when nothing else sets one**. The precedence is `--max` first,
then the configured `max-mutants`, then this table; effort never lowers a cap the caller or the
config chose, and never raises one:

| Effort | Cap when neither `--max` nor `max-mutants` is set |
|---|---|
| `low` | 5 mutants |
| `medium` | 15 mutants |
| `high`, `xhigh`, `max` | uncapped, the current behavior |

An effort-derived cap is a cap like any other, so Phase 1 step 5 already governs how it is reported:
say what was dropped, because a truncated run must never read as a clean one. Nothing downstream
moves. Phase 4 triage still runs in fresh context on every surviving mutant, at every effort level.

## The exercised scope (`--exercised`)

The diff scope asks whether the suite checks the changed code. `--exercised` asks whether the
changed tests check the code they call. Each mutant runs against those tests only, so a strong
existing test cannot kill it and hide a weak new one, and the verdict is for the tests as one set:
a mutant is killed when any test in the set fails. Each paragraph below replaces the named step of
the diff scope for this run only.

**The test set.** The changed files are the committed range, `git diff --name-only
<diff-target>...HEAD`, plus the working tree, `git status --porcelain --untracked-files=all`
(tracked modified files and untracked files, each listed by path), so tests an agent has just
written count before they are committed. A scope path narrows them. With `--exercised <test-path>`
the files under that test file or folder replace the changed files, the mapping starts from them,
and every step below that reads "the test set" means the tests under that path. That is not the
scope path, which only narrows the changed files.

**Which files are tests.** For each candidate file, invoke `/testing:audit --file <path>` through
the Skill tool and read the `adapter:` line of its coverage block:

- `adapter: <id>`: a test, in the set.
- `adapter: none (no adapter claims this file)`: not a test.
- `adapter: none (<id> claims this file and is off in the testing config)`: not in the set. The
  report lists it as skipped with that reason, because the team turned that adapter off.

When the `testing` plugin is not installed, refuse: `--exercised` needs the `testing` plugin to
recognize test files. Never guess from file names. A set with no tests ends the run as `no changed
tests: scope empty`, a result, never a clean run.

**The mapping.** Read each test in the set and list the functions it calls directly that are defined
in files inside the `mutate` globs. The mapped-line set is the bodies of those functions. Only direct
calls from the test body count, not callees of callees, so a call through dependency injection, an
interface, HTTP or a test helper maps nothing. The scope report lists the mapped functions. Zero
functions ends the run as `no mapping: scope empty`, a result, never a clean run. The mapped-line
set is the scope `--exercised` resolves to, so a mode that takes `--paths` can take `--exercised`
or `--exercised <test-path>` instead and inherit these limits; `--record-mutants` records over it.

**Runner and regime.** Use the configured tool's own test restriction only where
[`context/tool-test-restriction.md`](context/tool-test-restriction.md) reads `yes` in its
no-coverage column, with that row's option and source cited in the scope report. Otherwise run the
manual protocol ([Phase 2](#phase-2-generate)) with the config's `test-command`, replacing the
`{tests}` word with the test paths, each wrapped in single quotes with every `'` inside it written
as `'\''`, so no character in a file name reaches the shell unquoted. No `test-command`, one where
`{tests}` is not a standalone unquoted word, or a runner that only filters by name: refuse, naming
`/mutation-testing:setup apply`. This is decided
in Phase 0 and never switched mid-run.

**Phase 0, in this order:** config; tool availability; the test set; which files are tests; the
mapping; runner and regime; the dirty-target stop, on the mapped files; the regime gate with its
refusal rule; one baseline run of the test set alone, which replaces the full-suite baseline (red
stops the run; its wall-clock is the cost base); then the Phase 0 snapshot. A red test outside the
set cannot kill these mutants, so it does not stop the run.

**Phase 1.** Steps 2 and 3 key on the mapped-line set instead of the changed lines, so an arid
record on a mapped node still applies. Step 4's selection is the test set, not every covering test.
The effort cap, `--max` and `max-mutants` apply unchanged, and the estimate is the restricted
baseline times the mutant count.

**Phase 3.** Each mutant runs against the whole test set. There is no rerun after the loop; the
flaky-test gotcha below states that limit.

**Phase 4.** The brief hands over the whole test set for every survivor, not only the tests that
reached it.

**Phase 5.** The report carries the scope line, coverage and gap labeled with the same tests, and
the blind-spot line ([`templates/report.md`](templates/report.md)). Coverage and gap come from the
tool's no-coverage state only where the restriction keeps it; under the manual protocol both print
`unknown` and files are listed in path order, never ranked on an assumed coverage. The blind spot
is the one stated in the `principles` skill's
[`theory.md`](../principles/reference/theory.md) "What a mutation score is evidence for": a test
that copies the production formula kills the same mutants as one that states a literal, so a clean
run does not clear a restated or copied expected value. That check belongs to the `testing`
plugin's task-end judge rule `testing/judge/rule-restated-expectation`.

## Record and replay

`--record-mutants <file>` writes the mutants an exercised run applied, with their states.
`--replay-mutants <before> --record-mutants <after>` applies exactly those mutants again after the
tests changed, writes their new states, and compares the two records with
`bash "${CLAUDE_PLUGIN_ROOT}/scripts/compare-records.sh" <before> <after>`: every mutant detected
before must still be detected. The report carries one `Gate: pass` or `Gate: block` line and one
`newly-surviving <path>:<line_start> <operator>` line per blocking mutant. Both runs use the manual
protocol with `test-command`, and a red baseline stops either one and names the failing tests.
Read [`context/mutant-record.md`](context/mutant-record.md) before either run: it owns the record
format, the refusals, and the replay's Phase 0.

## The contract this skill holds

Three properties, stated first because everything below depends on them:

1. **Read-only with respect to tracked source.** A mutant is applied, measured, and reverted.
   Restoration is verified against the Phase 0 snapshot at the earliest point the configured write
   regime permits, so a run **either** ends with tracked source byte-identical to tracked source at
   the start **or** ends in failure naming what it could not restore, never in a reported outcome
   over edited source. The first tracked path that cannot be confirmed restored is that failure: no
   later phase runs and nothing is persisted ([Phase 3](#phase-3-execute)). Per the
   naming doctrine's verb contract, `audit` reports and stops, and bare invocation does exactly
   that. `--persist-findings` is the explicit user override that verb contract sanctions
   (the marketplace's `docs/plugin-philosophy.md` verb table). Its writes, the findings file and
   the self-ignore guard's own `.gitignore` when a governing checkout was found and the guard heals
   that root, are each **proven outside tracked space before that write is made**, never in tracked
   source and never in a file another producer owns. `--record-mutants` is a second such override,
   on the same terms: its record is written outside tracked space, after restoration is verified.
2. **No tests are written here.** Survivors are handed to the test-authoring lane. This skill never
   both creates a gap and closes it.
3. **No verdict this skill produces is graded by the context that produced it.** See
   [Phase 4](#phase-4-triage-fresh-context).

## Phase 0: Preflight

Refuse to proceed, with the specific remediation, when any of these fail. Under `--exercised`, run
them in the order [The exercised scope](#the-exercised-scope---exercised) gives.

- **Config missing** → `/mutation-testing:setup apply`.
- **Tool unavailable** → `/mutation-testing:setup check` names the install line.
- **Working tree dirty in a file about to be mutated** → stop. A mutation harness reverts by
  restoring a known state; uncommitted edits in the target make "revert" ambiguous and risk
  discarding the user's work. Ask them to commit or stash first. This is a hard stop, not a warning.
- **Baseline suite red** → stop and report the failure. A red suite kills every mutant and reports a
  perfect score. Invoke `/testing:diagnose` via the Skill tool when the `testing` plugin is installed; otherwise diagnose
  with the project's own test command before returning here.

Record the baseline run's result and wall-clock. Every later "killed" verdict is meaningful only
against a green baseline captured in this run, not against the one `setup` recorded, which may be
stale.

**Capture `git status --porcelain` here.** This is *the Phase 0 snapshot* every later restoration
check compares against, and the rest of this skill refers to it by that name. It is taken before the
first mutant is applied and never re-taken. A snapshot refreshed mid-run would absorb the very
difference it exists to detect.

**Resolve the write regime here too**, because it decides which restoration gate
[Phase 3](#phase-3-execute) can run: does the configured tool write mutants out of tree, rewrite the
working file whole once, or apply and revert it per mutant? Read the project's own config and the
installed tool version for it. Two rows of the `principles` skill's
[`tooling.md`](../principles/reference/tooling.md) table can land in tree: StrykerJS under
`inPlace: true`, and mutmut at 2.x or below, where the installed major version *is* the regime. The
rest are constants. Resolve it from what this project actually configured, never from the tool's
reputation.
State the resolved regime in the scope report. Refuse when the regime is in-tree per mutant and the
tool offers neither per-mutant observability nor interrupt safety: the gate that regime requires
cannot be run, and a check that cannot run is not a check.

## Phase 1: Scope

Under `--exercised`, step 1 is the mapped-line set and steps 2 to 4 change as
[The exercised scope](#the-exercised-scope---exercised) states.

1. Resolve the changed lines: `git diff --unified=0 <diff-target>...HEAD` for the files inside the
   configured `mutate` globs, intersected with any `--paths` or scope argument.
2. Drop lines with no test coverage, if a coverage report is available, a mutant on an uncovered
   line reports "no coverage", which the coverage report already said more cheaply.
3. Apply the arid-node suppression record per
   [`context/suppression.md`](context/suppression.md), which owns this plugin's read of the
   finding-suppression contract. Grade every layer that exists before applying anything, with
   `bash "${CLAUDE_PLUGIN_ROOT}/scripts/suppression-lint.sh" <record> [<record> ...]`: it prints
   `ok <finding_id>` or one of `malformed`, `mismatch`, `unknown-kind` per entry with what failed,
   and exits 0 when every entry passes, 1 when any fails, and 2 when a record cannot be graded at
   all. **Only an entry the lint reports `ok` suppresses.** Every other one carries the lint's own
   line into Phase 5's did-not-apply section, which is where the malformed and stale-key entries
   become visible rather than silently stopping suppressing. Three more things that are easy to get
   wrong and are not optional: a **personal-layer entry the team layer does not carry does not
   suppress** (this surface inverts the cascade default), and is reported
   `personal-only, not applied`; matching is by derived `finding_id`, never by bare file:line; and a
   layer the lint cannot grade is reported unreadable and the read continues, never failing whole.
   Under `--no-suppress` nothing is dropped and every entry that would have applied is marked as
   such.

   Entries are dispositioned **only when their anchored node is one this run generated a mutant
   for**. Inside the changed-line set from step 1, after the coverage drop in step 2. Anything else
   is *not-examined*: left untouched and counted, never resolved. Scope by node, not by file: a file
   with a suppressed survivor at line 100 and an unrelated edit at line 10 was "touched" but that
   node was never examined, and treating it as a disappearance would fail the skill's own self-check
   on nearly every run.
4. **Select the covering tests once, and cache the selection.** Test selection is fixed overhead per
   *target*, not per *mutant*; re-deriving it for each mutant is the difference between a run that
   finishes and one that does not.
5. Report the scope before running: files, changed lines, mutants to be generated, suppressed count,
   and the estimated wall-clock from `baseline-suite-ms × mutants`. If a cap truncates the set, say
   what was dropped, a truncated run must never read as a clean one.

## Phase 2: Generate

**At most one mutant per changed line.** Not every operator at every location. The marginal value of
a second mutant on a line is near zero: if the line is unchecked, one mutant proves it.

Where the configured tool supports diff-scoped generation, use it. `--since`, `--incremental`,
`--git-diff-lines`. Where `tool: manual`, apply the single-operator protocol from the `principles`
skill's `tooling.md`: prefer statement/block removal, then relational-operator inversion.

## Phase 3: Execute

For each mutant: apply, run the cached covering tests, record the state
(killed / survived / no-coverage / timeout / invalid), revert. **Where the mutant was written to
tracked source, verify the revert**, which regime below says when that is.

**This phase is a deterministic gate and is deliberately not delegated.** The tests' pass/fail *is*
the verdict; there is no judgment to bias and no independence to buy. Spending a subagent here would
be delegation cost with nothing bought, the narrow exemption the fresh-eyes rule states for
mechanical judgments.

Read [context/restoration-regimes.md](context/restoration-regimes.md) before the first mutant is
applied, and again before reporting a restoration as verified: it owns the comparison against the
Phase 0 snapshot rather than a clean tree, the three regimes that decide when that comparison can
run, and what a failed restore does to the rest of the run. Phases 5 and 6 exist only for a run
whose restoration was verified here.

## Phase 4: Triage (fresh context)

Every surviving mutant is one of three things, and the difference is a judgment:

| Disposition | Meaning | Downstream |
|---|---|---|
| **Productive** | A genuine gap, the behavior is unchecked | Hand to the test-authoring lane |
| **Equivalent** | Semantically identical to the original; no test can kill it | **Not** a suppression, the check is wrong for that node |
| **Arid** | Killable, but killing it would not improve the suite | Propose a complete suppression entry. Its `claim` binding a node kind from the vocabulary, its `reason` naming the unasserted behavior. Without that, the verdict is *unclassified*, not arid |

**This judgment is delegated to a fresh-context (non-fork) subagent, mandatorily.** It is the
`self-grade` bias class: a context that generated the mutants and ran them is the weakest place to
decide whether its own findings are worth reporting, and a fork inherits that reasoning rather than
removing it. Hand over the artifact, the mutated line, its surrounding code, and the tests that
covered it, never the reasoning that produced the mutant. The brief says it is done when every
handed-over survivor has one of the three verdicts or is marked unclassified, and that it returns
early rather than guess when the handed-over code is not enough to decide.

**Every productive survivor also gets a cause**, assigned in the same brief, in both scopes, with a
quoted line as its evidence:

| Cause | Meaning | Evidence to quote |
|---|---|---|
| `no-assertion` | No assertion in the handed-over tests reaches the mutated value | The test's line range and the absence, or the only assertions present |
| `input-gap` | An independent oracle exists, but no input tells the mutant apart | The assertion line and the inputs it uses |
| `unclassified` | No quotable evidence, or the expected value comes from the code under test | What was missing, or the assertion line whose expected side calls the mutated code |

The brief's tie-breaks: a weak, inert or mock-only assertion on the mutated value is `no-assertion`;
a mutated line no handed-over test reaches is `input-gap`, because no input takes that branch; an
expected value that reaches the mutated function, directly or through a helper, is `unclassified`,
never `input-gap`, and names `testing/judge/rule-restated-expectation`, so the fix goes to the
oracle rather than to a new input; a cause without a quote is `unclassified`.

For the **equivalence** call specifically, prefer a cross-vendor advisor when one is installed and
set up (invoked per its own documentation), falling back to the same-vendor fresh-context subagent.
Equivalence is formally undecidable, so the risk is a correlated blind spot rather than a lapse of
attention, and that is the case the top rung of the ladder exists for.

**Every verdict that WITHHOLDS a survivor must cite evidence, and a verdict that cannot is reported
as *unclassified*.** Equivalent and arid are the two that withhold, so the rule binds both. Asserting
either from inspection alone is exactly where this technique manufactures false confidence:

- **Equivalent** requires the demonstration: what was run, what was identical, and under which inputs.
- **Arid** requires a complete proposed suppression entry, all five keys, id derived from them,
  whose `claim` is `arid(kind=<node-kind>)` and whose `reason` names the behavior the suite
  deliberately does not assert on. **This context runs the lint over the proposal the subagent
  returned**, piping it in so nothing is written:
  `printf '%s\n' '<the proposed entry under a suppressions: mapping>' | bash "${CLAUDE_PLUGIN_ROOT}/scripts/suppression-lint.sh" -`.
  The check stays here rather than going out with the judgment because it is mechanical, the same
  exemption [Phase 3](#phase-3-execute) states: there is no independence to buy from a derivation
  that has one answer. The verdict is arid only when the lint reports `ok`; `malformed`, `mismatch`,
  or `unknown-kind` makes it *unclassified*. The lint reads the kind vocabulary at run time from the `principles`
  skill's [`scaling-and-suppression.md`](../principles/reference/scaling-and-suppression.md) "The
  node-kind vocabulary", which owns the rule that **a survivor fitting no node kind is not arid**.
  "Killing this would not improve the suite" is a conclusion, not the evidence for one. Aridity is
  the easier label to reach for, because its bar is otherwise a judgment about value rather than
  about observable behavior, the node-kind membership test is what makes it checkable rather than
  rhetorical, and running it is what makes it checked.

**This bar lives here, at classification, rather than at persist time, so one survivor has ONE
disposition.** Phase 5 reports and Phase 6 persists from the same classification, so an operator
reading the report and then the findings file cannot be shown "arid" in one and "unclassified" in the
other. It also means the bar binds a bare run, not only `--persist-findings`, the human-facing
report is exactly where an unevidenced withholding claim does its damage.

## Phase 5: Report

Per file, ranked by **oracle gap**, not by score. The gap is defined once, in the `principles`
skill's [`${CLAUDE_PLUGIN_ROOT}/skills/principles/reference/metrics.md`](../principles/reference/metrics.md), and this skill does not restate it:

```text
oracle gap = mutation score − code coverage
```

A large **negative** gap is the bad direction. Exercised but not checked. So rank **ascending**,
most negative first. The top row is where the reader's belief about the suite is most wrong, which
is the only thing this metric is good for.

Write the report from [`templates/report.md`](templates/report.md). Read it at the start of Phase 5,
before assembling any section: it owns the heading order, the five result classes, what each row
must carry, and why the two suppression sections are obligations of the finding-suppression
contract rather than reporting garnish. Phase 6 persists whatever Phase 5 wrote, so a section
invented here is a section persisted.

Report the covered-code score as the headline and the plain mutation score beside it, the first
answers "are my tests weak", the second mixes that with "do I have tests at all".

Then stop, unless `--persist-findings` was passed. Remediation is delegated. This phase is reached
only by a run whose restoration Phase 3 verified; a failed restore ended it there.

## Phase 6: Persist (opt-in)

Runs **only** under `--persist-findings`, and only on a run whose restoration Phase 3 verified.
Without the flag this phase does not exist and Phase 5 is the end of the run; without a verified
restoration there is no Phase 5 either, because the run already ended in failure. The flag is not the
only gate, and treating it as one is the defect: it decides whether *conforming* findings are
persisted, never whether the tree they describe still exists.

**This gate reads Phase 3's verdict; it never re-derives one.** The comparison against the Phase 0
snapshot has already run by the time this phase is reachable, so a run that persists over a failed
restore is not missing a check. It is declining to read one it already holds.

The flag exists because the survivors this skill detects are real findings with
no route to a remediation surface: writing one conforming file is that route, and it needs no wiring
on the consuming side, the `review:fanout` `fix` action locates its input by frontmatter, never by
provenance.

The mechanics are owned by [`context/persist-findings.md`](context/persist-findings.md), which reads
the detector-findings producer contract for this plugin. Six things there are easy to get wrong and
are not optional: the destination is the contract's `<memory_dir>/reviews/<branch-slug>/`, never a hardcoded
path outside it;
**each** write this phase makes, the findings file and the self-ignore guard's `.gitignore` where a
governing checkout was found, is proven outside tracked space before **that** write is made, against
the checkout that governs the destination rather than the invoking worktree, with the guard's own
write proven before the guard heals rather than reported afterwards, and with **nothing written at
all** where a resolved root has no governing checkout, the guard's create-when-absent rule could
land on a tracked-but-deleted `.gitignore` with no check having been possible, and the findings file
on a tracked deletion it would modify rather than create
(a memory root inside tracked space leaves `git status`
identical either way and so cannot detect itself, while a root outside the worktree is a layout the
consumer supports and a worktree-anchored probe could only ever refuse); the Phase 4 **verdict
class** selects the contract rule and the rule decides `Tier`, never the finding's prose, with
`Confidence: low` never emitted; every cell describes a mutant this run
actually executed, never an illustrative one; a run that examined mutants writes even when it found
nothing, while a run that examined **none** writes nothing at all; and an existing path is never
overwritten.

Persisting does not trade away the property in "The contract this skill holds": this phase is
reachable only from a run whose restoration verified, and a destination that cannot be proven
outside tracked space is not written to at all.

**This producer's remediation is off-site**, the missing assertion belongs in the covering test, not
at the mutated node the row's `Location` names. Every emitted row names that target in `Action`, and
the consumer surfaces such a row to a human rather than auto-applying it. The spoke records why
`Location` is never retargeted and no column is invented.

## Remediation. Delegated

- **Write the killing tests**. `/testing:write` when the `testing` plugin is installed, handed the
  survivor list. Otherwise report the survivors and let the user author tests with their project's
  own conventions; do not author them here. An `input-gap` survivor can be closed by a property (a
  generator over the input class the mutant hides in) as well as by one more example; name both
  options in the hand-off and let the authoring lane choose.
- **Make a property's kill replay.** A randomized property can kill a mutant in one run and miss it
  in the next (a design inference, not a sourced finding: the flaky-test gotcha from the generator
  side). During mutation runs pin the seed or derandomize the tool, and pin the killing
  counterexample as an explicit example so the kill replays whatever the generator draws.
  Pointer: Hypothesis `derandomize` in <https://hypothesis.readthedocs.io/en/latest/reference/api.html>;
  fast-check seed and `examples` in <https://fast-check.dev/docs/configuration/user-definable-values/>.
  As of 2026-10-06; recheck when either tool's major release redefines those settings.
- **Verify the new test actually kills the mutant**. Re-run this skill scoped to that file. This is
  the property that makes the loop trustworthy: the agent that wrote the test cannot grade itself
  into a pass, because the harness re-runs the mutant. A test that does not turn the mutant red has
  not closed the gap, however plausible it reads.
- **Record accepted arid mutants**. Append to `.claude/mutation-testing-arid.md` per
  [`context/suppression.md`](context/suppression.md). A complete entry carries all five required keys
  (`check`, `claim`, `sites`, `reason`, `date`) with the `finding_id` derived from the constituents,
  never hand-written: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/suppression-lint.sh" <record>` over the
  record the user accepted reports the derived id for any entry whose key is wrong. The user accepts each entry; this skill proposes and never writes suppressions
  unprompted, and writes only the **team** layer, a personal-layer entry would not suppress anything.
  An **equivalent** mutant is never recorded here; the convention's record is not for a finding that
  is simply wrong.

## Next

- Survivors remain and the killing tests are due: `/testing:write`.
- A survivor is about to be called arid or equivalent: `/mutation-testing:principles`.
- A clean exercised run: /testing:test-value.

## Gotchas

Failure modes documented from the literature and from measurement, not anticipated in the abstract.
Each one produces a *plausible* result, which is what makes them worth listing.

- **A red baseline reports a perfect score.** Every mutant is "killed" by a test that was already
  failing. This is the most dangerous failure mode because the number looks excellent. Phase 0 stops
  on it; never skip that probe to save a suite run.
- **Flaky tests inflate the score by an unknown margin.** A flaky failure kills a mutant by accident.
  There is no correction factor. Either fix the flakes or report the score with the caveat attached.
- **A timeout counts as detected, and that is correct**, an infinite loop *is* a detected behavior
  change. But a score leaning heavily on timeouts is being carried by wall-clock rather than
  assertions; report the timeout share when it is large.
- **"No coverage" is not a weak test, it is an absent one.** Keeping it out of the headline number
  is the entire reason the covered-code score is the one reported.
- **A partially-completed run must report as partial.** Mutants that never ran are named as not-run,
  never counted as killed, never silently omitted. The same rule applies to a mutant set truncated
  by a cap. **A run cut short by a failed restore is not this case**. It reports failure, not a
  partial result ([Phase 3](#phase-3-execute)). A partial report describes a tree that is intact;
  that one is not.
- **Reaching for a withholding label is the standard way this technique manufactures false
  confidence.** "Equivalent" is the convenient explanation for any survivor whose test is hard to
  write. [Phase 4](#phase-4-triage-fresh-context) holds the bar for both withholding labels; do not
  soften it when a survivor is inconvenient.
- **A persisted findings file written to the wrong directory fails silently.** Nothing reports the
  miss: the run says it persisted, the file exists, and the consumer never scans that path. It is the
  failure mode of hardcoding `.work` on a repo that declares its own memory root, which is why
  Phase 6 composes the home from the memory root.
- **A high mutation score is not a correctness argument.** The coupling effect covers faults composed
  of local errors. It says nothing about a wrong algorithm, a missing requirement, a concurrency
  interleaving, or an unexpressed security property.

## What this skill does NOT do

- Write or modify tests, or leave any mutation in the tree.
- Persist anything on bare invocation. The findings file is written only under `--persist-findings`,
  and only into a memory tier proven to sit outside tracked space; a mutant record only under
  `--record-mutants`, outside tracked space too.
- Apply its own findings, or read the consumer's consumption ledger. It writes one file and stops;
  what happens to that file belongs to the `fix` action.
- Write suppressions without the user accepting them.
- Fail a build on a score. There is no threshold to configure; see the `principles` skill's
  `scaling-and-suppression.md`.
- Answer test-design questions. Those belong to `/tdd:principles` when installed; otherwise use the
  project's own test-design guidance.
