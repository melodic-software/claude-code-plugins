# Allow API keys from the operator's own linked Console orgs

- Status: accepted; amended 2026-10-16 (decision 3, see the amendment below)
- Date: 2026-10-11
- Amends: [ADR 0037](0037-seat-mandatory-reviews-on-the-operator-session-and-retire-the-oauth-lanes.md),
  its premise that the operator cannot use API keys

## Context

ADR 0037's Context says "the operator cannot use API keys, so every review in CI drew on the same
subscription window the interactive sessions use." Every lane here has since run on a subscription
token, so a lane that reaches its subscription limit stalls until the window resets.

That premise no longer holds. Max and Team plans now include monthly credits for the Claude
Platform, claimed by linking one Claude Console organization to the plan
(<https://support.claude.com/en/articles/17154008-monthly-api-credits-for-max-and-team-plans>,
fetched 2026-10-11). Per that article:

- Everyone with an API key in the linked organization draws from the same balance.
- The credits cover the Messages API and Message Batches API, Claude Managed Agents, and
  `claude -p` and the Claude Agent SDK when run with an API key.
- Runs started by the Claude Code GitHub Action count as Claude Code usage, so the credits do not
  cover them, even with `-p`.
- Unused credits expire at the end of each billing cycle.
- When the credits run out, usage continues against any purchased credits or auto-reload, and an
  invoiced org is billed as usual; an org with no other credits stops API requests until the next
  monthly credits arrive.

Recheck this record when that article changes what the credits cover or how an organization links
to a plan.

The operator settled how subscriptions and credits split in the framing decision of the capacity
map (#6958, resolved on #6959) and declined a paid backstop (#6966).

## Decision

1. **API keys from the operator's own linked Console orgs may be used.** A linked org is one linked
   to a plan the operator holds. No other API key is in scope.
2. **They fund API-only workloads:** the Messages and Batches APIs, Managed Agents, and the
   operator's own Agent SDK or `claude -p` runs started with a linked org's key.
3. **They are the fallback that keeps a lane from stalling on a subscription limit.** A lane that
   hits its limit moves to API keys, rotating through the linked orgs. When every linked org's
   credits and the lane's subscription are spent, the lane pauses, alerts the operator, and resumes
   when a subscription window resets or credits refill. There is no paid backstop, so a linked org
   used for the fallback holds no purchased credits, has auto-reload off, and is not invoiced: the
   article says usage continues against purchased credits or auto-reload, and invoiced usage beyond
   the credits is billed, while an org with no other credits stops API requests until the next
   monthly credits arrive.
4. **Subscriptions stay one account per workload.** Each account runs to its limit and waits for
   the reset; no lane rotates between subscription accounts automatically.
5. **The mechanisms are decided on the capacity map (#6958), not here:** which lanes fall back,
   how a limit is detected, and how keys are stored and selected.

### What this changes in ADR 0037

ADR 0037's statement that the operator cannot use API keys is withdrawn. Its other text stands as
amended by ADR 0038 and its own addendum.

## Alternatives considered

- **Keep subscription-only.** Rejected: lanes stall at every limit, and the plan credits expire
  unused each billing cycle.
- **Rotate lanes between subscription accounts automatically.** Rejected in the framing decision
  (#6959): subscriptions stay one account per workload.
- **A capped paid balance behind the credits.** Rejected (#6966): it only moves the stall a short
  way and adds a moving part.
- **Rotate through linked orgs (original decision 3).** Replaced by the amendment: spreading one
  lane's work across several orgs' credits is not something the credits article or the terms
  explicitly permit, and this repository treats what the terms do not address as unsettled, not as
  permission.

## Consequences

- Lanes that run the Claude Code GitHub Action have no credit-funded fallback, because those runs
  never draw credits. The proposed remedy for a lane that must not stall is its own `claude -p`
  step (#6967), but whether a self-written workflow step that installs the CLI and runs `claude -p`
  with a linked org's key draws that org's credits is unconfirmed: the article does not say.
  Probe #6962 answers it, and whether any CI lane can fall back to credits waits on #6962 and
  #6967.
- A linked org's key is a new long-lived credential. Where it is stored and which jobs may read it
  is decided with the mechanisms (decision 5), under the CI lane hardening of
  [ADR 0049](0049-run-ci-lanes-on-github-hosted-runners-under-trigger-and-token-hardening.md).
- Once every linked org's credits (see the amendment) and a lane's subscription are spent, that
  lane waits. That is the intended end state of full use, not a fault.

## Revisit triggers

- When probe #6962 reports, record whether a self-written `claude -p` CI step draws credits.
- The credits article changes coverage, expiry, or the one-org link → re-derive decisions 2 and 3.
- The operator adds a paid backstop or automatic subscription rotation → amend decisions 3 and 4.
- Probe #6962 reports, or observed billing differs from what the amendment assumes → re-derive the
  amendment.

## Amendment (2026-10-16): each lane's role uses one plan

A lane asks for a role, and each role is assigned to one plan. A lane that self-runs `claude -p`
or the Agent SDK may fall back, when it reaches its subscription limit, only to that plan's own
linked-org credits; for a CI lane that fallback waits on probe #6962. The key is present only in
the environment of the fallback run, and never where the model's tools can read it: the launcher
sets `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB` so the Bash commands, hooks and MCP servers the run starts
get no credential (see [What the subprocess environment scrub removes](https://code.claude.com/docs/en/env-vars#what-the-subprocess-environment-scrub-removes)). A lane that runs the Claude Code GitHub Action is never given
a key: a key set there replaces the lane's subscription token, and the credits do not cover Action
runs. No lane rotates across linked orgs. When the plan's subscription window and its credits are
both spent, the work queues with an operator alert, and the operator may reassign the role by hand.

Where decision 3 says a lane rotates through the linked orgs, read this amendment. Decisions 1, 2,
4 and 5 stand, and decision 5 keeps the mechanisms on the capacity map (#6958).

Every lane today runs claude-code-action, so none has a credit fallback: each queues and alerts at
its limit until it is rebuilt on its own `claude -p` step (#6967). How such a lane saves its
progress when a limit stops it is an open operator decision, carried on #7677.
