# CI runner routing

This repository is private even though it publishes a public-facing plugin
marketplace. Eligible read-only Linux validation jobs prefer the organization
local fleet to reduce GitHub-hosted runner cost. Privileged or structurally
incompatible work stays on explicit GitHub-hosted images.

## Configuration contract

Workflow source contains no organization runner label, host name, or GitHub App
identifier. GitHub IaC owns the nonsecret organization variables:

- `CI_RUNNER_POLICY` (`prefer-self-hosted` or the emergency
  `hosted-only` kill switch)
- `CI_SELF_HOSTED_LABEL`
- `CI_HOSTED_RUNNER`
- `CI_RUNNER_SCOPE`
- `CI_MANAGED_RUNNER_PREFIX`
- `CI_RUNNER_OBSERVER_CLIENT_ID`

The caller passes only `CI_RUNNER_OBSERVER_PRIVATE_KEY`, by name, to the
reviewed selector. It never uses `secrets: inherit`. That credential belongs to
the read-only observer App; host registration keys and controller credentials
never enter GitHub Actions or worker containers.

All callers pin
`melodic-software/ci-workflows/.github/workflows/select-runner.yml` to the
independently reviewed commit recorded in `.github/runner-policy.json`'s
standards-distributed policy. GitHub documents a full commit SHA as the safest
reusable-workflow reference. Dependabot watches the GitHub Actions dependency,
but every executable pin update remains a reviewed pull request.

## Routing and failure behavior

Each independently scheduled eligible job has its own selector dependency. Its
workload uses `if: ${{ !cancelled() }}` and the exact reviewed expression
`needs.<selector>.outputs.runner || 'ubuntu-24.04'`. The literal is a last-resort
hosted route when selector infrastructure itself fails; it does not trust an
unvalidated variable after that failure. The selector remains a separate, short
GitHub-hosted job. Its two-minute workflow timeout does not limit the downstream
workload job, which retains its own timeout.

Local execution requires an exact managed label and an online, idle, ephemeral
runner. The selector returns `ubuntu-24.04` when any safety or availability
condition is not met, including:

- `CI_RUNNER_POLICY=hosted-only`;
- a rerun (`github.run_attempt > 1`);
- fork pull requests, Dependabot, public repositories, and merge-queue runs;
- missing configuration or the observer secret;
- no idle managed runner; or
- authentication, API, timeout, pagination, or response-validation failure.

The `ci-status` required check depends only on workload lanes and requires every
workload result to be `success`; selectors are intentionally excluded from the
required gateway. A selector failure still runs its workload hosted through the
cancellation-safe literal fallback, while a skipped or failed workload cannot
produce a green gate. The
`pr-title / pr-title` required check uses the same cancellation-safe hosted
fallback so its required-check identity is still emitted.

Selectors are deliberately one per independent workload. Sharing one result
would fan one idle observation into all thirteen CI lanes. GitHub exposes no
atomic runner reservation, so selectors that observe the same runner at the
same instant can still choose local together. The fleet enforces its capacity;
its queue monitor alerts on the accepted rare race and the recovery is to
cancel, then use **Re-run all jobs**, which routes the new attempt hosted.

## Hosted boundaries

The machine-readable exceptions in `.github/runner-policy.json` are the complete
hosted inventory:

- `zizmor` needs Docker for a container action; local workers have no Docker
  socket;
- `runner-policy` must audit routing independently of the fleet;
- `ci-status` must aggregate required workload outcomes independently of the
  fleet it governs;
- `claude-review` has `pull-requests: write` and `id-token: write`; and
- `link-check` has `issues: write`.

Forks and Dependabot always execute eligible validation on GitHub-hosted
compute, where the observer secret is unavailable. `merge_group` is included on
both required-check workflows so a future merge queue receives the same
`ci-status` and `pr-title / pr-title` contexts; those runs route hosted.

The plugin-gate toolchain is also identical on hosted and local compute. Node
executables are integrity-locked in `package-lock.json`, Ruff is pinned to the
Ubuntu x64 wheel and SHA-256 in `.github/requirements-ci.txt`, and Dependabot
tracks both dependency roots. CI consumes those manifests with `npm ci` and
hash-required `pip`, never mutable global installs.

## Authoritative references

- [Reuse workflows and pin a commit SHA](https://docs.github.com/en/actions/how-tos/reuse-automations/reuse-workflows)
- [Reusable workflow runner and permission behavior](https://docs.github.com/en/actions/reference/workflows-and-actions/reusing-workflow-configurations)
- [Secure use of self-hosted runners](https://docs.github.com/en/actions/reference/security/secure-use)
- [Self-hosted runner routing](https://docs.github.com/en/actions/reference/runners/self-hosted-runners)
- [`merge_group` and required checks](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#merge_group)
- [Dependabot configuration options](https://docs.github.com/en/code-security/reference/supply-chain-security/dependabot-options-reference)
