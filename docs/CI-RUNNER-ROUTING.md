# CI runner routing

This repository is public, so every lane runs on GitHub-hosted
`ubuntu-24.04` — free for public repositories — and the organization's
runner-policy engine forbids local-runner selector routing here outright
(`public-self-hosted-routing`). There is no selector preflight, no observer
credential, and no self-hosted exception inventory in this repository.

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

The `ci-status` required check depends on every workload lane and requires
each result to be `success`, failing closed through execution
(`!cancelled()`, never a success-guard, so a skipped lane cannot report
success to branch protection). The metadata gates (`do-not-merge`,
`pr-issue-linkage`) run on `pull_request_target` so the base-branch definition
evaluates, and emit their required contexts from the reusable's hosted default
runner. Fork pull requests receive no secrets and no automated review, by
design.

## Toolchain integrity

The plugin-gate toolchain is identical everywhere it runs. Node executables
are integrity-locked in `package-lock.json`, Ruff is pinned to the Ubuntu x64
wheel and SHA-256 in `.github/requirements-ci.txt`, and Dependabot tracks both
dependency roots. CI consumes those manifests with `npm ci` and hash-required
`pip`, never mutable global installs.

### Local / workstation ruff

Do **not** trust a bare `ruff` on `PATH` for verification in this repository.
Workstation package managers routinely auto-upgrade past the CI pin; a newer
ruff (for example 0.16.x while CI is on `ruff==0.15.22`) reports dozens of
findings on an unmodified `main` tree that CI still accepts. Prefer the pin:

```shell
scripts/run-ruff.sh check <paths>
# equivalent: uvx ruff==$(awk '/^ruff==/{sub(/^ruff==/,""); sub(/[[:space:]\\].*$/,""); print; exit}' .github/requirements-ci.txt) check <paths>
```

`scripts/run-ruff.sh` uses a PATH `ruff` only when it already reports the pinned
version (the CI install path); otherwise it runs `uvx ruff==<pin>`. Plugin
contract tests that lint Python (`engine.test.sh`) invoke that wrapper. Bumping
the pin is a deliberate Dependabot/CI change — do not "fix" a clean tree by
adopting a newer ruff's new rules in an unrelated PR.

## Authoritative references

- [Reuse workflows and pin a commit SHA](https://docs.github.com/en/actions/how-tos/reuse-automations/reuse-workflows)
- [Reusable workflow runner and permission behavior](https://docs.github.com/en/actions/reference/workflows-and-actions/reusing-workflow-configurations)
- [`merge_group` and required checks](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#merge_group)
- [Dependabot configuration options](https://docs.github.com/en/code-security/reference/supply-chain-security/dependabot-options-reference)
