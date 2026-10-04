# Run CI lanes on GitHub-hosted runners under trigger and token hardening

- Status: accepted
- Date: 2026-10-03

## Context

The autonomy plugin sets `L2` as the minimum isolation for any unattended run: a whole-process
boundary with default-deny egress, credential protection and contained host writes
(`plugins/autonomy/reference/guardrails/isolation-ladder.md:15-17`). Where no `L2` substrate exists,
autonomous dispatch on that surface is blocked (`isolation-ladder.md:70-75`).

The PR pipeline ([`docs/conventions/pr-pipeline/`](../conventions/pr-pipeline/README.md)) runs its
lanes as GitHub Actions jobs on GitHub-hosted runners. A hosted runner is a fresh virtual machine per
job, but it has open outbound network access and no egress policy the job cannot change. Read
strictly, `L2` blocks every CI lane, including the live `intake-triage` lane, which is already
non-conforming.

The lanes also need what `L2` would take away. They read documentation and upstream sources on the
web, and they push commits, comment and resolve threads with a GitHub token in the model step. The
operator's design rule for lanes is to harden who can reach them and what their credentials can do,
never to remove a capability the job needs.

## Decision

A CI lane on a GitHub-hosted runner may run unattended without default-deny egress when all of
these hold:

1. **Trusted actors only.** Only text from the operator and trusted bots reaches a lane prompt, in
   public and private repositories alike, checked per item (each comment, reply and linked issue
   by its own author). The trusted-actor list is one centrally managed standards component
   that every lane reads; no lane hard-codes it.
2. **Same-repository PRs only.** No lane acts on a PR from a fork.
3. **Short-lived, scoped credentials.** Each job mints its own App token (`melodic-automation-lanes`),
   valid for at most one hour, scoped to the permissions that job needs and revoked when the job
   ends. No long-lived write token reaches a model step, and no model step holds `checks: write`
   or `workflows` permission, so no lane can write `ci-status` or change a workflow.
4. **A kill switch.** One org-level switch stops every lane without a code change. Each lane reads
   it before its model step, and a switch it cannot read counts as off.
5. **Fresh runner per job.** No state carries from one job to the next.

Lanes keep unrestricted network access and every tool, and hold the write token their job needs in
the model step. This amends the `L2` floor for this surface only: a self-operated runner, a local
lane or any other surface keeps `L2`.

## Alternatives considered

- **Keep `L2` and block CI lanes.** Rejected: hosted runners offer no default-deny egress, so the
  whole PR pipeline would stay local, which is the work this effort moves off local sessions.
- **Self-hosted runners with an egress firewall.** Rejected for now: it adds machines to operate
  and patch, and a private repository on a self-hosted runner already needs a runner-policy
  exception. It stays open for a repository whose threat model requires it.
- **No GitHub token in the model step; a scripted step does every write.** Rejected after first
  being chosen: lanes that fix code, answer review threads and update branches need to write as they
  work, and splitting each write into a scripted step adds steps without changing who can trigger
  the lane.

## Consequences

- `intake-triage` and every pipeline lane conform once the five conditions hold.
- The trusted-actor gate is the main control. If it fails open, a stranger's text reaches a lane
  that holds a write token, so the gate needs its own tests and every lane must call it.
- The autonomy plugin's isolation ladder needs a matching change naming this surface and its
  conditions; until it lands, the ladder and this record disagree and this record governs CI lanes.
- Hosted runners can reach any host, so a prompt-injected lane could send data out. The
  trusted-actor gate covers text from GitHub, but not web pages or CI logs, which reach a lane
  whoever triggered it. The exposure is bounded by what a job-scoped token can reach before it is
  revoked, and by `ci-status` and workflow files staying out of every lane's reach.
- The model holds `gh` and can fetch an untrusted comment itself, which the trusted-text filter
  never sees. This is accepted in the same class as web pages and CI logs: lane instructions frame
  any text the model fetches as data
  ([`untrusted-content`](../conventions/untrusted-content/README.md)).
- claude-code-action passes the job's `GITHUB_TOKEN` into the model's environment
  (`DEFAULT_WORKFLOW_TOKEN`, `action.yml:308` at `ed670b4`), so every job that runs the model
  grants that token only `contents: read`, and every write goes through the App token.
- A listed bot (a review bot, dependabot) can relay text someone else wrote, such as a quote from
  a PR thread or upstream release notes, and the filter keeps it because it judges the item's
  author. This is accepted in the same class as web pages.
