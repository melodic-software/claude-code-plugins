# PLAN: tautological-tests-mutation-scope (Release 2b mutation scope)

## Brief

The contract is the Brief in `docs/specs/tautological-tests.md` (Q1-Q13, amendments A1-A14); this
plan does not reopen it. Release 2b is the mutation-scope item the user split off Release 2 on
2026-09-29. Release 2 outline scope, and where each item lands:

| Outline item | Where in this plan |
|---|---|
| `mutation-testing:audit` gains a scope that mutates the production code the changed tests exercise (Q11) | Phases 1, 3, 4 (design DT1-DT4, DT7, DT8, DT12-DT15) |
| It classifies each survivor: no assertion, expected value from the code under test, input gap (Q11) | Phase 4 (design DT5, DT6, DT13, DT16) |
| Evaluate PostToolUse `bashEditDiff` (beta) to narrow the Bash-write gap | Not in this plan: design DT10 defers it with research tag `bashEditDiff-coverage`; no plan owns it (see Open questions) |

Design: `design/design-threads.md` beside this file (DT1-DT16; handoff gate PASS on 2026-09-30,
re-read after the stress-test revision: every thread is resolved, directional with a research tag,
or deferred with one).

Goal: an agent that adds or changes tests gets a mutation signal on the production code those tests
exercise, judged against those tests as a set, and each surviving mutant says why it lived. A clean
result states plainly that it does not clear a copied-logic oracle.

Known limit (Tier 0 re-run, design Evidence): mutation kills every mutant for a copied-logic oracle
(3/3) and none for a calls-the-code-under-test oracle (0/3). This scope catches the second and
cannot see the first; the report says so and points to `/testing:test-value`.

This plan and its design were graduated to `docs/specs/tautological-tests-mutation-scope/` in the
pull request that proposed them, so every path below is under `docs/specs/`.

## Plan

Standards grounding: `AGENTS.md` (draft PRs, Conventional Commits titles),
`.claude/rules/pr-body-contract.md`, `.claude/rules/skill-bodies-state-current-rules.md` (a
restated tool option needs a claim, basis, as-of date and recheck trigger; a `## Next` names natural
successors), `docs/conventions/topic-docs/README.md` and `scripts/check-contract-slice-prune.sh` (no
path left under `docs/topics/`), `docs/conventions/detector-findings/README.md` (the findings
contract this producer follows; DT16 amends one row's rationale).

Test strategy: TDD where a script exists (Red, Green, Refactor). Test boundaries:

- `plugins/mutation-testing/scripts/exercised-fixture.test.sh` (new): applies the mutants the
  fixture's `EXPECTED.md` lists and asserts each state per scenario. The one new deterministic seam
  (design DT9).
- `plugins/mutation-testing/skills/audit/evals/evals.json` and
  `plugins/mutation-testing/skills/setup/evals/evals.json` (existing, prose-graded): new cases.
- `plugins/mutation-testing/scripts/suppression-lint.test.sh` (existing, unchanged; must stay green).
- Skill behavior end to end: live `claude -p` runs of the edited plugin on scratch copies of the
  fixture (Phase 5). Model output is not unit-tested.

### Phase 1: Tool test-restriction probe (DT8) [TODO]

For each tool the config accepts (`stryker-js`, `stryker-net`, `stryker4s`, `pitest`, `infection`,
`mutmut`; `config-template.md:16`), fetch the current official docs and record the option, if any,
that restricts a run to named test files or test cases, and how that option interacts with the
tool's own coverage or dry-run phase. Write one row per tool to
`docs/specs/tautological-tests-mutation-scope/design/tool-test-restriction.md`:
`| <tool> | <option or none> | <granularity: file, case, none> | <coverage/dry-run interaction> | <keeps no-coverage: yes, no, unknown> | <URL> | <fetched date> |`.
Also record, per ecosystem `setup` detects, the filter form a `test-command` `{tests}` placeholder
needs (DT14). Use `RESEARCH-tools.md` facts only as leads; `tooling.md` rows are known stale
(spec:158-159) and are not a source. A tool with `no` or `unknown` in the no-coverage column is
manual-only under this scope (DT8).

**Sanity Check:**

- `grep -cE '^\| (stryker-js|stryker-net|stryker4s|pitest|infection|mutmut) \|' docs/specs/tautological-tests-mutation-scope/design/tool-test-restriction.md` returns 6.
- `grep -E '^\| (stryker-js|stryker-net|stryker4s|pitest|infection|mutmut) \|' docs/specs/tautological-tests-mutation-scope/design/tool-test-restriction.md | grep -vc 'https://'` returns 0.
- `grep -E '^\| (stryker-js|stryker-net|stryker4s|pitest|infection|mutmut) \|' docs/specs/tautological-tests-mutation-scope/design/tool-test-restriction.md | grep -vcE '\| (yes|no|unknown) \|'` returns 0.

### Phase 2: Fixture and its self-check (DT9, DT12, DT13) [TODO]

Red first: write `plugins/mutation-testing/scripts/exercised-fixture.test.sh`. It resolves
`python3`, then `python` (precedent `plugins/code-metrics/scripts/dispatch.test.sh:18`), skips when
neither exists and fails instead when `CI` is set. It copies the fixture to a temp dir, applies each
mutant `EXPECTED.md` lists, runs that scenario's test file, restores, and asserts the state per
mutant, including the sentinel result for the unreached scenario. It fails until the fixture exists.

Then the fixture, `plugins/mutation-testing/skills/audit/evals/fixtures/exercised-scope/`:

- `app.py`: `price_with_tax` spread over several lines, so the manual protocol's one-mutant-per-line
  operators (SKILL.md:158-163) yield more than one mutant, and a discount branch above a threshold.
- `scenarios/<name>/test_app.py`, one per outcome, snake-case directory names so
  `python -m unittest <path>` imports them: `calls_sut` (survivors, `expected-from-sut`),
  `relation` (survivors, `expected-from-sut`: its expected side calls the code under test),
  `boundary` (the threshold-line mutant is reached and survives, `input-gap`), `copied_logic` (no
  survivor, the blind-spot line), `literal` (no survivor), `no_assertion` (survivors,
  `no-assertion`), `unreached_branch` (the discount-branch mutants are `unreached`, never
  survivors). At least one listed mutant sits on a continuation or header line (DT13).
- `.claude/mutation-testing.md`: `tool: manual`, `diff-target: main`, `mutate: [app.py]`,
  `tests: ["**/test_*.py"]`, `test-command: python -m unittest {tests}`.
- `EXPECTED.md`: per scenario, the exact mutants (line, operator), the expected state, sentinel
  result and cause of each, which the eval cases and the self-check both read.

**Sanity Check:**

- `bash plugins/mutation-testing/scripts/exercised-fixture.test.sh` exits 0.
- `ls plugins/mutation-testing/skills/audit/evals/fixtures/exercised-scope/scenarios | wc -l` returns 7.
- `for t in expected-from-sut no-assertion input-gap unreached; do grep -q -- "$t" plugins/mutation-testing/skills/audit/evals/fixtures/exercised-scope/EXPECTED.md || echo "missing $t"; done` prints nothing.

### Phase 3: Config keys and setup (DT2, DT14) [TODO]

- `skills/setup/templates/config-template.md`: optional `tests` key (framework filename-convention
  globs; never a bare `test/` or `tests/` folder, per Q6) and optional `test-command` key (with the
  `{tests}` placeholder).
- `skills/setup/SKILL.md`: `apply` proposes both per detected ecosystem, `test-command` only for
  path-list runners (DT14); `check` reports a bare-folder `tests` glob and a `test-command` without
  `{tests}` as failures.
- `skills/setup/evals/evals.json`: a case where a bare `tests/` glob fails `check`.

The user's reading of Q6 (design DT2 open question) may change where `apply` takes the `tests`
globs from; this phase waits for that answer.

**Sanity Check:**

- `grep -cE '^(tests|test-command):' plugins/mutation-testing/skills/setup/templates/config-template.md` returns 2.
- `grep -c '{tests}' plugins/mutation-testing/skills/setup/SKILL.md` is at least 1.
- `python3 -c "import json;d=json.load(open('plugins/mutation-testing/skills/setup/evals/evals.json'));print(sum('tests/' in e['prompt']+e['expected_output'] for e in d['evals']))"` prints at least 1.

### Phase 4: The exercised scope, reachability and survivor causes (DT1, DT3-DT7, DT12-DT16) [TODO]

Pre-flight consumer check first, listing hits for review (not a stop on any hit):
`grep -rn -e 'mutation-testing.md' -e 'max-mutants' -e 'rule-survivor-' -e '### Survivors' --include='*.md' --include='*.sh' --include='*.json' plugins docs | grep -v '^docs/specs/tautological-tests-mutation-scope/'`.
Record each hit outside `plugins/mutation-testing/` with whether it reads a changed surface. A hit
that parses the Survivors table columns or the config keys is a stop and a `/planning:plan review`;
`docs/conventions/detector-findings/README.md` and
`plugins/review/skills/audit-enforceability/context/crosswalk.md:38-41` are expected (both key on
rule ids, which do not change).

Changes, all under `plugins/mutation-testing/` unless named:

- `skills/audit/SKILL.md`:
  - Description: no longer "diff-scoped" only; it names both scopes. Argument parsing:
    `--exercised`, mutually exclusive with `--full` and `--paths`.
  - Phase 0, under the exercised scope, in DT15's order: config, tool, changed tests (committed
    range plus working tree, DT1), mapping (DT3; zero functions ends as `no mapping: scope
    empty`), effective runner and regime (a verified tool restriction, each option with a
    four-part verification record, else manual with `test-command` and DT14's quoting and
    allowlist), dirty-target stop on the mapped files, regime gate, restricted baseline twice
    (replacing the full-suite baseline for this scope), snapshot.
  - Phase 1: the trigger (DT4: auto-engage when the committed range plus working tree touches
    `tests` and no `mutate` line; cap is the smaller of the effort cap and 15 when no cap is set;
    the mixed-diff hint with the unexamined count). Steps 2 and 3 key on the mapped-line set, and
    step 4's test selection becomes the changed-test set, both stated as divergences (DT1, DT12,
    DT15).
  - Phase 3: each mutant runs against the changed-test set; every survivor gets one sentinel run,
    an exit with code 97 inserted before its statement (DT13): code 97 is reached, no 97 is
    `unreached` (never a survivor), any other failure is reachability `unknown`. After the loop,
    one unmutated rerun of the set; a changed result marks kills unreliable (DT15).
  - Phase 4: the triage brief hands over the whole changed-test set and adds the cause for
    productive survivors, with a quoted line or `unclassified`, the tie-break rules, and the
    `unknown`-reachability rule (DT5, DT12).
  - Phase 5: coverage and gap from reachability, else `unknown` (DT7); the fixed scope line
    `Scope: exercised (<explicit|auto-engaged>), changed tests as one set`; the fixed blind-spot line
    (DT6).
  - `## Next`: add `A clean exercised run: /testing:test-value.`
- `skills/audit/templates/report.md`: the scope line, a `Cause` column in the Survivors table, an
  `Unreached: <n>` line, the blind-spot line.
- `skills/audit/context/persist-findings.md`: the cause leads the `Finding` text and selects the
  `Action` wording; no new rule id and no new column; an `unreached` mutant is never a row.
- `skills/principles/reference/theory.md`, section "What a mutation score is evidence for": one
  paragraph on the copied-logic limit with the Tier 0 matrix, which the audit cites.
- `skills/audit/evals/evals.json`: one case per fixture scenario (7), one with uncommitted tests,
  one with an unmappable test.
- `docs/conventions/detector-findings/README.md` (the rationale of the `rule-survivor-productive`
  and `rule-survivor-unclassified` rows, DT16, with the trigger phrase "an input the changed tests
  do not use") and `docs/conventions/detector-findings/CHANGELOG.md`.

No em dashes in new text (the existing `report.md` uses them; do not copy them).

**Sanity Check:**

- `grep -c -- '--exercised' plugins/mutation-testing/skills/audit/SKILL.md` is at least 3.
- `grep -cE 'expected-from-sut|no-assertion|input-gap' plugins/mutation-testing/skills/audit/SKILL.md` is at least 3.
- `grep -c 'no mapping: scope empty' plugins/mutation-testing/skills/audit/SKILL.md` is at least 1.
- `grep -c 'Scope: exercised (' plugins/mutation-testing/skills/audit/templates/report.md` returns 1.
- `grep -c '| Cause |' plugins/mutation-testing/skills/audit/templates/report.md` returns 1.
- `grep -c 'A clean exercised run: /testing:test-value' plugins/mutation-testing/skills/audit/SKILL.md` returns 1.
- `python3 -c "import json;d=json.load(open('plugins/mutation-testing/skills/audit/evals/evals.json'));print(len(d['evals']))"` prints at least 23.
- `grep -c 'os._exit(97)' plugins/mutation-testing/skills/audit/SKILL.md` is at least 1 (the sentinel).
- `test "$(git show origin/main:plugins/mutation-testing/skills/audit/context/persist-findings.md | grep -o 'rule-survivor-[a-z-]*' | sort -u)" = "$(grep -o 'rule-survivor-[a-z-]*' plugins/mutation-testing/skills/audit/context/persist-findings.md | sort -u)"` passes (no new rule id).
- `grep -c 'an input the changed tests do not use' docs/conventions/detector-findings/README.md` returns 2.
- `/skill-quality:check check plugins/mutation-testing` reports no FAIL.
- `git diff origin/main -- plugins/mutation-testing docs/conventions | grep '^+' | grep -cP '\x{2014}'` returns 0 (no em dash added).

### Phase 5: Release housekeeping and live runs [TODO]

- `plugins/mutation-testing/.claude-plugin/plugin.json`: minor bump above main at merge (a new flag
  and two config keys); description names the exercised scope.
- `plugins/mutation-testing/CHANGELOG.md` entry; `README.md` names `--exercised`, `tests` and
  `test-command`.
- Live runs, one per scenario `calls_sut`, `boundary`, `no_assertion`, `copied_logic` and
  `unreached_branch`, plus `calls_sut` with its tests left uncommitted, run as
  `calls_sut_uncommitted`. Each runs in `"${TMPDIR:-/tmp}/tt-mutation-live/<run>/"`, outside this
  checkout so its CLAUDE.md and AGENTS.md do not load into the run. For each: copy `app.py` and
  `.claude/mutation-testing.md`, `git init -b main`, commit both on `main`, then
  `git switch -c tests` and add the scenario's test file (committed, or left uncommitted for the
  variant). Run from that directory:
  `claude -p --permission-mode auto --plugin-dir <worktree>/plugins/mutation-testing "/mutation-testing:audit"`
  (auto mode per `AGENTS.md`, because the audit edits `app.py` and runs Bash) and save stdout as
  `report.md` there. Record the Claude Code version, and confirm from the output that the edited
  plugin (the new version number) loaded rather than the installed one. If the installed copy wins,
  disable it for the run with `claude plugin disable` and re-enable it after; that is a user-scope
  change that needs the user's OK at run time. Distill the results into this phase's notes.

**Sanity Check** (with `L="${TMPDIR:-/tmp}/tt-mutation-live"`):

- `grep -l 'Scope: exercised (auto-engaged)' "$L"/*/report.md | wc -l` returns 6.
- `grep -cE '^\| .*\| expected-from-sut \|' "$L/calls_sut/report.md"` is at least 1, and the same for `"$L/calls_sut_uncommitted/report.md"`.
- `grep -cE '^\| .*\| input-gap \|' "$L/boundary/report.md"` is at least 1.
- `grep -cE '^\| .*\| no-assertion \|' "$L/no_assertion/report.md"` is at least 1.
- `grep -cE '^\| [^|]+:[0-9]+ \|' "$L/copied_logic/report.md"` returns 0 (no survivor row) and `grep -c 'copied-logic' "$L/copied_logic/report.md"` is at least 1 (the blind-spot line).
- `grep -cE '^Unreached: [1-9]' "$L/unreached_branch/report.md"` returns 1 and `grep -cE '^\| .*\| (expected-from-sut|no-assertion|input-gap) \|' "$L/unreached_branch/report.md"` returns 0.
- `bash scripts/validate-plugins.sh` exits 0.
- `bash scripts/run-plugin-tests.sh` exits 0.
- `bash scripts/check-changelog-parity.sh --check` exits 0.
- `bash scripts/check-changelog-parity.sh --check-bump origin/main` exits 0.
- `bash scripts/check-contract-slice-prune.sh --check-diff origin/main` exits 0.

## Files affected

Created: `plugins/mutation-testing/scripts/exercised-fixture.test.sh`;
`plugins/mutation-testing/skills/audit/evals/fixtures/exercised-scope/` (`app.py`, seven
`scenarios/*/test_app.py`, `.claude/mutation-testing.md`, `EXPECTED.md`);
`docs/specs/tautological-tests-mutation-scope/design/tool-test-restriction.md`.

Modified under `plugins/mutation-testing/`: `skills/audit/SKILL.md`,
`skills/audit/templates/report.md`, `skills/audit/context/persist-findings.md`,
`skills/audit/evals/evals.json`, `skills/setup/SKILL.md`,
`skills/setup/templates/config-template.md`, `skills/setup/evals/evals.json`,
`skills/principles/reference/theory.md`, `.claude-plugin/plugin.json`, `CHANGELOG.md`, `README.md`.

Modified elsewhere: `docs/conventions/detector-findings/README.md`,
`docs/conventions/detector-findings/CHANGELOG.md`.

## Alternatives considered

| Alternative | Why rejected | Switch condition |
|---|---|---|
| Run every covering test against each mutant (DT1 A) | A strong existing test kills the mutant and hides the weak new test | The user wants a suite-level answer rather than one about the changed tests |
| Per-test kill attribution (DT12 B) | Multiplies runs by the changed-test count; Q11 asks why each mutant lived | The user wants per-test verdicts and accepts the cost |
| Read the `testing` adapter globs for test files (DT2 B) | An installed plugin cannot reach another plugin's files reliably | Plugins gain a supported cross-plugin data path, or the user reads Q6 as binding (DT2 open question) |
| Per-test coverage tool for mapping and reachability (DT3 A) | Needs a per-ecosystem coverage command the config does not hold | Phase 1 finds every configured tool keeps its no-coverage state under restriction |
| A cause rule id per survivor cause | The findings contract keys the rule on the disposition alone (persist-findings.md:248-260) | The detector-findings contract adds a sub-classification field |
| Take `bashEditDiff` into 2b (DT10) | The audit reads `git diff` and the working tree, which already see Bash writes | The audit gains a hook-driven mode |

## Risks and mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Static mapping misses a function the tests reach through indirection | Med | Low | Fewer scoped lines, never a false survivor; zero functions ends as `no mapping: scope empty`; the scope report lists the mapped functions |
| Static mapping includes code the changed tests never reach | Med | Low | The sentinel run reports those mutants `unreached` (DT13) |
| The sentinel insertion breaks parsing or compiling | Med | Low | Reachability becomes `unknown`, never "reached"; DT5's `unknown` rule applies (DT13) |
| No tool can be restricted to named tests | Med | Med | Manual protocol with `test-command` (DT8, DT14), resolved in Phase 0 |
| A flaky changed test kills mutants by accident | Med | Med | Phase 0 runs the changed-test set twice and stops on a difference; a post-loop unmutated rerun marks kills unreliable when it differs. Two runs catch gross flakiness only (DT15) |
| Auto-engaged runs cost more than expected | Med | Med | `medium` cap when no cap is set; estimate from the restricted baseline (DT4) |
| The `tests` defaults drift from the `testing` adapters' globs | Med | Low | Known risk; Q6 reading is a user question (DT2) |
| The cause label is wrong but plausible | Med | Med | Quoted evidence or `unclassified`, tie-break rules (DT5); the fixture's causes are graded by evals and live runs |
| A clean exercised run is read as clearing the tests | High | Med | Fixed blind-spot line in every exercised report (DT6) |
| One language fixture only | High | Low | Recorded: the fixture proves the protocol, not per-language parity; Q12's per-language corpus binds the `testing` scanner rules |

## Blast radius

MEDIUM. One plugin (`mutation-testing`) plus one rationale cell in the shared detector-findings
convention (tier unchanged). Opt-in behavior plus an auto-engage path that fires only on diffs that
produce zero mutants today, capped by default. No hook, no gate, no other plugin's code changes. Two
new optional config keys; existing configs keep working for the diff scope.

## Stress-test summary

Step 3 plan-reviewer (fresh context) and Step 4 `/planning:devils-advocate` (fresh context) ran
against the same first draft in one message, as the plan skill's audit-judgment note allows at
MEDIUM blast radius, because the devils-advocate criteria read off the draft, not off the reviewer's
findings.

- Plan-reviewer: 2 CRITICAL, 7 IMPORTANT, 6 SUGGESTION.
- Devils-advocate: 1 CRITICAL, 5 HIGH, 6 MEDIUM, 4 LOW.

Each CRITICAL and HIGH, verified against the files before fixing:

| Finding | Resolution |
|---|---|
| Changed-test set masks weak siblings; the fixture could never show the causes (both passes, CRITICAL) | DT12 (the kill unit is the set; per-test attribution rejected with a switch condition); DT9 fixture split into six scenarios; Phase 5 checks count Survivors-table rows per scenario |
| Findings tier rationale assumes the diff scope (`detector-findings/README.md:234`) (reviewer CRITICAL) | DT16: rationale amended through the degradation limb, tier and rule ids unchanged; README and CHANGELOG added to Phase 4 and Files affected |
| Fixture assumes 3 Tier 0 mutants the skill never generates (DA HIGH) | DT9: `app.py` spread over lines; `EXPECTED.md` lists the mutants the manual protocol generates |
| Unreached mutants read as survivors under the manual protocol (DA HIGH) | DT13 sentinel run per survivor; DT7 coverage from reachability, else `unknown` |
| No test command for the manual fallback (DA HIGH) | DT14 `test-command` key with `{tests}`; Phase 3 |
| Mid-run switch to the manual regime skips the Phase 0 gate (DA HIGH) | DT15: effective runner and regime resolved in Phase 0 |
| Uncommitted tests invisible to the diff (DA HIGH) | DT1 revision: committed range plus working tree; an eval and a live-run variant |

MEDIUM, IMPORTANT and lower, folded in: pre-flight grep quoted and narrowed, lists hits instead of
stopping (reviewer 4, 5); live runs use `claude -p --plugin-dir` from the scratch directory with a
named branch layout (reviewer 6); exact scope-line grep (reviewer 7); setup eval (reviewer 8); the
relation oracle's expected cause (reviewer 9); python resolution (reviewer 10, DA 15); principles
file named (reviewer 11); `## Next` bullet (reviewer 12); flag exclusivity (reviewer 13); graduation
timing stated in the Brief (reviewer 14, DA 13); preflight ordering and restricted baseline (DA 7,
10, DT15); zero-mapping result (DA 8); auto-engage cap and estimate (DA 9); cause tie-breaks
(DA 11); Phase 1 coverage-interaction column (DA 12); Displaced answers block added (DA 14);
mixed-diff hint count (DA 16). Reviewer 3 (Q6) and reviewer 15 (the spec's Release 2 gate path) are
open questions below; the single-language fixture (DA 11) is a recorded risk.

Review 2 (2026-09-30): `/planning:plan review` dispatched a fresh-context plan-reviewer on DT12-DT16
and the sections they changed. Findings: 1 CRITICAL, 10 IMPORTANT, 5 SUGGESTION. All were folded
in:

| Finding | Resolution |
|---|---|
| The `relation` scenario expected `input-gap`, but DT5's tie-break makes it `expected-from-sut` (CRITICAL) | `relation` now expects `expected-from-sut`; a new `boundary` scenario carries `input-gap` (DT9; seven scenarios) |
| Sentinel replacement can fail to parse and read as "reached" | DT13 inserts an exit before the statement; only exit code 97 means reached; other failures mean `unknown` |
| A `try/except: pass` test swallowed the sentinel and hid its mutants | A process exit cannot be caught; the Risks row is removed |
| `{tests}` was unquoted, open to injection, and wrong for name filters | DT14: per-path quoting, a character allowlist, path-list runners only, Windows through Git Bash |
| Auto-engage read only the committed diff | DT4 trigger reads the committed range plus the working tree |
| Live run had no permission mode and ran inside the checkout | `--permission-mode auto`; the run root moves outside the checkout; config committed on `main` |
| Sanity checks passed vacuously | Per-term greps, a zero-survivor-row check, an `Unreached: n` check, the exact README phrase |
| Row 235 (`rule-survivor-unclassified`) also argues from the diff | DT16 amends rows 234 and 235 |
| The degradation trigger did not hold for `input-gap` | DT16 trigger reworded to name an unused input |
| Phase 0 order and baseline unstated | DT15 fixes the order; the restricted double run replaces the full-suite baseline |
| Phase 1 steps 2-3 still keyed on changed lines | DT15 re-keys them on the mapped-line set |
| Suggestions: two runs miss mild flakes, cap raised a `low` run, triage handover ambiguous, A12 note, stale description | Post-loop unmutated rerun; cap is the smaller of the effort cap and 15; the whole set is handed over (DT12); A12 note in DT13; description reworded in Phase 4 |

Not probed: whether `claude -p --plugin-dir` shadows an installed plugin of the same name (Phase 5
records it at run time).

## Execution shape

Fully sequential: Phase 1 gates Phase 4's effective-runner wiring; Phase 2's fixture gates Phase
4's evals; Phase 3's keys gate Phase 4's preflight; Phase 5 closes.

| Phase | Surface | Basis |
|---|---|---|
| 1 | sub-agent worker (research) | bounded doc lookups, one file written |
| 2 | main session | TDD on the one new script |
| 3 | main session | small, but waits on the Q6 answer |
| 4 | main session | the skill body carries the design judgment |
| 5 | main session | live runs need the edited plugin loaded and a human-readable check |

## Open questions

- Q6 reading (design DT2): does "one pattern list shared with `testing:audit`" bind
  `mutation-testing`? Options: a `tests` key as designed (recommended); the key seeded from
  `.claude/testing.yaml` when present; or a Q6 amendment. Unblocks Phase 3.
- Spec pointer: `docs/specs/tautological-tests.md` needs a Release 2b line in its Release 2 outline
  Sanity Check, `test -f docs/specs/tautological-tests-mutation-scope/PLAN.md`, and the
  mutation-scope bullet pointing here. Its existing gate `test -f docs/topics/tautological-tests-judge/PLAN.md`
  (spec:877) can never pass on main, because `check-contract-slice-prune.sh` forbids `docs/topics/`
  paths there. This PR does not edit the spec; the owner of the PR that edits it (the Release 2
  judge plan, which already schedules that line's rewrite) adds both. Unblocks landing 2b code.
- `bashEditDiff`: deferred by both the Release 2 judge plan and this one (DT10). It needs an owner
  the user names; the natural home is a `testing` hooks follow-up.

## Displaced answers and new external effects

| Q | What the user said | What the plan proposes | New external effect | Source |
|---|---|---|---|---|
| none | (no interview answer is displaced) | A shared-convention edit: the `rule-survivor-productive` rationale in `docs/conventions/detector-findings/README.md` | A change to a marketplace-wide convention doc (tier unchanged) | reviewer fix |
| none | (none) | Phase 5 may disable the installed `mutation-testing` plugin for a live run | A user-scope setting change, reverted after the run, asked at run time | reviewer fix |

## Handoff to implementation

Approval: pending the user (unattended run, recommended answers taken)

### User-approval gates

- Plan approval itself, including each "Recommended answer taken unattended (2026-09-30)" in
  `design/design-threads.md`.
- Each row of "Displaced answers and new external effects", replied to separately.
- The Q6 reading before Phase 3.
- Phase 5: any user-scope plugin toggle.

### Execution shape ([EXEC-SHAPE] tagged)

See "Execution shape" above. One draft PR for Phases 1-5, committed per phase.

| Decision | What it changes in the plan | Basis (evidence) | Source |
|---|---|---|---|
| [EXEC-SHAPE] Sequential phases, one PR | No parallel workers | File overlap: Phases 3-5 all edit `plugins/mutation-testing` skill files | /planning:plan Step 4.5 |
| [EXEC-SHAPE] Phase 1 on a research sub-agent | Keeps doc fetches out of the main context | Phase 1 writes one file and reads only external docs | /planning:plan Step 4.5 |

### Mechanical work

Commit per phase with a Conventional subject scoped `mutation-testing`. Run each phase's Sanity
Check before its commit. A divergence from this plan routes to `/planning:plan review`.
