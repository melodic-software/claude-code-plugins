# Changelog

All notable changes to the `work-items` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.2.0]

Re-plumbed onto the provider-neutral work-item-tracker seam. The skill is now backend-agnostic; GitHub
is the bound adapter today rather than a hardcoded dependency.

### Changed (breaking)

- **Provider-neutral over the tracker seam.** Every tracker operation routes through the
  work-item-tracker seam — the skill calls `tools/work-item-tracker/work-item-tracker.sh <verb>` and the
  bound provider adapter executes it (contract: `tools/work-item-tracker/CONTRACT.md`). The skill core
  inlines **no** provider commands: coordination (create, claim, renew/reclaim lease, dependency links,
  sub-items, frontier selection, single-item fetch) uses seam verbs, and provider mechanics (filtered
  listing, search, aggregation, close, label/comment edits) reference the bound adapter's operations
  doc. Previously the skill called `gh` directly throughout.
- **Claim protocol is now assignee + lease, race-safe at the seam.** The label-based
  hold&nbsp;→&nbsp;verify&nbsp;→&nbsp;claim dance (`status:considering` / `status:claimed`) is retired.
  Claiming assigns the item and writes a lease comment; races are resolved by lease-comment identity,
  and a session-start `reclaim` runs idempotently to recover crashed sessions' stale leases. The claim
  identity is always the authenticated session user, never a shared bot.
- **New consumer requirement.** The consuming repo provides the seam at `tools/work-item-tracker/` and
  binds its active provider in `.work-item-tracker.json`. The skill no longer shells out to `gh` on its
  own; the GitHub adapter behind the seam does.

### Changed

- Backend-neutral vocabulary throughout — "work item" rather than "GitHub issue"; the description and
  action docs read against any bound provider.
- Removed the skill's `gh`-scoped `allowed-tools` and the inline `gh`-based pre-computed dashboard
  block; the dashboard now derives through the seam and adapter.
- The agent-brief template ships at `reference/agent-brief.md`.

## [0.1.0]

- Initial release: a GitHub-Issues work-item tracker skill — `stats`, `list`, `add`, `work`, `start`,
  `done`, `due`, `recheck`, `search`, `scan`, `audit`, `decompose`, `triage` — with a `gh`-backed
  hold&nbsp;→&nbsp;verify&nbsp;→&nbsp;claim multi-agent claim protocol.
