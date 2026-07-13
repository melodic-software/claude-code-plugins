# CI runner routing

This repository is private even though it publishes a public-facing plugin
marketplace. Eligible read-only Linux validation jobs use the organization
local fleet and queue there until capacity is available. Privileged,
untrusted, or structurally incompatible work stays on explicit GitHub-hosted
images.

## Configuration contract

Workflow source contains no organization runner label, host name, or GitHub App
identifier. GitHub IaC owns the nonsecret organization variables:

- `CI_RUNNER_POLICY` (`self-hosted-only` or the emergency `hosted-only` kill
  switch)
- `CI_SELF_HOSTED_LABEL`
- `CI_HOSTED_RUNNER`
- `CI_RUNNER_SCOPE`
- `CI_MANAGED_RUNNER_PREFIX`
- `CI_RUNNER_OBSERVER_CLIENT_ID`

The caller passes only `CI_RUNNER_OBSERVER_PRIVATE_KEY`, by name, to the
reviewed selector. It never uses `secrets: inherit`. Strict
`self-hosted-only` routing does not mint or require that observer credential;
the input remains explicit for the separately reviewed inventory-based policy.
Host registration keys and controller credentials never enter GitHub Actions
or worker containers.

All callers pin
`melodic-software/ci-workflows/.github/workflows/select-runner.yml` to the
independently reviewed commit recorded in `.github/runner-policy.json`'s
standards-distributed policy. GitHub documents a full commit SHA as the safest
reusable-workflow reference. Dependabot watches the GitHub Actions dependency,
but every executable pin update remains a reviewed pull request.

## Routing and failure behavior

Each workflow runs a single selector preflight shared by every eligible job it
schedules. Each workload requires both `!cancelled()` and a successful selector
result, then uses the policy-required expression
`needs.select-runner.outputs.runner || 'ubuntu-24.04'`. The success gate is
load-bearing: invalid strict configuration or selector infrastructure failure
blocks the dependent workloads instead of silently redirecting them to paid
hosted Linux. The selector remains a separate, short preflight job. Its
two-minute workflow timeout does not limit the downstream workload jobs, which
retain their own timeouts.

For `self-hosted-only`, the selector validates the exact centrally allowlisted
managed label and returns it without querying runner inventory or minting the
observer token. Trusted private `push`, `schedule`, `workflow_dispatch`, and
same-repository `pull_request` workloads—including reruns—therefore stay on the
local queue until the controller supplies capacity. The selector returns the
reviewed hosted image for the emergency `hosted-only` policy and for security
boundaries: public repositories, fork pull requests, Dependabot, and event
classes outside the local allowlist, including `merge_group`.

The `ci-status` required check depends only on workload lanes and requires every
workload result to be `success`; selectors are intentionally excluded from the
required gateway. A failed selector leaves its workload non-successful, so the
gateway fails closed. PR-title semantic validation uses the same selector
success gate, while a tiny hosted `pr-title / pr-title` control-plane job emits
the existing required context and fails when selection or validation is not
successful.

One selector preflight per workflow makes the routing decision once instead of
fanning out identical jobs, and every required-check edge still passes through
the same explicit, policy-auditable selector gate. In strict mode it returns
the same governed label for every lane; the fleet, not a stale inventory
snapshot, enforces concurrency. Bursts queue on that label, one ephemeral
container accepts each job, and a re-run reuses the prior attempt's successful
selector output, so reruns remain local instead of becoming a paid recovery
path.

## Hosted boundaries

The machine-readable exceptions in `.github/runner-policy.json` are the complete
hosted inventory:

- `zizmor` needs Docker for a container action; local workers have no Docker
  socket;
- `runner-policy` must audit routing independently of the fleet;
- `ci-status` must aggregate required workload outcomes independently of the
  fleet it governs;
- `pr-title / pr-title` must report a failed required context even when strict
  selection prevents the semantic workload from starting;
- `claude-review` has `pull-requests: write` and `id-token: write`; and
- `link-check` has `issues: write`.

Forks and Dependabot always execute eligible validation on GitHub-hosted
compute, and the observer-token action is skipped. `merge_group` is included on
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
