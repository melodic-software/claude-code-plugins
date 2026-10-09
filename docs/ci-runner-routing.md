# CI runner routing

This repository is public, so every lane runs on GitHub-hosted runners, free for
public repositories: `ubuntu-24.04` for all of them except the informational
Windows lane `test-windows`, which runs `windows-2025` in its own workflow,
`.github/workflows/pr-test-windows.yml`. The organization's
runner-policy engine refuses a governed fleet label here outright, reporting
`public-self-hosted-routing`. There is no observer credential and no
self-hosted exception inventory in this repository.

There is no selector preflight anywhere in the organization any more. ci-perf
Phase 7 deleted the `select-runner` reusable workflow (ci-workflows#569, merged
as `541ee4e90d12d77a90a3ddd72a3af9bc78634ea7`, released as v0.23.0) and
melodic-software/standards#556 (merged as
`771a796628f325c3c418c7b397d09fb7211e2972`) removed its grammar from the
`runner-policy` component. Private repositories now name the governed fleet
label as a literal and nothing routes at run time; this repository is
unaffected, because it was never eligible for the fleet in the first place.
The decision is recorded in melodic-software/github-iac#466, which adds
`docs/adr/0014-fleet-first-ci-for-private-repositories.md`.

## Configuration contract

`.github/runner-policy.json` declares `visibility: "public"` and
`selfHostedCi: false`; the policy engine cross-checks that declaration against
the live repository-visibility evidence on every CI run and fails closed on a
mismatch, so a visibility change must land together with the matching posture
change in this repository's workflows.

Workflow source contains no organization runner label, host name, or GitHub
App identifier. Reviewed reusable workflows from `melodic-software/ci-workflows`
are pinned to the full commit SHA recorded as an approved contract in the
standards-distributed `.github/standards/runner-policy/policy.json`, and each
call passes its `runner` input explicitly (`ubuntu-24.04`). GitHub documents a
full commit SHA as the safest reusable-workflow reference. Dependabot watches
the GitHub Actions dependency, but every executable pin update remains a
reviewed pull request.

## Routing and failure behavior

The `ci-status` required check depends on every **required** workload lane
(`select-tests`, `lint-repo`, `lint-shell`, `check-plugins`, `check-skills`,
`test-bash`, `test-python`, `test-node`) and requires
each result to be `success`, failing closed through execution
(`!cancelled()`, never a success-guard, so a skipped lane cannot report
success to branch protection). The one exception is an ordered skip: a test
lane the change gives no work skips as a job, and `ci-status` counts that skip
as `success` only when `select-tests` succeeded and its row for that lane
(`run_bash`, `run_python`, `run_node`) is `false`; any other skip stays red.
On a draft pull request every lane but
`select-tests` carries a draft gate, so a draft run lints and tests nothing, and its
`ci-status` fails (`draft: lanes not run`) and records `ci-lanes=failure`
(`scripts/check-docs-only-gate.sh` pins both). A green draft would be the
newest `ci-status` on the SHA from the flip to ready until the
`ready_for_review` run's lanes finish, so a merge could land on nothing tested.
The `ready_for_review` run lints and tests the same SHA. `test-windows` is deliberately outside that
aggregate, as an informational platform lane; `pr-test-windows.yml` says so at the
top of the file and warns against wiring it into any required check. It runs in
its own workflow because nothing gates on it and, inside `pr-require-checks.yml`, it was the
longest job in the run: time-to-green is measured to the run's completion, so an
advisory lane was setting the number. Its `on.paths` filters repeat the `shell`,
`python` and `powershell` groups of `pr-require-checks.yml`'s detect-changes table, so a diff
that touches none of them starts no Windows run; the two are kept in step by
hand. Inside a run, its `select-tests-windows` job runs the same planner over the same
diff, and a Windows step runs only when the change selects its suite
(`scripts/test-windows-plan.txt`); a schedule run (09:17 and 16:17 UTC), a
dispatch, and a change to that workflow run every step. The
metadata checks (Conventional Commits title,
`do-not-merge` label, issue linkage) run as the `check-contract` composite step
inside the same `ci-status` job on the same hosted runner, so they no longer
carry status contexts of their own. Fork pull requests receive no secrets and
no automated review, by design.

Jobs are named `<verb>-<domain>` and the job id is the check name: `lint`
runs linters over source, `check` holds a repository contract across files,
`test` executes code. `lint-repo` lints the repository as a whole (text
hygiene, the CI configuration, the docs conventions); `lint-shell` runs
ShellCheck and the gates that read shell source; `check-plugins` holds the
plugin manifests, changelogs, hook declarations, `claude plugin validate`, the
counter ceilings and every shared-library sync; `check-skills` holds the skill
and eval contracts, check 25 included; `test-bash`, `test-python` and
`test-node` run the shell suites, the Python suites and the Node packages the
change selects, and each skips when it has none. A domain is its own job only
when that shortens the critical path by more than a job's fixed cost (about
15 s bare, about 40 s with a toolchain), or, for the test lanes, when it lets a
change that touches none of its ecosystem start no runner for it. Every gate
keeps its step name and its `id`, which is its aggregator key, and each job
carries its own `aggregate-hygiene-results.sh` feed over exactly its own gate
steps.

## What each event tests

The `select-tests` job resolves one diff base, published as `lane_base`, and every
diff-scoped step diffs against it:

- **Pull request:** the base branch. The contract suites are the affected
  selection (`scripts/affected-tests.sh`), and ShellCheck lints the changed
  shell files.
- **Merge group:** the queue's base commit
  (`github.event.merge_group.base_sha`), so the lanes run what the group's own
  diff selects, as on its pull request. A group whose diff touches a plugin or
  marketplace manifest, as a release does, tests the whole tree. The queue merges a commit only after
  this run passed on it, so main's commits carry its checks. The
  detect-changes groups read only a pull request's files and report true here;
  the check-25 scan diffs its own inputs instead.
- **Push to `main`:** no run, in `pr-require-checks.yml` or
  `pr-test-windows.yml`. Every commit reaches `main` through the merge queue,
  whose merge-group run already tested that SHA.
- **Schedule (09:17 and 16:17 UTC, two of the workflow's quietest hours) and
  dispatch:** the whole tree. That means
  the full contract corpus, the whole-repository ShellCheck, and the check-25
  scan over every skill. This run catches what a diff cannot show: a suite that
  asserts against the live tree, or a dependency the selector does not see.

Whole-tree gates whose verdict depends only on their own inputs are scoped the
same way on a diff: markdownlint lints the changed markdown (its download is
cached), the eval-quality lint reads the eval set of every skill directory the
diff touched (a set's `files` entries resolve anywhere in it), `claude plugin
validate` runs for the touched plugins, the manifest and workflow schemas run
when their filter group matched, and the skill-count, eval-coverage and
fixture-isolation scans skip when none of their inputs changed. Each falls back
to the whole tree when there is no diff base or `pr-require-checks.yml` changed, and the
scheduled run scans everything. Replayed on 20 recent pull requests, every
skipped or narrowed scan landed on a whole-tree success.

`select-tests` also plans the test lanes, once, with `scripts/plan-test-lanes.sh`:
each selected suite goes to the lane of its ecosystem (a Node suite with a
sibling `.test.sh` runs through it in `test-bash`), `test-bash` gets one to six
legs of about 120 suite-seconds each and `test-python` one to four of about
180, packed longest first from the measured seconds in
`scripts/suite-seconds.txt`, and each leg installs only the optional toolchains
(the animation wheels, the inventory's parser packages, the DuckDB CLI) its
suites need. `test-node` runs the Node packages the change reaches. An
UNMAPPED code file adds the whole corpus of its language; unmapped data adds
nothing, since no suite reads it, and is still counted. A Python pin runs every
Python suite, a Node pin every Node package, and a change to
`pr-require-checks.yml` or `.github/actions/download-full-history/` every suite
of every lane. `lint-shell` skips when the change touches none of its inputs
(the `lint_shell` filter group: shell and Python source, hook and bin
directories, skill and agent markdown, its gates and their baselines).

A suite that scans a directory never names the file that changed, so it
declares what it reads in a `# test-scope:` header, and the selector's rule R8
selects it for any changed file matching the glob. The rules, and the
`--replay` mode that shows a selector change's effect on recent main commits,
are in the header of `scripts/affected-tests.sh`.

## Contract-only `ci-status`

A same-repo `edited` (without `changes.base`), `labeled`, or `unlabeled` event
runs `ci` as contract-only: every lane job is gated off and `ci-status` reads
the `ci-lanes` commit status on the head SHA once, with no wait
(`carry-forward-wait-seconds: '0'`, a 3-minute job). It passes only when the
newest status the Actions bot wrote is `success`.

No run waits on another run:

1. A full run's `select-tests` job first writes `ci-lanes=pending` on the head SHA.
   A contract-only run that reads it goes red at once instead of carrying an
   older verdict forward while the lanes are in flight. Before its marker is
   written, the full run is queued or in progress on the SHA, and the
   contract-only run goes red at once on that too: one runs listing, where a
   sibling whose `select-tests` job was skipped (contract-only) or whose `ci-status`
   job has started (writing its verdict) does not count.
2. The full run's own `ci-status` check run appears only when its lanes finish.
   It is newer than the red one, and the newest same-name check run is the one
   the merge gate reads: three merged pull requests kept an older, never
   re-run red contract-only `ci-status` beside a newer green one, and the
   `ci-gate` ruleset has no bypass actors.
3. After recording `success`, the full run's `ci-status` re-runs the failed
   jobs of every red contract-only run on the same SHA (`rerun-failed-jobs`,
   `actions: write`). The re-run keeps its event, so it is contract-only again,
   reads `success` and replaces the red check run within seconds. That
   includes a run drawn while the pull request was a draft: its payload still
   says draft, so `Fail a draft` reads the live draft state on a contract-only
   run and passes once the pull request is ready
   (`scripts/ci-fail-a-draft.test.sh`).

A red contract-only run also stays red when its contract fails (an invalid
title or a `do-not-merge` label). That is the intended answer.

**Operator remedy.** When a contract-only `ci-status` is still red after the
full run finished:

- If `ci-lanes` on that SHA is `success` and the pull-request contract passes
  (valid title, no `do-not-merge` label), re-run the red contract-only `ci`
  run. This covers a contract-only run that was still in progress when the full
  run listed its siblings. The composite logs
  `Carried forward: ci-lanes is success`, passes, and the re-run replaces the
  red check run. Pushing a new commit is not needed.
- If the title is invalid or `do-not-merge` is applied, the contract check
  stays red on a re-run. Fix the title or remove the label first, then follow
  the other bullets for `ci-lanes`.
- If `ci-lanes` is `failure`, `pending` with no full run in flight, or missing,
  re-run the full workflow. On a draft, mark it ready instead.

## Toolchain integrity

The plugin-gate toolchain is identical everywhere it runs. Node executables
are integrity-locked in `package-lock.json`, Ruff is pinned to the Ubuntu x64
wheel and SHA-256 in `.github/requirements-ci.txt`, and Dependabot tracks both
dependency roots. CI consumes those manifests with `npm ci` and hash-required
`pip`, never mutable global installs.

### Local / workstation ruff

Do **not** trust a bare `ruff` on `PATH` for verification in this repository.
A workstation `ruff` at a different version from the one CI installs disagrees
with CI in both directions: it reports findings on an unmodified `main` tree
that CI accepts, and misses findings CI raises. A release can move a rule into
or out of the default set, as 0.16.0 did for eighteen `E`/`F` rules.
Resolve the tool from the pin instead of from `PATH`:

```shell
scripts/run-ruff.sh check <paths>
# equivalent: uvx ruff==$(awk '/^ruff==/{sub(/^ruff==/,""); sub(/[[:space:]\\].*$/,""); print; exit}' .github/requirements-ci.txt) check <paths>
```

`scripts/run-ruff.sh` uses a PATH `ruff` only when it already reports the pinned
version (the CI install path); otherwise it runs `uvx ruff==<pin>`. Plugin
contract tests that lint Python (`engine.test.sh`) invoke that wrapper. The pin
is read at run time, so the wrapper follows the repository's version wherever it
goes and carries no copy of its own.

Bumping the pin is a deliberate Dependabot change, and its direction is set
elsewhere: the pin is held equal to the fleet inventory in
melodic-software/dotfiles (`.chezmoidata/uv-tools.yaml`), which is what installs
a developer's local toolchain, so CI never lints with a ruff nobody runs. Do not
"fix" a clean tree by adopting a newer ruff's new rules in an unrelated PR.

## Time-to-green

The standing target is a p50 under 5 minutes and a p95 under 12 minutes per
pull-request head SHA, measured to the first successful full run of the
required workflow (`ci-status`); contract-only runs are excluded. This
repository owns the target, tracked on #3932.

## Authoritative references

- [Reuse workflows and pin a commit SHA](https://docs.github.com/en/actions/how-tos/reuse-automations/reuse-workflows)
- [Reusable workflow runner and permission behavior](https://docs.github.com/en/actions/reference/workflows-and-actions/reusing-workflow-configurations)
- [`merge_group` and required checks](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#merge_group)
- [Dependabot configuration options](https://docs.github.com/en/code-security/reference/supply-chain-security/dependabot-options-reference)
