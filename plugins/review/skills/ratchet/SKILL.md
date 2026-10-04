---
description: "Freeze a counter at today's value as a checked-in CI ceiling, so a rise fails the required check and a fall lowers the ceiling by PR: a lint rule's violation count, a suppression count, a verified performance counter, or a telemetry count. A zero count lands the rule with no ceiling. Counters only, never durations. Proposes files; a human approves and merges. Use when: 'ratchet this lint rule', 'freeze the violation count', 'add a count ceiling to CI', 'stop this count from growing', 'ratchet the suppressions'."
user-invocable: true
argument-hint: "[<counter, rule or claim>]"
disable-model-invocation: false
allowed-tools: ["Bash(python3 ${CLAUDE_SKILL_DIR}/scripts/ratchet.py:*)", "Bash(python3 \"${CLAUDE_SKILL_DIR}/scripts/ratchet.py\":*)", "Bash(git grep:*)", "Bash(git ls-files:*)"]
metadata:
  workflow-stage: review
  summary: Hold a count in CI with a checked-in ceiling a human merges
---

**Arguments.** `[<counter, rule or claim>]`. e.g. /review:ratchet the no-floating-promises rule

## Purpose

Answers **"how do we stop this count from growing while we pay it down?"**

A new lint rule with 300 existing violations cannot fail the build today, and a rule that does not
fail the build lets violation 301 in. A ceiling fixed at today's count fails the next change that
adds one, while the existing ones are fixed at whatever pace the team picks. Each fix lowers the
ceiling, so the count only moves down.

The check is `scripts/ratchet.py` (one standard-library file) and a number: no model runs in CI.
This skill writes the proposed files into the working tree and commits nothing. It never merges.

## 1. Take the counter

The counter arrives from one of four places:

| Source | What it hands over |
|---|---|
| `/performance:protect` | a verified counter: name, command, field, and the goal with its Correlation value |
| an enforcement stub's ratchet offer from `/review:audit-enforceability` | a lint rule and a command that counts its violations |
| `/code-metrics:audit-suppressions`, when that skill is available | a command that prints the suppression count |
| the user, from a telemetry store | a command that queries one run's count and prints it |

Each needs a command that prints a `<field>=<number>` token on stdout, run through the shell from
the repository root.

- **Counters only.** A wall-clock time, a latency percentile or a memory high-water mark moves with
  the host, so a ceiling on it fails at random and trains people to raise it. Refuse it and name a
  count that moves only when the code does (calls, queries, spawns, violations). When none exists,
  say so: there is nothing to ratchet yet.
- **The command fails when its subject fails.** A linter that cannot parse its config reports no
  violations; a crashed program spends fewer calls. Either one passes any ceiling. Make the command
  exit non-zero in that case: check the linter's own exit status, or filter on the subject's status.
- **Measure in CI's state.** A count behind a cache reads lower on a warm machine than on a fresh
  runner. Pin the cache state in the command (unset or empty its location) before measuring.

## 2. Zero lands the rule

Run the command once. A lint count of `0` needs no ceiling: turn the rule on at error severity in
the linter's config so the build fails on the first violation, and stop. Report that the rule
landed and that no ceilings entry was written.

A suppression count of `0` lands the same way only when the tool has a rule that forbids the
suppression comment itself (for example an ESLint rule that reports every disable directive): turn
that rule on at error severity. When no such rule exists, nothing in the linter fails on the first
new suppression, so ratchet the count at `0` like any other counter.

A counter from `/performance:protect` with a value of `0` is also ratcheted at `0`, since no linter
stands behind it.

A non-zero lint count keeps the rule from failing the build by itself (warning severity, or the
rule run in its own linter invocation): the ceiling is what fails it.

## 3. The ceilings file

Add to the file the repository's CI already checks. Find the calls with
`git grep -n -E 'ratchet\.py.{0,2} check'`, which covers workflow files and any script they run:

- **A `check` call with `--file <path>`:** add to `<path>`, and use the `ratchet.py` that call runs.
- **A `check` call with no `--file`:** the file is `.performance/ratchets.json`, the script's
  default, with the vendored script at the path the call names (usually `.performance/ratchet.py`).
  Add to it; propose no second file.
- **Calls naming different files:** ask which file this counter joins.
- **No call:** propose `.ratchets.json` at the repository root and vendor `ratchet.py` beside it.
  Every `add`, `check` and `propose-tighten` call then passes `--file .ratchets.json`, because the
  script's own default is the `.performance/` path.

CI has no plugin installed, so the repository carries its own copy of the script. Vendor
`${CLAUDE_SKILL_DIR}/scripts/ratchet.py` without its first two lines (the generated-file header),
unless the repository already carries one. A vendored copy older than the `--runs` flag exits 2 on
it: refresh the copy before using that flag.

**A suppression counter** needs the scanner in CI too. Vendor
`${CLAUDE_SKILL_DIR}/scripts/suppression-scan.py` beside the vendored `ratchet.py`, also without its
first two lines, and make the counter command run that copy with `--count`, for example
`python3 <dir>/suppression-scan.py --count`. It prints `suppressions=<n>` and `unjustified=<n>`;
ratchet `unjustified` to stop new suppressions without a reason, or `suppressions` to stop any new
one. With no path it reads every file git does not ignore, so a fresh checkout counts exactly what
was committed. The vendored scanner needs Python 3.11 or later and exits 2 with a one-line message
below it, so the CI job must provide that version.

## 4. Record the ceiling

```bash
python3 "${CLAUDE_SKILL_DIR}/scripts/ratchet.py" add --file <ceilings file> \
  --name <name> --field <field> --command '<command>' --goal '<goal>'
```

- `add` runs the command twice by default and refuses a counter whose runs disagree. `--runs N`
  changes the count (at least 1). A counter that varies on an unchanged tree fails at random; fix
  what varies first.
- The ceiling is the measured value. A ceiling above it is room for a regression to land unnoticed.
- `--goal` says what the ceiling protects. For a lint rule: the rule id and the direction ("no new
  `no-floating-promises` violations; fix existing ones down to 0"). For a counter from
  `/performance:protect`: the verified goal, ending with its Correlation value exactly as protect
  passed it.

### Telemetry counters

The command flushes the store, queries the run it started, and prints the token; `ratchet.py`
only runs the command and reads stdout.

- **Query by a run id the command generates,** never a time window: a late batch from an earlier
  run lands inside a window.
- **Fail when the run's completion record is missing.** Lost telemetry must not read as `0`; a
  real `0` with the record present is a valid count.
- **Flush, or poll until the record is complete, before printing.** `add` measures more than once;
  a read taken before the flush gives a partial count.
- **CI needs the store.** `check` exits 2 when the command fails. Either the CI job starts the
  store and its exporter, or the counter stays out of the required check.

## 5. The CI step

`check` exits `0` at or below every ceiling, `1` naming each counter above its ceiling, and `2`
when it could not measure. Add one step inside the job the repository requires for merge (branch
protection or a ruleset names it; ask when neither can be read):

```yaml
      - name: Check count ceilings
        run: python3 <vendored ratchet.py> check --file <ceilings file>
```

When the repository already has a `check` step for this file, add nothing: the new entry is
checked by it. A step in a job that is not required turns red and blocks nothing.

## 6. Tightening

`check` prints `propose-tighten can lower it` when a counter sits below its ceiling.
`propose-tighten --write` records the lower value and never raises one.

- **The count drops only when code changes it** (a lint rule, a suppression count): tighten in the
  same PR that fixed the violations. No schedule.
- **The count can drop with no PR touching it** (a dependency upgrade, a data-driven count): propose
  a scheduled workflow that opens a draft PR and stops. Keeping the file is the setting; deleting it
  means tightening by hand.

```yaml
on:
  schedule:
    - cron: "41 5 * * 2"
  workflow_dispatch:
permissions: {}
jobs:
  measure:
    runs-on: ubuntu-24.04
    permissions:
      contents: read
    outputs:
      ceilings: ${{ steps.lower.outputs.ceilings }}
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
      - id: lower
        run: |
          python3 <vendored ratchet.py> propose-tighten --file <ceilings file> --write
          git diff --quiet -- <ceilings file> && exit 0
          echo "ceilings=$(jq -c . <ceilings file>)" >> "$GITHUB_OUTPUT"
  draft-pr:
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
          jq . <<<"$CEILINGS" > <ceilings file>
          git switch -c "ratchet/lower-$GITHUB_RUN_ID"
          git -c user.name="github-actions[bot]" \
            -c user.email="41898282+github-actions[bot]@users.noreply.github.com" \
            commit -am "chore: lower count ceilings"
          git push origin HEAD
          gh pr create --draft --fill
```

The counter commands run in `measure`, with a read-only token and no stored credentials, because a
counter can run third-party code. Only `draft-pr`, which runs no counter, can write.

A `GITHUB_TOKEN` opens that PR only when the repository allows workflows to create pull requests,
which is off by default for a personal-account repository, and runs on such a PR wait for a human's
approval. A GitHub App token or a personal access token stored as a secret avoids the wait.

- **Pointer:** [Managing GitHub Actions settings for a repository](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/enabling-features-for-your-repository/managing-github-actions-settings-for-a-repository)
  and [GITHUB_TOKEN](https://docs.github.com/en/actions/concepts/security/github_token).
- **As of:** 2026-10-04.
- **Recheck trigger:** either page renames the "Allow GitHub Actions to create and approve pull
  requests" setting or changes what a `GITHUB_TOKEN`-created pull request triggers.

## Output

```text
Counter:   <name> = <measured> (<field>), agreed across <runs> runs | 0: rule landed, no ceiling
Ceiling:   <value> in <ceilings file> (<existing | new>)    Script: <vendored ratchet.py path>
CI step:   <workflow file and job>                         Required check: <name>
Tighten:   same-PR | scheduled draft PR (<workflow file>)
Files:     <each proposed file, uncommitted>
Awaiting:  human approval of the files above
```

## Boundary

- **Does not choose the rule.** `/review:audit-enforceability` proposes rungs; this holds a count
  once a rule or counter exists.
- **Does not prove a performance win.** `/performance:verify` does; this takes the verified counter.
- **Does not commit, push or merge,** under any autonomy setting. The scheduled job opens a draft
  PR and stops.
- **Does not check in a duration** or run a model in CI.

## Next

`/source-control:pull-request` with the approved files.

## Gotchas

- **A second ceilings file splits the check.** Add to the file CI already checks; a new file needs
  its own step, and one that never gets it is never checked.
- **A call that omits `--file` uses `.performance/ratchets.json`.** In a repository whose ceilings
  are in `.ratchets.json`, `add` starts a second file there and `check` exits 2 because that path
  does not exist.
- **A raised ceiling is a decision.** State the reason in the PR body; never raise one to turn a
  build green.
- **A count measured warm fails on every fresh runner.** Pin the cache state in the command.
