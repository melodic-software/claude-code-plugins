# CI runner routing

This repository is public, so every lane runs on GitHub-hosted runners, free for
public repositories: `ubuntu-24.04` for all of them except the two informational
Windows lanes, `test-windows` in `ci.yml` and `windows` in
`hook-utils-timing.yml`, which run `windows-2025`. The organization's
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
(`changes`, `lint`, `test-linux`, `hook-utils`) and requires
each result to be `success`, failing closed through execution
(`!cancelled()`, never a success-guard, so a skipped lane cannot report
success to branch protection). `test-windows` is deliberately outside that
aggregate, as an informational platform lane; `ci.yml` says so at the job and
warns against adding it to `ci-status.needs`. The metadata checks (Conventional Commits title,
`do-not-merge` label, issue linkage) run as the `pr-contract` composite step
inside the same `ci-status` job on the same hosted runner, so they no longer
carry status contexts of their own. Fork pull requests receive no secrets and
no automated review, by design.

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

## Authoritative references

- [Reuse workflows and pin a commit SHA](https://docs.github.com/en/actions/how-tos/reuse-automations/reuse-workflows)
- [Reusable workflow runner and permission behavior](https://docs.github.com/en/actions/reference/workflows-and-actions/reusing-workflow-configurations)
- [`merge_group` and required checks](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#merge_group)
- [Dependabot configuration options](https://docs.github.com/en/code-security/reference/supply-chain-security/dependabot-options-reference)
