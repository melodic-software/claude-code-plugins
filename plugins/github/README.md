# github

A Claude Code plugin for the **GitHub settings/admin plane**: audit, review, advise, and guided
setup/management for the authenticated user across organizations, repositories, and enterprises —
consistency, drift, standards conformance, and cost control.

Everything is grounded at runtime: live state comes from the consumer's own `gh` CLI session, and
mechanics come from freshly fetched official GitHub documentation. The plugin ships **zero vendored
GitHub knowledge** — no endpoint tables, no scope lists, no prices — so it cannot go stale against
GitHub's weekly-moving surface. Where a fetch fails or an area is out of the current credential's
reach, the skills say so honestly instead of guessing.

| Skill | Status | What it does |
|---|---|---|
| `/github:audit <area…>` | shipped | Read-only findings over one, several, or all coverage areas: current-state review, drift vs declared conventions, standards conformance, cost signals. |
| `/github:advise` | planned | Forward-looking guidance and hand-holding ("how should I configure X", "walk me through Y"). |
| `/github:setup` | planned | Verify prerequisites (`gh` present and authenticated) and write consumer config. |

Areas are **arguments, not skills** — the coverage matrix (rulesets, billing, security model,
Actions policy, webhooks, packages, and the rest) lives in
[`reference/areas.md`](reference/areas.md), and every area routes through the same
[`reference/method-ladder.md`](reference/method-ladder.md).

## Verb contract

This plugin follows the marketplace verb grammar: `audit` is a read-only findings report — a bare
invocation performs **zero mutations** (no write-capable `gh api` flags, no non-GET methods, no
GraphQL mutations). It additionally declares one new verb at this coupling site:

- **`advise`** — read-only advisory guidance. Distinct discovery intent from `audit`:
  design/forward-looking ("how should I…") where `audit` is current-state/backward-looking
  ("what is…", "what drifted…").

Mutation is only ever reachable behind an explicit override argument, resolves through the
consumer's declared change routing, and keeps the user in the loop for every write.

## Prerequisites

- **`gh` CLI, authenticated by you.** The plugin uses your own `gh` session and never stores
  credentials. When a token scope or credential modality cannot reach an area, the skill names the
  gate and recommends the remediation for you to run yourself.

## Consumer configuration

Unconfigured consumers work read-only out of the box: change routing defaults to **propose-only**
(proposed changes are emitted as exact commands or diffs, never executed). Consumer config lives in
`.claude/github/` (change routing plus the conventions your audits compare against); its contract
document ships in an upcoming phase.

## Install

From whichever marketplace distributes this plugin:

```shell
/plugin marketplace add <marketplace-owner>/<marketplace-repo>
/plugin install github@<marketplace-name>
```
