# Design threads: tautological-tests-mutation-scope (Release 2b)

Scope: Release 2b of `docs/specs/tautological-tests.md`. Brief Q11: "`mutation-testing:audit` gains
a scope that mutates the production code the changed tests exercise. Its survivor report classifies
why each mutant lived: no assertion, expected value taken from the code under test, or an input
gap." The Brief (Q1-Q13) and amendments A1-A14 are the contract and are not reopened here. The user
split this scope off Release 2 on 2026-09-29 (`docs/topics/tautological-tests-judge/PLAN.md:15` on
that plan's branch).

Form: light (one module, one skill). Unattended run on 2026-09-30: no one answered questions, so
each thread records the recommended answer as taken. Every answer is open to the user at plan
approval, which is still pending.

Evidence read this session:

- `plugins/mutation-testing/skills/audit/SKILL.md` (Phases 0-6), `templates/report.md`,
  `context/persist-findings.md`, `skills/setup/templates/config-template.md`,
  `skills/audit/evals/evals.json` (14 prose-graded cases).
- `plugins/testing/skills/audit/scripts/cant-fail-scan.sh` header (rule ids, `--file`/`--lines`).
- `.work/tautological-tests/mutation/RESEARCH.md`, `RESEARCH-gaps.md`, `RESEARCH-tools.md`
  (verified MEDIUM, single publisher pool per tool).
- `.work/tautological-tests-verify/mutation/taut.py`, re-run this session:

  ```text
  calls-SUT f(100)==f(100): killed 0/3
  relation f(200)==2*f(100): killed 1/3
  copied logic f(100)==100+100*0.2: killed 3/3
  literal f(100)==120: killed 3/3
  ```

- `https://code.claude.com/docs/en/hooks.md`, fetched 2026-09-30, the `bashEditDiff` section.

## Threads

| ID | Thread | Status |
|---|---|---|
| DT1 | Which tests run against each mutant | resolved |
| DT2 | How changed test files are recognized | directional (Q6 scope is a user question) |
| DT3 | Mapping changed tests to the production code they exercise | resolved |
| DT4 | Trigger: flag, auto-engage, mixed diffs, cost | resolved |
| DT5 | Survivor cause classification (Q11) | resolved |
| DT6 | The copied-logic blind spot | resolved |
| DT7 | Metrics under the new scope | resolved |
| DT8 | Tool support for running a named test set | directional |
| DT9 | Test seam | resolved |
| DT10 | PostToolUse `bashEditDiff` | deferred |
| DT11 | What stays out of 2b | resolved |
| DT12 | The kill unit: the changed-test set, per mutant | resolved |
| DT13 | Reachability: telling an unreached mutant from a survivor | resolved |
| DT14 | The test command for the manual fallback | resolved |
| DT15 | Preflight order under the exercised scope | resolved |
| DT16 | The findings tier rationale outside the diff | resolved |

Stress-test revision (2026-09-30): the plan-reviewer and `/planning:devils-advocate` passes found
that the first draft of DT1, DT3, DT4, DT5 and DT7 rested on assumptions the skill does not meet.
DT12-DT16 were added and the changed threads are restated below as old, new and why.

### DT1: Which tests run against each mutant

Options:

- A. Every test covering the mutated line, as Phase 1 step 4 does today (SKILL.md:149-151).
- B. Only the changed tests.

Recommended answer taken unattended (2026-09-30): B. Under the new scope each mutant runs against
the changed tests only. Under A, an existing strong test kills the mutant and hides the weak new
test, which is the one being judged. This is a deliberate divergence from Phase 1 step 4 for this
scope only; the diff scope keeps A. A survivor under B means "the changed tests do not check this",
not "nothing in the suite checks this", and the report says so in its scope line.

Basis: SKILL.md:149-151 (selection covers every covering test); Q11 (the scope exists to judge the
changed tests); `taut.py` output above (the calls-SUT oracle lets 0/3 mutants die, so a strong
neighbor test is the only thing that would kill them).

The changed tests are the committed range plus the working tree: tracked modified and untracked
files matching `tests` (DT2). An agent's freshly written tests are usually uncommitted, and
`git diff <diff-target>...HEAD` (SKILL.md:123) sees only commits. Revised 2026-09-30 after the
devils-advocate pass (old: committed diff only; new: committed plus working tree; why: the main use
case writes tests without committing).

### DT2: How changed test files are recognized

Options:

- A. Files in the diff outside the `mutate` globs.
- B. Read the `testing` plugin's adapter globs.
- C. A new `tests` key in `.claude/mutation-testing.md`: framework filename-convention globs,
  written by `setup apply`.

Recommended answer taken unattended (2026-09-30): C. A is wrong: `mutate` excludes tests by
instruction, but docs, config and fixtures also sit outside it. B couples an installed plugin to
another plugin's private files, which it cannot reach reliably. C keeps `mutation-testing`
installable alone. Q6 binds the key: filename conventions only (`**/*.test.ts`, `**/test_*.py`,
`**/*Tests.cs`), never a bare `test/` or `tests/` folder glob. `setup apply` proposes defaults per
detected ecosystem; `setup check` reports a bare-folder glob as a failure. A config without the key
makes the new scope refuse with the remediation `/mutation-testing:setup apply`; the diff scope is
unaffected. The key's defaults can drift from the `testing` adapters' `files:` globs; the plan
records that as a known risk rather than wiring the two together.

Open for the user (plan reviewer, 2026-09-30): Q6 says "There is one pattern list shared with
`testing:audit`" (spec:74-75). Read inside Q6's hook context, that sentence governs the `testing`
plugin's hooks and audit, and a `mutation-testing` key does not breach it. Read broadly, C creates a
second list. This plan does not reopen the contract, so the reading is the user's call. Options: C
as recommended; or C with a rule that `setup apply` copies the globs from `.claude/testing.yaml`
when that consumer file exists (a tracked consumer file, not plugin internals); or a Q6 amendment
naming `mutation-testing` as a consumer of the one list. Research tag: `q6-scope`, settled by the
user's reading of Q6 at plan approval.

Basis: config-template.md:30-35 (`mutate` excludes test code); Q6 (spec:72-80); Q1 (spec:43, no
new plugin, extend in place); SKILL.md:97 and :306 (cross-plugin use only through Skill invocation
"when installed").

### DT3: Mapping changed tests to the production code they exercise

Options:

- A. Per-test coverage from a coverage tool.
- B. Static resolution by the audit context: read each changed test, list the calls into code under
  the `mutate` globs, and scope to the bodies of those functions.
- C. Import-graph resolution: mutate whole imported files.

Recommended answer taken unattended (2026-09-30): B. A needs a per-ecosystem coverage command the
config does not hold today. C over-scopes to whole files and multiplies mutants. B is universal and
cheap. It follows direct calls from the test body only, not callees of callees; indirection (DI,
interfaces, HTTP-level tests, helpers) can map to nothing. One mutant per line and the cap rules stay
as they are (SKILL.md:152-159). The scope report lists the resolved functions so the reader can see
the mapping. Zero resolved functions ends the run as `no mapping: scope empty`, named as a result,
never reported as a clean run.

Revised 2026-09-30 after the devils-advocate pass. Old: "a wrong mapping cannot produce a false
survivor; an unreached mutant records `no-coverage`". New: DT13 decides reachability. Why: under the
manual protocol an unreached mutant passes the tests and reads as survived, because no-coverage is
known only from a coverage report (SKILL.md:125-126).

Basis: SKILL.md:123-126; SKILL.md:158-159 (one mutant per line); config-template.md:13-66 (no
coverage command key).

### DT4: Trigger: flag, auto-engage, mixed diffs

Recommended answer taken unattended (2026-09-30):

- New flag `--exercised` selects the scope explicitly.
- A diff that changes at least one file matching `tests` and no line inside the `mutate` globs
  engages the scope automatically. That diff produces zero mutants today, so no existing run
  changes; the scope report names the auto-engagement.
- A mixed diff without the flag runs the diff scope as today, and the scope report names
  `--exercised` and the count of changed tests it did not examine. With the flag, the exercised
  scope replaces the diff scope for that run.
- `--exercised` is mutually exclusive with `--full` and `--paths`; a scope path argument narrows the
  changed tests considered.
- The effort cap, `--max` and `max-mutants` apply unchanged (SKILL.md:46-64). An auto-engaged run
  with none of them set takes the `medium` cap (15 mutants), because auto-engagement turns a no-op
  into a real run nobody asked for; the scope report states the cap. The cost estimate uses the
  restricted changed-test baseline (DT15), not `baseline-suite-ms`.
- Revised 2026-09-30 after the devils-advocate pass (old: no cap on auto-engage, estimate from the
  full-suite time; new: medium cap and restricted baseline; why: the skill is model-invocable, and
  under the manual protocol each mutant is several tool turns).

Basis: RESEARCH-gaps.md "Missing for the tautology role" item 3 (a test-only diff gets no mutation
signal; cargo-mutants documents the same limit, `https://mutants.rs/in-diff.html`); SKILL.md:123
(scope keyed on `mutate` globs).

### DT5: Survivor cause classification (Q11)

The Phase 4 dispositions (productive, equivalent, arid, unclassified) stay. A productive survivor
under any scope gains one cause:

| Cause | Meaning | Evidence the triage must quote |
|---|---|---|
| `no-assertion` | No assertion in the covering tests reaches the mutated value | The test's line range and the absence, or the only assertions present (weak, mock-only, inert) |
| `expected-from-sut` | The expected value is computed by calling the code under test | The assertion line whose expected side calls the mutated code |
| `input-gap` | An independent oracle exists, but no input distinguishes the mutant | The assertion line and the inputs used |
| `unclassified` | The triage could not quote evidence for a cause | What was missing |

Recommended answer taken unattended (2026-09-30): the same fresh-context triage that assigns the
disposition assigns the cause, in the same brief, with quoted evidence; a cause without a quote is
`unclassified`. No new rule id and no new findings column: the cause leads the persisted `Finding`
text and selects the `Action` wording (add an assertion; replace the expected value with a spec
literal; add an input case). The human report's Survivors table gains a `Cause` column. The
`testing` scanner is not called; a `testing:audit` finding the caller already holds may be passed as
evidence.

Tie-break rules in the triage brief (added 2026-09-30 after the devils-advocate pass, because the
cause boundaries are soft):

- A weak, inert or mock-only assertion on the mutated value counts as `no-assertion`.
- An expected value that reaches the mutated function, directly or through a helper, counts as
  `expected-from-sut`.
- A cause is assigned only to a survivor whose mutant is reached (DT13); a survivor with
  reachability `unknown` gets the cause only after the triage shows, by quoting the call path from a
  changed test, that the line runs.

Rejected: calling `cant-fail-scan.sh --file --lines` from `mutation-testing` (cross-plugin script
path, DT2); a separate cause rule id (persist-findings.md:248-260 keys the rule on the disposition
alone).

Basis: SKILL.md:184-198 (fresh-context triage, evidence bar); persist-findings.md:219-245 (Finding
and Action text, "never invent a column"); Q11 (spec:98-100); `taut.py` (calls-SUT oracle survives 3/3,
the `expected-from-sut` case).

### DT6: The copied-logic blind spot

Recommended answer taken unattended (2026-09-30): every exercised-scope report prints one fixed
line: a killed mutant does not clear a copied-logic oracle, because a test that copies the
production formula kills the same mutants as a spec literal. It points to `/testing:test-value` for
a provenance review. The principles skill states the limit once; the audit body cites it.

Basis: `taut.py` output (copied logic 3/3, literal 3/3); RESEARCH.md "What mutation detects"
(2608.17214: mutation cannot certify oracle independence).

### DT7: Metrics under the new scope

Recommended answer taken unattended (2026-09-30): coverage in the oracle gap is the changed tests'
line coverage over the scoped lines: scoped lines whose mutant DT13 marked reached, over scoped
lines. The ranking at SKILL.md:234-243 stays meaningful because both terms describe the same tests.
The report labels the numbers "changed tests only". Where DT13 cannot establish reachability (no
sentinel run and no restricted coverage), coverage and gap print as `unknown` and files are listed
in path order; the report never computes a gap from an assumed 100%.

Revised 2026-09-30 after the devils-advocate pass (old: coverage from mutants not `no-coverage`;
new: from DT13 reachability, else `unknown`; why: under the manual protocol nothing records
`no-coverage`, so the old term was always 100%).

Basis: SKILL.md:234-243 (gap = mutation score minus coverage, ranked ascending); DT1, DT13.

### DT8: Tool support for running a named test set

Direction: the configured tool runs each mutant against the changed tests only (DT1). Where the
tool cannot be restricted to a named test set, the scope runs under the `manual` single-operator
protocol with the project's own test command filtered to the changed files, and the scope report
says so. Whether each tool can be restricted, and at which granularity (file or test case), is not
settled: RESEARCH-tools.md:39 says Stryker.NET's `since` marks the mutants a changed test covers,
which narrows mutants, not the tests that run.

Research tag: `tool-test-restriction`. For stryker-js, stryker-net, stryker4s, pitest, infection
and mutmut, fetch the current docs and record the option (if any) that restricts a run to named
test files or cases, with URL and date, and how that option interacts with the tool's own
coverage or dry-run phase (a restriction that breaks the tool's no-coverage state makes the tool
manual-only under this scope). Settled in plan Phase 1; an unverified tool uses the manual fallback,
resolved in Phase 0 (DT15), never switched to mid-run.

### DT9: Test seam

The audit is skill prose plus one script (`scripts/suppression-lint.sh`). Existing seams: the
prose-graded `skills/audit/evals/evals.json` (14 cases) and `*.test.sh` files run by
`scripts/run-plugin-tests.sh`.

Recommended answer taken unattended (2026-09-30): one fixture project with one scenario per
expected outcome, and the existing evals seam. The kill unit is the changed-test set (DT12), so each
scenario changes only its own test file; six tests changed together would let the literal test kill
every mutant and hide the rest.

- One `app.py` (`tool: manual`) with `price_with_tax` spread over several lines, so the manual
  protocol's one-mutant-per-line operators (statement removal, then relational inversion;
  SKILL.md:158-163) produce more than one mutant, plus a discount branch above a threshold.
- Scenarios, one test file each: calls-SUT oracle (`expected-from-sut`), relation oracle
  (survivors expected `input-gap`), copied-logic oracle (no survivor; the blind-spot line), literal
  oracle (no survivor), assertion-free test (`no-assertion`), and a literal test that never reaches
  the discount branch (its mutants are unreached; DT13 must not label them survivors).
- `EXPECTED.md` lists, per scenario, the exact mutants the manual protocol generates and the state
  and cause each must get. The Tier 0 3-mutant matrix is not reproduced literally; only its
  qualitative outcomes are (calls-SUT kills none, copied logic and literal kill all).
- `exercised-fixture.test.sh` applies exactly the mutants `EXPECTED.md` lists, runs each scenario's
  test file with Python (standard library only), and asserts the state per mutant, so the fixture
  cannot drift from what the evals grade. It resolves `python3`, then `python`; it skips when
  neither exists, and fails instead when `CI` is set.
- New eval cases per scenario, one with uncommitted tests (DT1), one unmappable test (DT3), and
  one setup case (a bare `tests/` glob fails `setup check`).

Revised 2026-09-30 after both stress-test passes (old: six tests changed together, the 3-mutant
Tier 0 matrix; new: one scenario per outcome, mutants the skill actually generates; why: under
DT12 the strong tests would kill every mutant, and the skill never generates the Tier 0 mutants).

Basis: `evals.json` (dict with `evals`, 14 cases); `scripts/run-plugin-tests.sh:2` (runs
`plugins/**/*.test.sh`); `taut.py` (qualitative outcomes); SKILL.md:158-163;
`plugins/code-metrics/scripts/dispatch.test.sh:18` (python3-or-python precedent, per the plan
reviewer).

### DT10: PostToolUse `bashEditDiff`

Status: deferred out of 2b.

The audit reads `git diff` (SKILL.md:123), which already sees files a Bash command wrote, so the
field adds nothing to this scope. The docs call the list "best effort and in public beta" and say
to "use the list to find what to review, not to enforce a policy"; it is recorded in every mode
only with `bashEditDiffEnabled`, otherwise only in auto and `bypassPermissions` mode. Its natural
consumer is the advisory `testing` test-scan hook, which misses Bash writes today (spec risk table,
"Bash and MCP writes bypass the hooks", spec:910). The Release 2 judge plan also deferred it, so no plan owns
it now.

Research tag: `bashEditDiff-coverage`. Measure, on the installed Claude Code version, how many
Bash-written test files reach a PostToolUse hook under the default permission mode with and without
`bashEditDiffEnabled`; owner is a `testing` hooks follow-up, to be named by the user.

Basis: `https://code.claude.com/docs/en/hooks.md` (fetched 2026-09-30, `bashEditDiff` section,
requires v2.1.269 or later); SKILL.md:123.

### DT11: What stays out of 2b

Recommended answer taken unattended (2026-09-30): out, each already recorded elsewhere:

- `tooling.md` refresh and Rust/Go rows (spec:158-159, "Separate maintenance").
- ACH-style LLM semantic mutants (RESEARCH.md open decision 4, no open-tool primary).
- Extreme-mutation mode for pseudo-tested code (A12, candidate, not filed).
- Any score gate (config-template.md "Deliberately absent").

Basis: the cited lines.

### DT12: The kill unit: the changed-test set, per mutant

Found by both stress-test passes (CRITICAL). A mutant is killed when any changed test fails, so one
strong changed test hides a weak sibling changed test.

Options:

- A. Per mutant, against the changed-test set as one unit.
- B. Per mutant per changed test: attribute each kill to each test, multiplying runs by the number of
  changed tests.

Recommended answer taken unattended (2026-09-30): A. Q11 asks "why each mutant lived", which is a
per-mutant question; B changes the cost model by the number of changed tests. A weak test beside a
strong one is the `testing:audit` scanner's and the Release 2 judge's concern, not mutation's. The
report's scope line says the verdict is for the changed tests as a set. Switch condition for B: the
user wants per-test verdicts and accepts runs multiplied by the changed-test count.

Basis: SKILL.md:167 (one state per mutant against the cached covering tests); Q11 (spec:98-100).

### DT13: Reachability: telling an unreached mutant from a survivor

Found by the devils-advocate pass (HIGH). Under the manual protocol a mutant on a line the changed
tests never run passes those tests and would read as survived.

Recommended answer taken unattended (2026-09-30): every survivor gets one sentinel run before triage.
The mutated line is replaced by a statement that raises (Python `raise`, JS `throw`, C# `throw`, Go
`panic`), under the same per-mutant apply-and-restore gate. The changed tests failing means the
line is reached, so the mutant is a survivor. The tests passing means the line is unreached (or the
exception is swallowed), so the mutant is reported `unreached`: a mapping miss, never a survivor and
never given a cause. A tool whose restricted run keeps its own no-coverage state (Phase 1 column,
DT8) skips the sentinel. Cost: one extra run per survivor, not per mutant.

The sentinel is a reachability probe only. It is not the extreme-mutation mode A12 names as a
candidate (that mode would report pseudo-tested methods as findings); no sentinel result becomes a
finding.

Basis: SKILL.md:125-126 (no-coverage only when a coverage report exists); restoration-regimes.md:35-43
(in-tree per-mutant gate); A12 (spec:977).

### DT14: The test command for the manual fallback

Found by the devils-advocate pass (HIGH). The config's `command` invokes the mutation tool
(config-template.md:18-22); nothing holds the project's test command or its per-file filter.

Recommended answer taken unattended (2026-09-30): a new optional key `test-command`, a command with
a `{tests}` placeholder that the audit fills with the changed test paths (for example
`python -m pytest {tests}`, `npx vitest run {tests}`, `dotnet test --filter {tests}` with the
filter form Phase 1 records). `setup apply` proposes it per ecosystem. The exercised scope under the
manual protocol refuses without it, naming `/mutation-testing:setup apply`.

Basis: config-template.md:18-22; SKILL.md:161-163 (manual protocol).

### DT15: Preflight order under the exercised scope

Found by the devils-advocate pass (HIGH and MEDIUM). Phase 0 resolves the write regime and the
dirty-target stop before Phase 1 knows which files the exercised scope will mutate, and its
baseline runs the whole suite.

Recommended answer taken unattended (2026-09-30): under the exercised scope, Phase 0 also resolves
the changed tests (DT1), the mapping (DT3) and the effective runner (tool with a verified restriction,
else manual, DT8) before the first mutant. The dirty-target stop and the regime gate, including the
refusal rule, apply to the mapped files and the effective regime. Phase 0 also runs the changed-test
set alone twice: red stops the run, and two different results stop it as flaky, because a flaky
changed test kills mutants by accident and hides the weakness being judged. Its wall-clock is the
cost-estimate base (DT4).

Basis: SKILL.md:93-119 (Phase 0 stops and regime); SKILL.md:335-336 (flaky tests inflate the score).

### DT16: The findings tier rationale outside the diff

Found by the plan-reviewer (CRITICAL). The detector-findings contract argues IMPORTANT for
`rule-survivor-productive` from "this producer is diff-scoped, so the mutated node is inside the
change under review" (`docs/conventions/detector-findings/README.md:234`). Under the exercised
scope the mutated node is outside the change; the change is the tests.

Recommended answer taken unattended (2026-09-30): keep the rule ids and the IMPORTANT tier, and
amend the row's rationale to cover both scopes: under the exercised scope IMPORTANT's
degradation-with-a-named-trigger limb matches, as it does for `testing/audit/rule-zero-assertion`
(the changed test is a coverage claim nothing backs; the trigger is the first regression in the
mapped behavior shipping green). The tier and every consumer's reading of it stay the same
(`plugins/review/skills/audit-enforceability/context/crosswalk.md:38-41` keys on the rule id). The
amendment is a convention edit with its own CHANGELOG entry and a consumer check first.

Basis: `docs/conventions/detector-findings/README.md:234` and the `rule-zero-assertion` row below
it; crosswalk.md:38-41.

## Dependency order

DT2 and DT14 before DT4 and DT15 (the trigger and preflight need the `tests` and `test-command`
keys). DT8 (plan Phase 1 probe) before DT15's effective-runner choice. DT12 fixes the fixture shape
in DT9. DT13 before DT5 and DT7 (cause and coverage need reachability). DT16 before any persisted
exercised-scope row ships. DT10 has no dependency inside 2b.
