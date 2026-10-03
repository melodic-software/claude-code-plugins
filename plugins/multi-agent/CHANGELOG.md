# Changelog

All notable changes to the `multi-agent` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.3.0] - 2026-10-02

### Added

- **`/multi-agent:check`**, a read-only check that reports whether `node` resolves, whether
  `hooks/hooks.json` registers the `drift-checker` fetch gate on `WebFetch`, and whether the gate
  denies a sample off-host drift-checker fetch, through its bundled `scripts/check.sh`. The
  registration row requires one `PreToolUse` entry to carry the matcher, command and script
  together when `node` resolves. The script takes no arguments, and the skill installs nothing. `prerequisites.json` declares
  `node` with this skill as its check.

### Changed

- **The README states that the fetch gate fails open without `node`**: the hook cannot start,
  Claude Code shows a non-blocking hook error notice, and the drift checker's fetches are held to
  first-party docs hosts only by the workflow's source filter and the agent's prompt.

## [0.2.0] - 2026-10-02

### Added

- **`multi-agent:drift-audit` workflow** (`workflows/drift-audit.js`). In `defaults` mode, one
  finder per owner rechecks each bundled default against its pointers; in `repo` mode, one
  reader per area quotes the repository's model, effort, subagent and workflow statements and
  one finder per area checks those quotes against upstream pages. Plain code dedups the
  findings, then three independent skeptics per batch try to refute each one, and a finding
  stands or falls on a majority. It returns confirmed, refuted and unverified findings with
  evidence URLs, plus a proposed `defaults.yaml` diff in `defaults` mode, built only from
  confirmed rows whose proposed value fits the key (a model alias, an effort level, and never
  `frontier_guard: false`) and that no skeptic corrected. A `current` verdict needs evidence
  from a vetted source host; without it the row is unverified. It never edits a file.
  Missing `pointers` (defaults mode) or `targets` (repo mode) returns an error and runs
  nothing. Under a frontier or unknown session, every stage runs on `opus`.
- **`drift-reader` and `drift-checker` agents**, the only agents the workflow runs. The reader
  has Read, Grep and Glob; the checker has WebFetch only. Neither has a shell or can
  edit, and no agent holds both file and web access. Repository text and pages reach their
  prompts only as fenced data, and a finding whose evidence URL is outside the vetted source
  hosts is reported unverified instead of going to a skeptic.
- **`drift-checker` fetch gate** (`hooks/drift-checker-fetch-gate.mjs`), a `PreToolUse` hook on
  `WebFetch`. Inside a `drift-checker` subagent it denies any fetch that is not an https URL on a
  first-party docs host with no query string; other agents and the main thread pass through.
  The workflow drops sources outside those hosts before any stage runs. Needs `node`.
- **`audit-defaults repo`**, a mode that sweeps the repository's tracked markdown;
  `scripts/list-targets.sh` computes the areas and skips symlinks.
- **`list-pointers.sh --json`**, which prints the rows as the workflow's `args.pointers`.

### Changed

- **`/multi-agent:audit-defaults` launches the workflow.** Its `allowed-tools` grants only
  `Workflow(multi-agent:drift-audit)`. When workflows are unavailable, `defaults` mode runs on
  the main thread as before, and `repo` mode stops and says so.

## [0.1.0] - 2026-10-02

### Added

- **Skills.** `assess` (workflow, subagent or single context for a task, with a Workflow
  availability check), `route` (the resolved role map for a workflow's `args.roles`),
  `audit-defaults` (rechecks each bundled default against its upstream pointer, for every
  owner or one named owner, and proposes changes, never applies them) and `setup` (`check` prints the resolved map and the overlay's
  gitignore state; `apply` previews a user, team or local layer change as a diff, writes it on
  an explicit yes, and shows the map before and after. It refuses a team or local path that is,
  or sits under, a symlink inside the repository, and replaces the file by rename).
- **Scope.** The role map governs generic `agent()` calls and Agent dispatches with no agent
  type. A named agent, such as `implementation:scoped-implementer`, keeps the tier in its own
  definition.
- **Role map.** `reference/defaults.yaml` with `orchestrator`, `worker`, `verifier` and
  `retrieval`, each with its pointer, as-of date and recheck trigger, layered through
  user-global, team and overlay files by `scripts/resolve-roles.sh`, which runs on Bash 3.2
  (stock macOS) and later.
- **Fan-out guard.** Each role resolves to a `single` and a `fanout` variant; with
  `fanout.frontier_guard` on (the default), a fan-out variant that would inherit a frontier or
  unknown session model, or that names a frontier alias, takes `fanout.model` (`opus` by
  default).
