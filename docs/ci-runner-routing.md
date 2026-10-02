# CI runner routing

This repository is public, so every lane runs on GitHub-hosted runners, free for
public repositories: `ubuntu-24.04` for all of them except the informational
Windows lane `test-windows`, which runs `windows-2025` in its own workflow,
`.github/workflows/test-windows.yml`. The organization's
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
(`changes`, `lint`, `lint-2`, `test-linux`, `hook-utils`) and requires
each result to be `success`, failing closed through execution
(`!cancelled()`, never a success-guard, so a skipped lane cannot report
success to branch protection). The one exception is a draft pull request:
every lane but `changes` carries a draft gate, so a draft run lints and tests
nothing, and `ci-status` passes `skipped` on a draft and nowhere else
(`scripts/check-docs-only-gate.sh` pins both). The `ready_for_review` run
lints and tests the same SHA before the pull request can merge. `test-windows` is deliberately outside that
aggregate, as an informational platform lane; `test-windows.yml` says so at the
top of the file and warns against wiring it into any required check. It runs in
its own workflow because nothing gates on it and, inside `ci.yml`, it was the
longest job in the run: time-to-green is measured to the run's completion, so an
advisory lane was setting the number. It re-derives its own `run_windows` from
the same detector and the same two filter groups `ci.yml` uses, because job
outputs do not cross workflow files; the two rows are kept byte-identical. The
metadata checks (Conventional Commits title,
`do-not-merge` label, issue linkage) run as the `pr-contract` composite step
inside the same `ci-status` job on the same hosted runner, so they no longer
carry status contexts of their own. Fork pull requests receive no secrets and
no automated review, by design.

`lint` and `lint-2` are two halves of one hygiene lane, split across two
runners and balanced on measured wall time; every gate keeps the name it always
had, and each half carries its own `aggregate-hygiene-results.sh` feed over
exactly its own gate steps. ShellCheck runs in `hook-utils` with a one-row feed
of its own, so its whole-repository scan does not set `lint`'s wall time.

## What each event tests

The `changes` job resolves one diff base, published as `lane_base`, and every
diff-scoped step diffs against it:

- **Pull request:** the base branch. The contract suites are the affected
  selection (`scripts/affected-tests.sh`), and ShellCheck lints the changed
  shell files.
- **Push to `main`:** the commit of the newest green `ci` push run that HEAD
  descends from, not HEAD's parent. A push run that went red, or was dropped
  while pending, leaves its commits in the next run's range, so a break stays
  red until a run passes. Push runs coalesce: one runs and only the newest
  waits. With no such run among the last 50, or a range that touches the
  shared test machinery (`ci.yml`, `.github/actions/`, the suite runner and
  selector, `scripts/lib/`, the toolchain pins), the push tests the whole tree.
- **Schedule (05:17 and 17:17 UTC) and dispatch:** the whole tree. That means
  the full contract corpus, the whole-repository ShellCheck, and the check-25
  scan over every skill. This run catches what a diff cannot show: a suite that
  asserts against the live tree, or a dependency the selector does not see.

Whole-tree gates whose verdict depends only on their own inputs are scoped the
same way on a diff: markdownlint lints the changed markdown (its download is
cached), the eval-quality lint reads the changed eval sets, `claude plugin
validate` runs for the touched plugins, the manifest and workflow schemas run
when their filter group matched, and the skill-count, eval-coverage and
fixture-isolation scans skip when none of their inputs changed. Each falls back
to the whole tree when there is no diff base or `ci.yml` changed, and the
scheduled run scans everything. Replayed on 20 recent pull requests, every
skipped or narrowed scan landed on a whole-tree success.

The selector's rule R8 covers the gap a full main run used to cover: a change
anywhere under `plugins/<p>/` also selects every shell suite under that plugin,
because suites that scan their own plugin directory never name the file that
changed.

## Contract-only `ci-status`

A same-repo `edited` (without `changes.base`), `labeled`, or `unlabeled` event
runs `ci` as contract-only: every lane job is gated off and `ci-status` reads
the `ci-lanes` commit status on the head SHA once, with no wait
(`carry-forward-wait-seconds: '0'`, a 3-minute job). It passes only when the
newest status the Actions bot wrote is `success`.

No run waits on another run:

1. A full run's `changes` job first writes `ci-lanes=pending` on the head SHA.
   A contract-only run that reads it goes red at once instead of carrying an
   older verdict, such as a draft run's, forward while the lanes are in flight.
2. The full run's own `ci-status` check run appears only when its lanes finish.
   It is newer than the red one, and the newest same-name check run is the one
   the merge gate reads: three merged pull requests kept an older, never
   re-run red contract-only `ci-status` beside a newer green one, and the
   `ci-gate` ruleset has no bypass actors.
3. After recording `success`, the full run's `ci-status` re-runs the failed
   jobs of every red contract-only run on the same SHA (`rerun-failed-jobs`,
   `actions: write`). The re-run keeps its event, so it is contract-only again,
   reads `success` and replaces the red check run within seconds.

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
  re-run the full workflow.

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
