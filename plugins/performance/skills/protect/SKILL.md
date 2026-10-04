---
description: "Lock in a verified performance win: ratchet its counter in CI with a checked-in ceiling, so a regression fails the build and a lower count proposes a lower ceiling by PR. Proposes files; a human approves and merges. Use when: 'protect this win', 'ratchet this counter', 'stop this regressing', 'add a performance guardrail to CI'. Runs once after /performance:verify reports MET on a counter. Skip when the result is a duration only, or NOT MET."
user-invocable: true
argument-hint: "[<counter or claim>]"
disable-model-invocation: false
metadata:
  workflow-stage: verify
  summary: Hold a verified counter win with a CI ceiling a human merges
---

**Arguments.** `[<counter or claim>]`. e.g. /performance:protect the 4-to-1 spawn reduction

## Purpose

Answers **"what keeps this win from eroding?"**

Performance wins decay in a codebase that keeps moving: nothing asserts the new cost, so the next
change that adds it back passes every test. A checked-in counter ceiling, checked in CI, turns the
win into a build failure the next regression has to answer.

Run it once, after `/performance:verify` reports **MET** on a counter. For a change shipped behind
a flag, run it only after the field read that verify's Next routes to shows the gain; if the read
shows no gain, turn the flag off instead. It proposes files; a human approves them. It never
merges, and no model runs in CI: the check is a script and a number.

Read [`${CLAUDE_PLUGIN_ROOT}/reference/techniques.md#g-protect-the-win`](${CLAUDE_PLUGIN_ROOT}/reference/techniques.md#g-protect-the-win)
for the technique entries this skill applies.

## 1. Choose the counter

- **Counters only, never durations.** A duration ceiling moves with runner load, fails at random,
  and teaches people to raise it. Ratchet the headline counter from the verify report.
- **Measure it in the state CI will see.** A counter behind a cache has a cold value and a warm
  value; a guard with a per-user cache can count 6 spawns cold and 1 warm. CI runners start cold, so
  a ceiling measured warm fails there. Pin the state in the command (unset or empty the cache
  location), and measure that.
- **It must be deterministic.** `ratchet.py add` measures twice by default and refuses a counter
  whose runs disagree (`${CLAUDE_PLUGIN_ROOT}/reference/harness-integrity.md` rule 1). `--runs N`
  sets the run count, at least 1. Fix what varies before ratcheting.
- **A vendored copy may predate `--runs`.** A copy of `ratchet.py` from before plugin 0.5.0 exits 2
  on it. Re-copy `ratchet.py`, `ab.sh` and `summarize.py` from `${CLAUDE_PLUGIN_ROOT}/scripts/`
  before using the new flags.

## Who writes the ceiling

Check whether `/review:ratchet` is among the available skills in this session.

- **It is available:** hand it the counter's name, command, field and goal (with its Correlation
  value), and skip §2-§4 here. It picks the ceilings file the repository's CI already checks, or
  proposes one, and writes the CI step and the tightening plan. Then continue at §5.
- **It is not available:** run §2-§4 below against `.performance/ratchets.json` with
  `${CLAUDE_PLUGIN_ROOT}/scripts/ratchet.py`. Nothing here needs the review plugin.

Either way, the Output block names the ceilings file and which path ran.

## 2. The ceilings file

Propose `.performance/ratchets.json`, created by
`python3 ${CLAUDE_PLUGIN_ROOT}/scripts/ratchet.py add --name <n> --field <f> --goal <g> --command <cmd>`
from the repository root:

```json
{"counters": [{"name": "guard-spawns", "command": "<shell command>", "field": "spawns",
               "ceiling": 6, "goal": "<the verified goal this protects>. Correlation: unproven: <reason>"}]}
```

- `command` runs through the shell from the repository root and prints a `<field>=<number>` token.
- `--goal` names the verified goal and ends with the goal's Correlation value, copied as
  `Correlation: <pointer>` or `Correlation: unproven: <reason>`.
- **The command must exit non-zero when the subject fails.** A subject that errors out early spends
  fewer spawns and passes any ceiling. `spawn-census.sh` exits 0 whatever the subject did and prints
  `rc=<n>`, so append `| grep -F ' rc=0 '`.
- The ceiling is the measured value, never a round number above it. Headroom is room for a
  regression.
- CI has no plugin installed, so the proposal vendors `ratchet.py` (one stdlib file) into the
  repository, for example `.performance/ratchet.py`, unless the repository already carries it.

### Telemetry-derived counters

A count that lives in a telemetry store (spans, events, a log) is measured by a command that
flushes, queries, and prints the token itself; `ratchet.py` only runs the command and parses stdout.

```json
{"name": "tool-calls", "field": "calls", "ceiling": 12,
 "goal": "<the verified goal this protects>. Correlation: <pointer>",
 "command": "id=$(uuidgen); RUN_ID=$id ./run-subject.sh && ./flush-exporter.sh && ./count-run.sh $id"}
```

- **Scope the query to the run the command started**, by an id it generates, never a time window.
  A late batch from the previous run lands in a window and inflates the count.
- **Exit non-zero when the run record is missing, not when the count is zero.** `count-run.sh` is
  the counter's query step: it checks for a completion record the subject emits for that id and
  exits non-zero without it, so lost telemetry fails the command instead of reading as 0. With the
  record present it prints `calls=<n>`, and `calls=0` is valid, since a zero ceiling is legitimate.
  The subject's own failure must also fail the command.
- **Force the exporter to flush, or poll until the run's record is complete, before printing.**
  `add` and `propose-tighten` measure twice by default, and `--runs` tunes the count. A read taken
  before the flush sees a partial count: the runs disagree and `add` refuses, or all read partial
  values, agree, and set a ceiling that is too low.
- **CI needs the store.** `check` exits 2 when the command fails, and a runner with no telemetry
  store fails it. Either the CI job stands up the store and exporter so the command is
  self-contained, or the counter is re-expressed as a count the command prints directly. Otherwise
  leave it out of the required ratchet.
- The store query lives in the counter command. `ratchet.py` takes no telemetry dependency.

## 3. The CI check

`ratchet.py check` exits `0` at or below every ceiling, `1` when a counter is above its ceiling
(naming it), and `2` when it could not measure. Any CI that runs a command and reads its exit status
can host it. GitHub Actions:

```yaml
      - name: Check performance counter ceilings
        run: python3 .performance/ratchet.py check --file .performance/ratchets.json
```

Put the step inside the check the repository already requires for merge. A ratchet outside the
required check reports red and blocks nothing.

## 4. Tightening

When a counter drops, the ceiling drops with it, or the next regression can climb back to the old
ceiling unnoticed. `check` prints `propose-tighten can lower it` whenever a counter sits below its
ceiling; `propose-tighten --write` records the lower value and never raises one.

- **Counter moves only when code changes it:** tighten in the same PR. No schedule is needed.
- **Counter can fall without a PR touching it** (a dependency upgrade, a data-driven count, a
  nightly rig): propose a scheduled job that opens a draft PR and stops there.

The proposed workflow file is the setting: keep it to tighten on a schedule, delete it to tighten by
hand.

```yaml
on:
  schedule:
    - cron: "17 6 * * 1"
  workflow_dispatch:
permissions: {}
jobs:
  measure:
    runs-on: ubuntu-24.04
    permissions:
      contents: read
    outputs:
      ceilings: ${{ steps.tighten.outputs.ceilings }}
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
      - id: tighten
        run: |
          python3 .performance/ratchet.py propose-tighten --write
          git diff --quiet -- .performance/ratchets.json && exit 0
          echo "ceilings=$(jq -c . .performance/ratchets.json)" >> "$GITHUB_OUTPUT"
  open-pr:
    needs: measure
    if: needs.measure.outputs.ceilings != ''
    runs-on: ubuntu-24.04
    permissions:
      contents: write
      pull-requests: write
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
      - env:
          GH_TOKEN: ${{ github.token }}
          CEILINGS: ${{ needs.measure.outputs.ceilings }}
        run: |
          jq . <<<"$CEILINGS" > .performance/ratchets.json
          git switch -c "ratchet/tighten-$GITHUB_RUN_ID"
          git -c user.name="github-actions[bot]" \
            -c user.email="41898282+github-actions[bot]@users.noreply.github.com" \
            commit -am "perf: lower counter ceilings"
          git push origin HEAD
          gh pr create --draft --fill
```

The counter commands run in `measure`, which holds a read-only token and no stored git credentials,
because a counter can exercise third-party code; only `open-pr`, which runs no counter, can write.

A workflow's `GITHUB_TOKEN` can open that PR only when the repository setting "Allow GitHub Actions
to create and approve pull requests" is on, and it is off by default for a new personal-account
repository; the PR's `opened` event then creates workflow runs in an approval-required state, so a
human approves the checks as well as the merge. To have the checks start without that approval,
open the PR with a GitHub App installation token or a personal access token stored as a secret
instead of `GITHUB_TOKEN`. Verified 2026-09-24 against
`https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/enabling-features-for-your-repository/managing-github-actions-settings-for-a-repository`,
`https://docs.github.com/en/actions/concepts/security/github_token`, and
`https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/trigger-a-workflow`.
Recheck when any of them stops naming that setting or changes what a `GITHUB_TOKEN`-created pull
request event triggers.

## 5. Guardrails for fragile optimizations

A ratchet guards a count, not correctness. Guardrails scale with how brittle the optimization is:

- **A fast path that copies a slow one** (a static placeholder, a precomputed table, a cache): generate
  the copy from the source, and add a test that fails when the two drift.
- **A fast path that must match the real one:** keep verify's differential as a standing test, over
  every mode and configuration it covered.
- **A handoff between two implementations:** a test that drives input through the switch and fails
  on anything lost or reordered.

Propose these beside the ratchet. The ratchet alone passes a subject that got cheaper by breaking.

## 6. Win decay the ratchet does not see

- **A new path around the counted one.** The counter measures the path its command drives. Code
  that reaches the same cost another way is invisible to it.
- **A command that drifts from production.** A counter command that copies a hook list or a config
  keeps measuring the copy after production changes. Name the source it copies in `goal`.
- **A raised ceiling.** Raising one is a decision, stated with its reason in the PR body, never an
  edit made to turn a build green.

## Output

```text
Counter:   <name> = <measured> (<field>), deterministic across <runs> runs
Ceiling:   <value> in <ceilings file>, written by <review:ratchet | protect §2-§4>
Protects:  <goal>. Correlation: <goal's value>
CI step:   <workflow file and job>                   Required check: <name>
Tighten:   same-PR | scheduled draft PR (<workflow file>)
Guardrails proposed: <tests, or none needed and why>
Awaiting:  human approval of the files above
```

## Boundary

- **Does not measure the win.** `/performance:snapshot` captures and `/performance:verify` proves it;
  this protects a result already MET.
- **Does not merge,** under any autonomy setting, and its scheduled job only opens a draft PR.
- **Does not commit durations.** Only counter ceilings are checked in.
- **Does not run a model in CI.**

## Next

- The counter still needs its ceiling, CI step and tightening plan: `/review:ratchet`
- A human approved the proposed files: `/source-control:pull-request`

## Gotchas

- **A ratchet on a counter measured warm fails on every fresh runner.** Measure in CI's cache state.
- **A command that swallows the subject's failure passes the ratchet.** Fewer spawns is also what a
  crash looks like; make the command fail with the subject.
- **A ratchet outside the required check blocks nothing.** It turns red in the run list while the
  merge gate stays green.
- **Headroom in a ceiling is a pre-approved regression.** Set it to the measured value.
- **A scheduled tighten job that merges is out of bounds.** It opens a draft PR; a human merges.
