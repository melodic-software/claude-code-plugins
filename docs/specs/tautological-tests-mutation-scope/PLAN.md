# PLAN: tautological-tests-mutation-scope (Release 2b mutation scope)

## Brief

The contract is the Brief in `docs/specs/tautological-tests.md` (Q1-Q13, amendments A1-A14); this
plan does not reopen it. Release 2b is the mutation-scope item the user split off Release 2 on
2026-09-29. Release 2 outline scope, and where each item lands:

| Outline item | Where in this plan |
|---|---|
| `mutation-testing:audit` gains a scope that mutates the production code the changed tests exercise (Q11) | Phases 1, 3, 4 (design DT1-DT4, DT7, DT8, DT12-DT15) |
| It classifies each survivor: no assertion, expected value from the code under test, input gap (Q11) | Phase 4 (design DT5, DT6, DT13, DT16) |
| Evaluate PostToolUse `bashEditDiff` (beta) to narrow the Bash-write gap | Not in this plan: design DT10 keeps it deferred (user, 2026-09-30) with research tag `bashEditDiff-coverage`; owner: #5608 (a `testing` hooks follow-up) |

Design: `design/design-threads.md` beside this file (DT1-DT16; handoff gate PASS on 2026-09-30,
re-read after the stress-test revision: every thread is resolved, directional with a research tag,
or deferred with one; since 2026-09-30, DT13 and DT14's character allowlist wait on the user and
DT2 carries the open tag `testing-glob-source`). The user decided DT2, DT3, DT4, DT8, DT9, DT10, DT14, DT15 and DT16 on
2026-09-30; those lines read "Decided 2026-09-30 (user)". DT13 is pending the user's re-decision.

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
contract this producer follows; DT16 amends two rows' rationale), issue #5606 (plans add no new
`.claude/*` config file).

Test strategy: this change is skill prose plus a fixture; there is no new script to drive with
Red-Green-Refactor. Test boundaries, all existing:

- `plugins/mutation-testing/skills/audit/evals/evals.json` and
  `plugins/mutation-testing/skills/setup/evals/evals.json` (prose-graded): new cases.
- `plugins/mutation-testing/scripts/suppression-lint.test.sh` (unchanged; must stay green).
- Skill behavior end to end: live `claude -p` runs of the edited plugin on scratch copies of the
  fixture (Phase 5). Model output is not unit-tested.

### Phase 1: Tool test-restriction probe (DT8) [TODO]

For `stryker-js`, `stryker-net` and `mutmut` (`config-template.md:16` lists the accepted tools),
fetch the current official docs and record the option, if any, that restricts a run to named test
files or test cases, and how that option interacts with the tool's own coverage or dry-run phase.
Write one row per tool to
`docs/specs/tautological-tests-mutation-scope/design/tool-test-restriction.md`:
`| <tool> | <option or none> | <granularity: file, case, none> | <coverage/dry-run interaction> | <keeps no-coverage: yes, no, unknown> | <URL> | <fetched date> |`.
Also record, per ecosystem `setup` detects, the filter form a `test-command` `{tests}` placeholder
needs (DT14). Use `RESEARCH-tools.md` facts only as leads; `tooling.md` rows are known stale
(spec:158-159) and are not a source. A tool with `no` or `unknown` in the no-coverage column is
manual-only under this scope (DT8). stryker4s, pitest and infection are deferred and run under the
manual fallback (DT8; switch condition: a fleet repo adopts Scala, Java or PHP).

**Sanity Check:**

- `grep -cE '^\| (stryker-js|stryker-net|mutmut) \|' docs/specs/tautological-tests-mutation-scope/design/tool-test-restriction.md` returns 3.
- `grep -E '^\| (stryker-js|stryker-net|mutmut) \|' docs/specs/tautological-tests-mutation-scope/design/tool-test-restriction.md | grep -vc 'https://'` returns 0.
- `grep -E '^\| (stryker-js|stryker-net|mutmut) \|' docs/specs/tautological-tests-mutation-scope/design/tool-test-restriction.md | grep -vcE '\| (yes|no|unknown) \|'` returns 0.
- `grep -c '{tests}' docs/specs/tautological-tests-mutation-scope/design/tool-test-restriction.md` is at least 1 (the per-ecosystem `test-command` filter forms).

### Phase 2: Fixture (DT9, DT12, DT13) [TODO]

The fixture, `plugins/mutation-testing/skills/audit/evals/fixtures/exercised-scope/`:

- `app.py`: `price_with_tax` spread over several lines, so the manual protocol's one-mutant-per-line
  operators (SKILL.md:158-163) yield more than one mutant, and a discount branch above a threshold.
- `scenarios/<name>/test_app.py`, one per outcome, snake-case directory names so
  `python -m unittest <path>` imports them: `calls_sut` (survivors, `expected-from-sut`),
  `no_assertion` (survivors, `no-assertion`), `boundary` (the threshold-line mutant is reached and
  survives, `input-gap`), `copied_logic` (no survivor, the blind-spot line), and, only while DT13 is
  pending, `unreached_branch` (the discount-branch mutants are `unreached`, never survivors; at least
  one listed mutant sits on a continuation or header line). If the user folds unreached into
  `input-gap` (DT13), `unreached_branch` is dropped.
- `.claude/mutation-testing.md`: an instance of the existing config file, `tool: manual`,
  `diff-target: main`, `mutate: [app.py]`, `test-command: python -m unittest {tests}`. No `tests`
  key (DT2). How the audit recognizes `test_app.py` as a test depends on the `testing-glob-source`
  answer; under option (a) the shipped `testing` adapters claim `test_*.py`, so no testing config
  file is added.
- `EXPECTED.md`: per scenario, the exact mutants (line, operator) and the expected state, cause and
  (while DT13 stands) sentinel result of each, which the eval cases and the live-run checks read.

**Sanity Check** (with `F=plugins/mutation-testing/skills/audit/evals/fixtures/exercised-scope`):

- `ls "$F/scenarios" | wc -l` returns 5 (4 if DT13 drops `unreached_branch`).
- `for s in "$F"/scenarios/*/; do (cd "$F" && python3 -m unittest -q "scenarios/$(basename "$s")/test_app.py") || echo "red $s"; done` prints no `red` line (every scenario is green on the unmutated `app.py`, so a survivor is never a red baseline).
- `for t in expected-from-sut no-assertion input-gap; do grep -q -- "$t" "$F/EXPECTED.md" || echo "missing $t"; done` prints nothing.
- `grep -c '^tests:' "$F/.claude/mutation-testing.md"` returns 0 and `grep -c '^test-command:' "$F/.claude/mutation-testing.md"` returns 1.

### Phase 3: `test-command` key and setup (DT2, DT14) [TODO]

- `skills/setup/templates/config-template.md`: optional `test-command` key with the `{tests}`
  placeholder, in the existing `.claude/mutation-testing.md`. No `tests` key: test files come from
  the testing config the `testing` scanner reads (DT2).
- `skills/setup/SKILL.md`: `apply` proposes `test-command` per detected ecosystem, for path-list
  runners only (DT14); `check` reports a `test-command` without `{tests}` as a failure.
- `skills/setup/evals/evals.json`: a case where a `test-command` without `{tests}` fails `check`.

This phase waits for the user's answer to `testing-glob-source` (design DT2; Open questions): the
answer decides whether `setup check` also reports a missing `testing` plugin or a missing testing
config layer.

**Sanity Check:**

- `grep -c '^test-command:' plugins/mutation-testing/skills/setup/templates/config-template.md` returns 1 and `grep -c '^tests:' plugins/mutation-testing/skills/setup/templates/config-template.md` returns 0.
- `grep -c '{tests}' plugins/mutation-testing/skills/setup/SKILL.md` is at least 1.
- `python3 -c "import json;d=json.load(open('plugins/mutation-testing/skills/setup/evals/evals.json'));print(sum('test-command' in e['prompt']+e['expected_output'] for e in d['evals']))"` prints at least 1.
- `git diff --name-only --diff-filter=A origin/main | grep '\.claude/' | grep -v 'fixtures/exercised-scope/\.claude/mutation-testing\.md$'` prints nothing (no new `.claude/*` config file).

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
    range plus working tree, test files per the testing config, DT1, DT2), mapping (DT3; zero
    functions ends as `no mapping: scope empty`), effective runner and regime (a verified tool
    restriction, each option with a four-part verification record, else manual with `test-command`
    and DT14's per-path quoting), dirty-target stop on the mapped files, regime gate, one restricted
    baseline run (replacing the full-suite baseline for this scope; red stops), snapshot.
  - The mapping (DT3) is stated as the scope `--exercised` resolves to, the mapped-line set, so a
    later mode can take `--exercised` in place of `--paths`: Release 3's recording run
    (`--record-mutants`, #5604) is the named consumer. 2b adds no recording mode.
  - Phase 1: the trigger (DT4: auto-engage when the committed range plus working tree touches a
    test file and no `mutate` line; the effort cap, `--max` and `max-mutants` apply unchanged; a
    mixed diff prints one line naming `--exercised`). Steps 2 and 3 key on the mapped-line set, and
    step 4's test selection becomes the changed-test set, both stated as divergences (DT1, DT12,
    DT15).
  - Phase 3: each mutant runs against the changed-test set; while DT13 stands, every survivor gets
    one sentinel run, an exit with code 97 inserted before its statement: code 97 is reached, no 97
    is `unreached` (never a survivor), any other failure is reachability `unknown`. No post-loop
    rerun (DT15); the flaky-test gotcha (SKILL.md:335-336) stays.
  - Phase 4: the triage brief hands over the whole changed-test set and adds the cause for
    productive survivors, with a quoted line or `unclassified`, the tie-break rules, and the
    `unknown`-reachability rule (DT5, DT12).
  - Phase 5: coverage and gap from reachability, else `unknown` (DT7); the fixed scope line
    `Scope: exercised (<explicit|auto-engaged>), changed tests as one set`; the fixed blind-spot line
    (DT6).
  - `## Next`: add `A clean exercised run: /testing:test-value.`
- `skills/audit/templates/report.md`: the scope line, a `Cause` column in the Survivors table, an
  `Unreached: <n>` line (while DT13 stands), the blind-spot line.
- `skills/audit/context/persist-findings.md`: the cause leads the `Finding` text and selects the
  `Action` wording; no new rule id and no new column; an `unreached` mutant is never a row.
- `skills/principles/reference/theory.md`, section "What a mutation score is evidence for": one
  paragraph on the copied-logic limit with the Tier 0 matrix, which the audit cites.
- `skills/audit/evals/evals.json`: one case per fixture scenario and one with uncommitted tests.
- `docs/conventions/detector-findings/README.md` (the rationale of the `rule-survivor-productive`
  and `rule-survivor-unclassified` rows, DT16, approved by the user 2026-09-30, with the trigger
  phrase "an input the changed tests do not use") and
  `docs/conventions/detector-findings/CHANGELOG.md`.

No em dashes in new text (the existing `report.md` uses them; do not copy them).

**Sanity Check:**

- `grep -c -- '--exercised' plugins/mutation-testing/skills/audit/SKILL.md` is at least 3.
- `grep -cE 'expected-from-sut|no-assertion|input-gap' plugins/mutation-testing/skills/audit/SKILL.md` is at least 3.
- `grep -c 'no mapping: scope empty' plugins/mutation-testing/skills/audit/SKILL.md` is at least 1.
- `grep -c 'record-mutants' plugins/mutation-testing/skills/audit/SKILL.md` is at least 1 (the mapping named as a scope for Release 3).
- `grep -c 'Scope: exercised (' plugins/mutation-testing/skills/audit/templates/report.md` returns 1.
- `grep -c '| Cause |' plugins/mutation-testing/skills/audit/templates/report.md` returns 1.
- `grep -c 'A clean exercised run: /testing:test-value' plugins/mutation-testing/skills/audit/SKILL.md` returns 1.
- `for s in calls_sut no_assertion boundary copied_logic uncommitted; do grep -q "$s" plugins/mutation-testing/skills/audit/evals/evals.json || echo "missing $s"; done` prints nothing; while DT13 stands, `grep -c unreached_branch plugins/mutation-testing/skills/audit/evals/evals.json` is at least 1.
- While DT13 stands: `grep -c 'os._exit(97)' plugins/mutation-testing/skills/audit/SKILL.md` is at least 1 (the sentinel).
- `test "$(git show origin/main:plugins/mutation-testing/skills/audit/context/persist-findings.md | grep -o 'rule-survivor-[a-z-]*' | sort -u)" = "$(grep -o 'rule-survivor-[a-z-]*' plugins/mutation-testing/skills/audit/context/persist-findings.md | sort -u)"` passes (no new rule id).
- `grep -c 'an input the changed tests do not use' docs/conventions/detector-findings/README.md` returns 2.
- `/skill-quality:check check plugins/mutation-testing` reports no FAIL.
- `git diff origin/main -- plugins/mutation-testing docs/conventions | grep '^+' | grep -cP '\x{2014}'` returns 0 (no em dash added).

### Phase 5: Release housekeeping and live runs [TODO]

- `plugins/mutation-testing/.claude-plugin/plugin.json`: minor bump above main at merge (a new flag
  and one config key); description names the exercised scope.
- `plugins/mutation-testing/CHANGELOG.md` entry; `README.md` names `--exercised` and
  `test-command`.
- Live runs, one per fixture scenario (`calls_sut`, `no_assertion`, `boundary`, `copied_logic`, and
  `unreached_branch` while DT13 stands), plus `calls_sut` with its tests left uncommitted, run as
  `calls_sut_uncommitted`. Each runs in `"${TMPDIR:-/tmp}/tt-mutation-live/<run>/"`, outside this
  checkout so its CLAUDE.md and AGENTS.md do not load into the run. For each: copy `app.py` and
  `.claude/mutation-testing.md`, `git init -b main`, commit both on `main`, then
  `git switch -c tests` and add the scenario's test file (committed, or left uncommitted for the
  variant). Run from that directory:
  `claude -p --permission-mode auto --plugin-dir <worktree>/plugins/mutation-testing "/mutation-testing:audit"`
  (auto mode per `AGENTS.md`, because the audit edits `app.py` and runs Bash; if the
  `testing-glob-source` answer needs the `testing` plugin, also pass
  `--plugin-dir <worktree>/plugins/testing` or confirm the installed `testing` plugin loads) and save stdout as
  `report.md` there. Record the Claude Code version, and confirm from the output that the edited
  plugin (the new version number) loaded rather than the installed one. If the installed copy wins,
  disable it for the run with `claude plugin disable` and re-enable it after. The user allowed that
  user-scope toggle on 2026-09-30; ask at run time before each toggle. Distill the results into this
  phase's notes.

**Sanity Check** (with `L="${TMPDIR:-/tmp}/tt-mutation-live"`):

- `test "$(grep -l 'Scope: exercised (auto-engaged)' "$L"/*/report.md | wc -l)" = "$(ls -d "$L"/*/ | wc -l)"` passes, and `ls -d "$L"/*/ | wc -l` returns 6 (5 if DT13 drops `unreached_branch`).
- `grep -cE '^\| .*\| expected-from-sut \|' "$L/calls_sut/report.md"` is at least 1, and the same for `"$L/calls_sut_uncommitted/report.md"`.
- `grep -cE '^\| .*\| input-gap \|' "$L/boundary/report.md"` is at least 1.
- `grep -cE '^\| .*\| no-assertion \|' "$L/no_assertion/report.md"` is at least 1.
- `grep -cE '^\| [^|]+:[0-9]+ \|' "$L/copied_logic/report.md"` returns 0 (no survivor row) and `grep -c 'copied-logic' "$L/copied_logic/report.md"` is at least 1 (the blind-spot line).
- While DT13 stands: `grep -cE '^Unreached: [1-9]' "$L/unreached_branch/report.md"` returns 1 and `grep -cE '^\| .*\| (expected-from-sut|no-assertion|input-gap) \|' "$L/unreached_branch/report.md"` returns 0.
- `bash scripts/validate-plugins.sh` exits 0.
- `bash scripts/run-plugin-tests.sh` exits 0.
- `bash scripts/check-changelog-parity.sh --check` exits 0.
- `bash scripts/check-changelog-parity.sh --check-bump origin/main` exits 0.
- `bash scripts/check-contract-slice-prune.sh --check-diff origin/main` exits 0.

## Files affected

Created: `plugins/mutation-testing/skills/audit/evals/fixtures/exercised-scope/` (`app.py`, four
`scenarios/*/test_app.py` plus `unreached_branch` while DT13 stands, `.claude/mutation-testing.md`,
`EXPECTED.md`); `docs/specs/tautological-tests-mutation-scope/design/tool-test-restriction.md`.

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
| A `tests` key in `.claude/mutation-testing.md` (DT2 C) | The user's decision (2026-09-30): a second pattern list beside Q6's one list | The user reverses the one-list reading of Q6 |
| Per-test coverage tool for mapping and reachability (DT3 A) | Needs a per-ecosystem coverage command the config does not hold | Phase 1 finds every probed tool keeps its no-coverage state under restriction |
| A cause rule id per survivor cause | The findings contract keys the rule on the disposition alone (persist-findings.md:248-260) | The detector-findings contract adds a sub-classification field |
| Take `bashEditDiff` into 2b (DT10) | The audit reads `git diff` and the working tree, which already see Bash writes | The audit gains a hook-driven mode |
| Two baseline runs plus a post-loop unmutated rerun (DT15, old) | Overengineering review (user, 2026-09-30); the flaky gotcha states the limit | A live run shows a flaky kill |
| Auto-engage cap of the smaller of the effort cap and 15 (DT4, old) | Overengineering review (user, 2026-09-30); the effort cap already bounds the run | Basis: judgment. An auto-engaged run's cost draws a complaint the effort cap did not prevent |
| Probe stryker4s, pitest and infection now (DT8) | Overengineering review (user, 2026-09-30); no fleet repo uses them | A fleet repo adopts Scala, Java or PHP |
| `exercised-fixture.test.sh` self-check and seven scenarios (DT9, old) | Overengineering review (user, 2026-09-30); evals and live runs grade the same states | Basis: judgment. A live run's state for a listed mutant differs from `EXPECTED.md` |

## Risks and mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Static mapping misses a function the tests reach through indirection | Med | Low | Fewer scoped lines, never a false survivor; zero functions ends as `no mapping: scope empty`; the scope report lists the mapped functions |
| Static mapping includes code the changed tests never reach | Med | Low | While DT13 stands, the sentinel run reports those mutants `unreached`; DT13 is pending the user |
| The sentinel insertion breaks parsing or compiling | Med | Low | Reachability becomes `unknown`, never "reached"; DT5's `unknown` rule applies (DT13) |
| No tool can be restricted to named tests | Med | Med | Manual protocol with `test-command` (DT8, DT14), resolved in Phase 0 |
| A flaky changed test kills mutants by accident | Med | Med | One restricted baseline stops on red; the flaky-test gotcha states the limit (DT15). Switch to more runs when a live run shows a flaky kill |
| Auto-engaged runs cost more than expected | Med | Med | The effort cap, `--max` and `max-mutants` apply unchanged; estimate from the restricted baseline (DT4) |
| No testing config layer, so no test-file list to read | High | Med | Open question `testing-glob-source` (DT2); until answered, Phase 3 waits and the exercised scope refuses rather than guessing |
| The cause label is wrong but plausible | Med | Med | Quoted evidence or `unclassified`, tie-break rules (DT5); the fixture's causes are graded by evals and live runs |
| A clean exercised run is read as clearing the tests | High | Med | Fixed blind-spot line in every exercised report (DT6) |
| One language fixture only | High | Low | Recorded: the fixture proves the protocol, not per-language parity; Q12's per-language corpus binds the `testing` scanner rules |

## Blast radius

MEDIUM. One plugin (`mutation-testing`) plus two rationale cells in the shared detector-findings
convention (tier unchanged). Opt-in behavior plus an auto-engage path that fires only on diffs that
produce zero mutants today, under the existing effort cap. No hook, no gate, no other plugin's code
changes. One new optional config key in the existing `.claude/mutation-testing.md`; no new
`.claude/*` file; existing configs keep working for the diff scope.

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
mixed-diff hint count (DA 16). Reviewer 3 (Q6) and reviewer 15 (the spec's Release 2 gate path)
were open questions; the user answered both on 2026-09-30. The single-language fixture (DA 11) is a
recorded risk.

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

Overengineering review (2026-09-30): the user took every recommendation. DT15 runs one restricted
baseline and drops the post-loop rerun; DT4 keeps the effort cap unchanged and a one-line mixed-diff
hint; Phase 1 probes stryker-js, stryker-net and mutmut only; the fixture keeps four scenarios
(plus `unreached_branch` while DT13 is pending) and loses `exercised-fixture.test.sh` and the eval
count gate; DT3's mapping is exposed as a scope for Release 3's recording run. Still pending the
user: DT13 (fold unreached into `input-gap`, defer the sentinel) and DT14's character allowlist
(cut recommended).

Not probed: whether `claude -p --plugin-dir` shadows an installed plugin of the same name (Phase 5
records it at run time).

## Execution shape

Fully sequential: Phase 1 gates Phase 4's effective-runner wiring; Phase 2's fixture gates Phase
4's evals; Phase 3's key gates Phase 4's preflight; Phase 5 closes.

| Phase | Surface | Basis |
|---|---|---|
| 1 | sub-agent worker (research) | bounded doc lookups, one file written |
| 2 | main session | fixture files; the scenario outcomes carry design judgment |
| 3 | main session | small, but waits on the `testing-glob-source` answer |
| 4 | main session | the skill body carries the design judgment |
| 5 | main session | live runs need the edited plugin loaded and a human-readable check |

## Open questions

- `testing-glob-source` (design DT2): the testing config holds only overrides; the base test-file
  globs are the `testing` plugin's shipped adapters, so a repository with no layer file gives
  `mutation-testing` nothing to read. Options: (a) when `testing` is installed, invoke
  `/testing:audit` on the changed files and count a file as a test when an adapter claims it;
  refuse the scope without `testing` (recommended: the only option that sees the list the scanner
  uses today and adds no config); (b) wait for #5606's convention file to carry the full list and
  refuse until then; (c) read only `paths.include` and `extend.*.files` from the layers and refuse
  when none are set. Unblocks Phase 3 and the changed-test set in Phase 4.
- DT13 (reachability sentinel): pending the user's re-decision. The overengineering review
  recommends folding unreached into `input-gap` and deferring the sentinel, because exit-code
  detection likely fails under vitest/jest/dotnet/go workers. Unblocks the final fixture scenario
  count and Phase 4's Phase 3 wording.
- DT14 character allowlist: pending the user; cut recommended. Unblocks Phase 4's manual-regime
  wording.

Decided follow-ups (user, 2026-09-30), no longer open:

- Spec pointer: the next PR that edits `docs/specs/tautological-tests.md` adds a Release 2b line
  (`test -f docs/specs/tautological-tests-mutation-scope/PLAN.md`) to its Release 2 outline Sanity
  Check and points the mutation-scope bullet here. PR #5605 (the Release 2 judge) already rewrote
  the Release 2 gate to `test -f docs/specs/tautological-tests-judge/PLAN.md`.
- `bashEditDiff`: stays deferred (DT10); owner: #5608 (a `testing` hooks follow-up).

## Displaced answers and new external effects

| Q | What the user said | What the plan proposes | New external effect | Source |
|---|---|---|---|---|
| none | Approved (2026-09-30) | A shared-convention edit: the `rule-survivor-productive` and `rule-survivor-unclassified` rationale in `docs/conventions/detector-findings/README.md` | A change to a marketplace-wide convention doc (tier unchanged) | reviewer fix |
| none | Allowed, asked at run time (2026-09-30) | Phase 5 may disable the installed `mutation-testing` plugin for a live run | A user-scope setting change, reverted after the run, asked at run time | reviewer fix |

## Handoff to implementation

Approval: pending the user (unattended run, recommended answers taken; the user decided DT2, DT3,
DT4, DT8, DT9, DT10, DT14, DT15 and DT16 on 2026-09-30)

### User-approval gates

- Plan approval itself, including each "Recommended answer taken unattended (2026-09-30)" in
  `design/design-threads.md` that no "Decided 2026-09-30 (user)" line replaces.
- `testing-glob-source` before Phase 3.
- DT13 and DT14's character allowlist before Phase 4.
- Phase 5: each user-scope plugin toggle, asked at run time.

### Execution shape ([EXEC-SHAPE] tagged)

See "Execution shape" above. One draft PR for Phases 1-5, committed per phase.

| Decision | What it changes in the plan | Basis (evidence) | Source |
|---|---|---|---|
| [EXEC-SHAPE] Sequential phases, one PR | No parallel workers | File overlap: Phases 3-5 all edit `plugins/mutation-testing` skill files | /planning:plan Step 4.5 |
| [EXEC-SHAPE] Phase 1 on a research sub-agent | Keeps doc fetches out of the main context | Phase 1 writes one file and reads only external docs | /planning:plan Step 4.5 |

### Mechanical work

Commit per phase with a Conventional subject scoped `mutation-testing`. Run each phase's Sanity
Check before its commit. A divergence from this plan routes to `/planning:plan review`.
