# Changelog

All notable changes to the `multi-agent` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.1.0] - 2026-10-02

### Added

- **Skills.** `assess` (workflow, subagent or single context for a task, with a Workflow
  availability check), `route` (the resolved role map for a workflow's `args.roles`),
  `audit-defaults` (rechecks each bundled default against its upstream pointer and proposes
  changes, never applies them) and `setup` (`check` prints the resolved map and the overlay's
  gitignore state; `apply` previews a user, team or local layer change as a diff, writes it on
  an explicit yes, and shows the map before and after. It refuses a team or local path that is,
  or sits under, a symlink inside the repository, and replaces the file by rename).
- **Scope.** The role map governs generic `agent()` calls and Agent dispatches with no agent
  type. A named agent, such as `implementation:scoped-implementer`, keeps the tier in its own
  definition.
- **Role map.** `reference/defaults.yaml` with `orchestrator`, `worker`, `verifier` and
  `retrieval`, each with its pointer, as-of date and recheck trigger, layered through
  user-global, team and overlay files by `scripts/resolve-roles.sh`.
- **Fan-out guard.** Each role resolves to a `single` and a `fanout` variant; with
  `fanout.frontier_guard` on (the default), a fan-out variant that would inherit a frontier or
  unknown session model, or that names a frontier alias, takes `fanout.model` (`opus` by
  default).
