# Changelog

All notable changes to the `multi-agent` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.1.0] - 2026-10-02

### Added

- **Skills.** `assess` (workflow, subagent or single context for a task, with a Workflow
  availability check), `route` (the resolved role map for a workflow's `args.roles`) and
  `audit-defaults` (rechecks each bundled default against its upstream pointer and proposes
  changes, never applies them).
- **Role map.** `reference/defaults.yaml` with `orchestrator`, `worker`, `verifier` and
  `retrieval`, each with its pointer, as-of date and recheck trigger, layered through
  user-global, team and overlay files by `scripts/resolve-roles.sh`.
- **Fan-out guard.** Each role resolves to a `single` and a `fanout` variant; with
  `fanout.frontier_guard` on (the default), a fan-out stage under a frontier or unknown session
  names `opus` instead of inheriting the session model.
