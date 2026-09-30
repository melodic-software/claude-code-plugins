# Design threads: tautological-tests-mutation-scope (Release 2b)

Scope: Release 2b of `docs/specs/tautological-tests.md`. Brief Q11: "`mutation-testing:audit` gains
a scope that mutates the production code the changed tests exercise. Its survivor report classifies
why each mutant lived: no assertion, expected value taken from the code under test, or an input
gap." The Brief (Q1-Q13) and amendments A1-A14 are the contract and are not reopened here. The user
split this scope off Release 2 on 2026-09-29 (`docs/topics/tautological-tests-judge/PLAN.md:15` on
that plan's branch).

Form: light (one module, one skill). Unattended run on 2026-09-30: no one answered questions, so
each thread records the recommended answer as taken. Every answer is open to the user at plan
approval, which is still pending. The user decided DT2, DT3, DT4, DT8, DT9, DT10, DT14, DT15 and
DT16 on 2026-09-30; each such line starts "Decided 2026-09-30 (user)". DT13 and DT14's character
allowlist wait on the user.

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
| DT2 | How changed test files are recognized | directional (source decided by the user; base-glob source is tag `testing-glob-source`) |
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
| DT14 | The test command for the manual fallback | resolved (character allowlist pending the user) |
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
files the testing config counts as tests (DT2). An agent's freshly written tests are usually uncommitted, and
`git diff <diff-target>...HEAD` (SKILL.md:123) sees only commits. Revised 2026-09-30 after the
devils-advocate pass (old: committed diff only; new: committed plus working tree; why: the main use
case writes tests without committing).

### DT2: How changed test files are recognized

Options:

- A. Files in the diff outside the `mutate` globs.
- B. The testing config the `testing` scanner reads.
- C. A new `tests` key in `.claude/mutation-testing.md`.

Decided 2026-09-30 (user): B. No new `tests` key in `.claude/mutation-testing.md`.
`mutation-testing` reads test-file patterns from the same testing config the `testing` scanner reads:
today `.claude/testing.yaml`, resolved through its cascade (`~/.claude/testing.yaml`, the team file,
`.claude/testing.local.yaml`), and wherever issue #5606 later moves it (a docs convention file with a
CLAUDE.md pointer as the default, `.claude/` as an option). Plans add no new `.claude/*` config
file. This replaces the unattended answer C, which made a second pattern list beside Q6's "one
pattern list shared with `testing:audit`" (spec:74-75). A stays rejected: docs, config and fixtures
also sit outside `mutate`.

Open for the user (found while applying the decision, 2026-09-30): the testing config holds only
overrides (`paths.include`, `paths.exclude`, `extend.<adapter>.files`, `adapters.disable`). The base
filename globs are the `files:` fields of the `testing` plugin's shipped adapters, and with no layer
file "the shipped adapters, globs and rule levels apply" (`plugins/testing/skills/setup/scripts/setup.sh:148`).
A repository without a layer file, the common case, gives `mutation-testing` no list to read.
Options:

- a. When `testing` is installed, ask it: the audit invokes `/testing:audit` through the Skill tool
  on the changed files and counts a file as a test when an adapter claims it (the `--file` coverage
  block prints `adapter: <id>` or `adapter: none`, `cant-fail-scan.sh:962-967`). Without `testing`
  installed, the exercised scope refuses and names it. One list, resolved by its owner.
- b. Wait for #5606: its convention file carries the full pattern list, not only overrides, and
  `mutation-testing` reads that; until then the exercised scope refuses.
- c. Read the config layers directly and count only `paths.include` and `extend.*.files` globs as
  test patterns; refuse when none are set.

Recommendation: a, the only option that sees the list the scanner uses today and adds no config.
Research tag: `testing-glob-source`, open, to be settled by the user. Unblocks DT1's changed-test set, DT4's
trigger and plan Phase 3.

Basis: config-template.md:30-35 (`mutate` excludes test code); Q6 (spec:72-80); Q1 (spec:43, no
new plugin, extend in place); SKILL.md:97 and :306 (cross-plugin use only through Skill invocation
"when installed"); `plugins/testing/skills/audit/scripts/cant-fail-scan.sh:124-130, :312-322`
(cascade layers); issue #5606 (config location).

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

Decided 2026-09-30 (user, overengineering review): this static mapping owns "which production
files the changed tests exercise". It is exposed as a scope a caller can pass on, so Release 3
(#5604) can hand it to its recording run (`--record-mutants`, which today takes `--paths`) instead
of building its own `--paths` list. Interaction: a Release 3 recording run that takes this scope
inherits its limits (direct calls only, `no mapping: scope empty` on zero functions), and the
mapping stays defined here, not in Release 3.

Basis: SKILL.md:123-126; SKILL.md:158-159 (one mutant per line); config-template.md:13-66 (no
coverage command key); issue #5604 body ("`--record-mutants` (every line in `--paths` ...)").

### DT4: Trigger: flag, auto-engage, mixed diffs

Recommended answer taken unattended (2026-09-30):

- New flag `--exercised` selects the scope explicitly.
- A change set that touches at least one test file (DT2) and no line inside the `mutate`
  globs engages the scope automatically. The change set is the committed range plus the working
  tree, the same set DT1 uses (review 2, 2026-09-30: the trigger read the committed diff only, so
  uncommitted tests never auto-engaged). That change set produces zero mutants today, so no
  existing run changes; the scope report names the auto-engagement.
- A mixed diff without the flag runs the diff scope as today, and the scope report prints one line
  naming `--exercised`. With the flag, the exercised scope replaces the diff scope for that run.
- `--exercised` is mutually exclusive with `--full` and `--paths`; a scope path argument narrows the
  changed tests considered.
- The effort cap, `--max` and `max-mutants` apply unchanged (SKILL.md:46-64), auto-engaged or not;
  the scope report states the cap. The cost estimate uses the restricted changed-test baseline
  (DT15), not `baseline-suite-ms`.
- Revised 2026-09-30 after the devils-advocate pass (old: no cap on auto-engage, estimate from the
  full-suite time; new: medium cap and restricted baseline; why: the skill is model-invocable, and
  under the manual protocol each mutant is several tool turns).
- Decided 2026-09-30 (user, overengineering review): the auto-engage cap is the existing effort
  cap, unchanged (old: the smaller of the effort cap and 15); the mixed-diff hint drops the count of
  unexamined tests and keeps one line naming `--exercised`.

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

Decided 2026-09-30 (user, overengineering review): the probe covers stryker-js, stryker-net and
mutmut only. stryker4s, pitest and infection are deferred and run under the manual fallback;
switch condition: a fleet repo adopts Scala, Java or PHP.

Research tag: `tool-test-restriction`. For stryker-js, stryker-net and mutmut, fetch the current docs and record the option (if any) that restricts a run to named
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
- Scenarios, one test file each, directory names in snake case so `python -m unittest <path>`
  imports them: `calls_sut` (`expected-from-sut`); `relation`, whose expected side calls the code
  under test (`expected-from-sut` under DT5's tie-break); `boundary`, a literal oracle at an input
  far above the discount threshold, so the relational-inversion mutant on the threshold line is
  reached and survives (`input-gap`); `copied_logic` (no survivor; the blind-spot line); `literal`
  (no survivor); `no_assertion` (`no-assertion`); and `unreached_branch`, a literal test that never
  reaches the discount branch (its mutants are `unreached`; DT13 must not label them survivors).
  At least one listed mutant sits on a continuation or header line, to exercise DT13's
  insert-before rule.
- Review 2, 2026-09-30: the relation oracle `f(200)==2*f(100)` calls the code under test on its
  expected side, so DT5's own tie-break makes it `expected-from-sut`, not `input-gap`; `boundary`
  now carries `input-gap`.
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

Decided 2026-09-30 (user, overengineering review), superseding the scenario bullet, the
`exercised-fixture.test.sh` bullet and the eval-cases bullet above (the unmappable-test eval is
dropped):

- Four scenarios: `calls_sut`, `no_assertion`, `boundary` and `copied_logic`. `relation` and
  `literal` are cut (their outcomes repeat `calls_sut` and `copied_logic`). `unreached_branch` stays
  only while DT13 is pending; if DT13 folds unreached into `input-gap`, it goes too.
- `exercised-fixture.test.sh` is cut. The seams are the evals and the live runs; the fixture's
  config carries no `tests` key (DT2).
- Evals: one case per scenario plus the uncommitted-tests case (DT1); no count gate. The setup
  case becomes "a `test-command` without `{tests}` fails `setup check`" (DT14), since the bare
  `tests/` glob check left with the `tests` key.
- Live runs: the scenarios plus `calls_sut_uncommitted`.

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
"Bash and MCP writes bypass the hooks", spec:910). The Release 2 judge plan also deferred it.

Decided 2026-09-30 (user): stays deferred. The orchestrator files an issue owned by a follow-up to
the `testing` plugin's hooks; owner: issue to be filed.

Research tag: `bashEditDiff-coverage`. Measure, on the installed Claude Code version, how many
Bash-written test files reach a PostToolUse hook under the default permission mode with and without
`bashEditDiffEnabled`; owner: issue to be filed (a `testing` hooks follow-up).

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

Because the unit is the set, the Phase 4 triage brief hands over every changed test for each
survivor, not only "the tests that covered it" (SKILL.md:195-196); `no-assertion` means no
assertion anywhere in the set reaches the value (review 2, 2026-09-30).

Basis: SKILL.md:167 (one state per mutant against the cached covering tests); Q11 (spec:98-100).

### DT13: Reachability: telling an unreached mutant from a survivor

Found by the devils-advocate pass (HIGH). Under the manual protocol a mutant on a line the changed
tests never run passes those tests and would read as survived.

Recommended answer taken unattended (2026-09-30): every survivor gets one sentinel run before triage,
under the same per-mutant apply-and-restore gate.

- The sentinel is a process exit with a unique code, inserted before the statement that contains
  the mutated line (at its indentation; for a continuation or header line, before the statement's
  first line), with the original code left in place. Python `os._exit(97)`, JS
  `process.exit(97)`, C# `Environment.Exit(97)`, Go `os.Exit(97)`. An `except Exception` or
  `catch` cannot swallow a process exit.
- Reached: the changed-test run exits with code 97. The mutant is a survivor.
- Unreached: the run completes without code 97. The mutant is reported `unreached`: a mapping
  miss, never a survivor and never given a cause.
- Unknown: any other failure (a syntax or compile error from the insertion, a runner crash). The
  mutant is a survivor with reachability `unknown`, which DT5's rule handles.
- A tool whose restricted run keeps its own no-coverage state (Phase 1 column, DT8) skips the
  sentinel. Cost: one extra run per survivor, not per mutant.

Review 2, 2026-09-30 (old: replace the line with a raise, any failure means reached; new: insert
an exit before the statement, only exit code 97 means reached; why: a replacement can fail to
parse, which read as a false "reached", and a `try/except: pass` test, the exact can't-fail shape
this release targets, swallowed the raise and hid its mutants as `unreached`).

The sentinel is a reachability probe only. It is not the extreme-mutation mode A12 names as a
candidate (that mode would report pseudo-tested methods as findings); no sentinel result becomes a
finding. A reached survivor under a test that swallows exceptions is close to a pseudo-tested
signal; reporting it as such stays A12's scope.

Pending the user (2026-09-30): the overengineering review recommends folding unreached into
input-gap and deferring the sentinel, because exit-code detection likely fails under
vitest/jest/dotnet/go workers.

Basis: SKILL.md:125-126 (no-coverage only when a coverage report exists); restoration-regimes.md:35-43
(in-tree per-mutant gate); A12 (spec:977).

### DT14: The test command for the manual fallback

Found by the devils-advocate pass (HIGH). The config's `command` invokes the mutation tool
(config-template.md:18-22); nothing holds the project's test command or its per-file filter.

Recommended answer taken unattended (2026-09-30): a new optional key `test-command`, a command with
a `{tests}` placeholder that the audit fills with the changed test paths, for runners that take a
path list (`python -m pytest {tests}`, `python -m unittest {tests}`, `npx vitest run {tests}`,
`npx jest {tests}`). `setup apply` proposes it per ecosystem. The exercised scope under the manual
protocol refuses without it, naming `/mutation-testing:setup apply`.

- Each path is substituted as its own shell-quoted argument. A changed path containing a character
  outside `[A-Za-z0-9._/-]` is refused by name, never substituted: file names come from a diff the
  audit may be reading on an untrusted branch.
- v1 supports path-list runners only. Runners that filter by name (`dotnet test --filter`, Go
  `-run`, surefire `-Dtest`) use a tool restriction Phase 1 verified, or the scope refuses for that
  ecosystem; `setup check` reports a `test-command` without `{tests}` as a failure.
- Windows: the command runs under the same bash the plugin's scripts use (Git Bash); forward-slash
  repository paths are passed as-is. No `cmd.exe` form is supported.
- Review 2, 2026-09-30 (old: one raw substitution, a `dotnet --filter` example; new: per-path
  quoting, a character allowlist, path-list runners only; why: spaces split arguments, a crafted
  file name was shell injection, and a name filter cannot take a path list).
- Decided 2026-09-30 (user, overengineering review): `test-command` stays an optional key in the
  existing `.claude/mutation-testing.md` (not a new file), with per-path quoting. The DT2 decision
  does not remove the need for it: the testing config and its adapters hold file globs and
  assertion patterns, no run command (`plugins/testing/skills/audit/adapters/py-pytest.yaml`).
- The character allowlist: pending the user: cut recommended. It stays in the design until the
  user decides.

Basis: config-template.md:18-22; SKILL.md:161-163 (manual protocol).

### DT15: Preflight order under the exercised scope

Found by the devils-advocate pass (HIGH and MEDIUM). Phase 0 resolves the write regime and the
dirty-target stop before Phase 1 knows which files the exercised scope will mutate, and its
baseline runs the whole suite.

Recommended answer taken unattended (2026-09-30): under the exercised scope Phase 0 runs in this
order: config, tool availability, changed tests (DT1), mapping (DT3), effective runner and regime
(a tool with a verified restriction, else manual, DT8), dirty-target stop on the mapped files,
regime gate including the refusal rule, restricted baseline run (once, per the user's decision
below), then the Phase 0 snapshot.

- The restricted double run replaces the full-suite baseline for this scope: a red test the
  mutants never run cannot kill them, so it is no reason to stop. Red stops the run; two different
  results stop it as flaky. Its wall-clock is the cost-estimate base (DT4).
- Two runs catch only gross flakiness (a test failing 10% of runs differs across two runs about
  18% of the time). So after the mutant loop, the changed-test set runs once more on the
  unmutated tree; a result different from the baseline marks every kill in the report as
  unreliable.
- Decided 2026-09-30 (user, overengineering review), superseding the two bullets above: one
  restricted baseline run, not two, and no post-loop unmutated rerun. Red stops the run. The
  existing flaky-test gotcha (SKILL.md:335-336) stays as the stated limit. Switch condition: a live
  run shows a flaky kill.
- Phase 1 steps 2 and 3 (coverage drop, suppression dispositions) key on the mapped-line set
  instead of the changed-line set under this scope, so an arid record on a mapped node still
  applies instead of falling to not-examined (SKILL.md:143-144).
- Review 2, 2026-09-30 (old: order and baseline unstated, steps 2 and 3 unadapted; new: the order
  above, replacement baseline, post-loop rerun, mapped-line keying; why: an unrelated red test
  stopped the run, and every suppression on a mapped node was ignored).

Basis: SKILL.md:93-119 (Phase 0 stops and regime); SKILL.md:335-336 (flaky tests inflate the score).

### DT16: The findings tier rationale outside the diff

Found by the plan-reviewer (CRITICAL). The detector-findings contract argues IMPORTANT for
`rule-survivor-productive` from "this producer is diff-scoped, so the mutated node is inside the
change under review" (`docs/conventions/detector-findings/README.md:234`). Under the exercised
scope the mutated node is outside the change; the change is the tests.

Recommended answer taken unattended (2026-09-30): keep the rule ids and the IMPORTANT tier, and
amend the rationale of two rows, `rule-survivor-productive` (README.md:234) and
`rule-survivor-unclassified` (README.md:235, which argues from "a mutant survived inside the
diff"), to cover both scopes. Under the exercised scope IMPORTANT's degradation-with-a-named-trigger
limb matches for every productive or unclassified survivor, whatever its cause. The trigger is
named so it holds for `input-gap` too: "the first regression that changes the result for an input
the changed tests do not use, in a function they exercise, ships green". The row is rule-keyed, so
the argument must hold for every cause; README.md:240 forbids a per-finding tier drop. The tier and
every consumer's reading of it stay the same: `crosswalk.md:38-41` keys on the rule id, and no
reader in `persist-findings.md` or `SKILL.md` quotes the rationale text. The amendment is a
convention edit with its own CHANGELOG entry and a consumer check first.

Review 2, 2026-09-30 (old: row 234 only, trigger "the first regression in the mapped behavior";
new: rows 234 and 235, a trigger that holds for `input-gap`; why: row 235 argues from the diff
too, and the old trigger rested on "a coverage claim nothing backs", which an `input-gap` test
does back).

Decided 2026-09-30 (user): the README edit to rows 234 and 235 is approved.

Basis: `docs/conventions/detector-findings/README.md:234-235, :238, :240`; crosswalk.md:38-41.

## Dependency order

DT2 and DT14 before DT4 and DT15 (the trigger and preflight need the test-file source and the
`test-command` key). DT8 (plan Phase 1 probe) before DT15's effective-runner choice. DT12 fixes the fixture shape
in DT9. DT13 before DT5 and DT7 (cause and coverage need reachability). DT16 before any persisted
exercised-scope row ships. DT10 has no dependency inside 2b.
