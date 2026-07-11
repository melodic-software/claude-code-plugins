---
name: work-items
description: "Manage GitHub Issues as a development work-item tracker — dashboard stats, create with a label taxonomy, concurrent-safe claim protocol, recurring-schedule checks, codebase TODO scanning, stale-claim auditing, plan decomposition into vertical-slice issues, and structured triage. Use when: 'add an issue', 'pick work', 'close issue', 'list issues', 'what's due', 'issue stats', 'search issues', 'scan TODOs', 'audit claims', 'break plan into issues', 'decompose into tickets', 'triage issue', 'check overdue recurring items'."
argument-hint: "<action> [args] — actions: stats, list, add, work, start, done, due, recheck, search, scan, audit, decompose, triage (default: stats)"
user-invocable: true
disable-model-invocation: false
allowed-tools:
  - "Bash(gh issue list*)"
  - "Bash(gh api user*)"
---

## Pre-computed context

Open issues: !`gh issue list --state open --limit 500 --json number --jq 'length' 2>/dev/null || echo "0"`
Claimed issues: !`gh issue list --label "status:claimed" --limit 500 --json number --jq 'length' 2>/dev/null || echo "0"`
Current user: !`gh api user --jq '.login' 2>/dev/null || echo "unknown"`

## Variables

Arguments: `$ARGUMENTS`

## Scope

This skill manages **development work items** via GitHub Issues — maintenance tasks, feature requests, bug reports, recurring audits, and housekeeping. It is a centralized, concurrent-safe alternative to file-based TODO lists.

**Backend-agnostic design.** The skill uses "work items" language. The current backend is GitHub Issues; all `gh` CLI commands operate against the current repository.

**Write identity.** All commands below use bare `gh` (the session's own identity). If the consuming project routes tracker writes through a bot identity or wrapper script, follow that project's own rules (its `CLAUDE.md` / `.claude/rules`) for every write operation (create, comment, label edit, close) — with one exception: claim assignments (`--add-assignee "@me"`) must always run on the session identity, never a shared bot, or the multi-agent collision check in the claim protocol silently breaks (every claimant would resolve to the same account).

**Default = fix, not file.** Do NOT reflexively suggest `add` or `scan` for small/medium drift discovered while working. Boy Scout scope (cosmetic fixes, stale counts, broken links, single-line corrections) belongs in the current change, not the tracker. File NEW issues only when the work is genuinely orthogonal to the current session, large enough to need its own plan, or needs research the current session isn't positioned to do. When in doubt, fix in-place and surface what was fixed in the commit message / PR description.

**Label taxonomy.** Issues use a label prefix structure — UNIVERSAL groups (work in any repo) plus PROJECT-SPECIFIC groups whose members each consuming repo defines. The full structure, the discovery command, and the extension pattern live in [`reference/label-taxonomy.md`](reference/label-taxonomy.md).

| Group | Prefix | Scope | Examples |
|-------|--------|-------|----------|
| Type | `type:` | universal | `type:feat`, `type:fix`, `type:chore`, `type:docs`, `type:refactor`, `type:test`, `type:build`, `type:perf` (Conventional Commits) |
| Priority | `priority:` | universal | `priority:p0-critical` through `priority:p3-low` |
| Status | `status:` | universal | `status:needs-triage`, `status:considering`, `status:claimed`, `status:blocked`, `status:needs-info` |
| Meta | (none) | universal | `automated`, `recurring`, `agent-ready`, `good-first-issue`, `migrated`, `stale` |
| Cadence | `cadence:` | universal | `cadence:weekly`, `cadence:biweekly`, `cadence:monthly`, `cadence:quarterly`, `cadence:semi-annual`, `cadence:annual` |
| Area | `area:` | project-specific | the consuming repo's architecture surface — discover via `gh label list` |
| Category | `category:` | project-specific | the consuming repo's domain categorization — discover via `gh label list` |
| Ecosystem | `ecosystem:` | project-specific | the consuming repo's language/toolchain mix — discover via `gh label list` |

**Recurring schedule (optional consumer infrastructure).** When the consuming repo defines recurring items in `.github/recurring-schedule.json` (and optionally automates issue creation from it with its own scheduled workflow), the `due`, `recheck`, and `work` actions consume that schedule. When the file is absent, those recurring features degrade gracefully: `due` reports "no recurring schedule configured", and `work` skips the recurring tiers. Schedule item shape: see [`actions/add.md`](actions/add.md) step "If `--recurring`".

## Emit checklist

For the `work` action (the most common multi-step path), copy the "Action: work" section of [`templates/checklist.md`](templates/checklist.md) into your session task list (or the consuming project's working-notes convention) and tick each step as completed. For `add`, `start`, `done`, and `recheck`, copy the matching action section. Single-action reads (`stats`, `list`, `search`, `scan`, `audit`) don't need a checklist.

## Action Router

Parse `$ARGUMENTS` to extract the action (first token) and remaining arguments.

| Action | Description | Detail |
|--------|-------------|--------|
| `stats` | Dashboard: open/claimed counts, overdue recurring, category breakdown | [actions/stats.md](actions/stats.md) |
| `list` | List issues with label/state/assignee filtering | [actions/list.md](actions/list.md) |
| `add` | Create a new issue with labels from the taxonomy | [actions/add.md](actions/add.md) |
| `work` | Auto-select one issue and execute it via the project's development workflow | [actions/work.md](actions/work.md) |
| `start` | Claim an issue (assign + label `status:claimed`) | [actions/start.md](actions/start.md) |
| `done` | Close an issue with a completion comment | [actions/done.md](actions/done.md) |
| `due` | Show recurring items past their `next_due` date | [actions/due.md](actions/due.md) |
| `recheck` | Update `last_checked`/`next_due` in the recurring schedule after a periodic check | [actions/recheck.md](actions/recheck.md) |
| `search` | Full-text search across issues (open + closed) | [actions/search.md](actions/search.md) |
| `scan` | Scan codebase for TODO/FIXME/HACK comments, resolve or file issues from them | [actions/scan.md](actions/scan.md) |
| `audit` | Detect stale claims/holds, orphaned recurring entries, label hygiene | [actions/audit.md](actions/audit.md) |
| `decompose` | Break a plan/PRD/issue into vertical-slice issues with HITL/AFK classification and dependency ordering | [actions/decompose.md](actions/decompose.md) |
| `triage` | Evaluate incoming issue: gather → recommend → reproduce → interview → apply outcome. No args = attention view | [actions/triage.md](actions/triage.md) |
| `help` | Show the action table above | *(inline)* |

If `$ARGUMENTS` is empty, run `stats`. If the action is unknown, show the action table.

---

## Integration points

- **Development workflow.** The `work` action executes a claimed issue through the consuming project's own development workflow when one is defined (a workflow skill, CLAUDE.md workflow section, or team convention). When none is defined, follow the generic sequence: explore → plan → implement → test → review → PR.
- **Bug intake.** For new bug reports, prefer a structured capture first (the `/bug-report:bug-report` skill when that plugin is installed), then chain to `add` with the structured report as `--context`.
- **PR linkage.** Branch name `<type>/<N>-<short-slug>` (proposed by `start` / `work`) carries the issue number forward so PR tooling can inject `Closes #N`. `done --pr <N>` is the belt-and-suspenders path for manual PR flows: it verifies keyword presence on the unmerged PR body or falls back to `gh issue close` when the PR already merged.
- **Autonomous agents.** Issues labeled `agent-ready` with no assignee are available for autonomous pickup. The `work` action's claim protocol prevents concurrent-agent collisions; the `audit` action detects stale claims from crashed/abandoned sessions.
- **End of session.** Check `due` to see if any recurring items need attention.

**JSON fields available** (for `--json`): `assignees`, `author`, `body`, `closed`, `closedAt`, `comments`, `createdAt`, `id`, `isPinned`, `labels`, `milestone`, `number`, `projectCards`, `projectItems`, `reactionGroups`, `state`, `stateReason`, `title`, `updatedAt`, `url`

---

## Gotchas

Failure patterns and platform quirks. Add to this section when new gotchas are discovered.

- **Windows `\r` in pipe output.** Git Bash on Windows adds `\r` to `gh` output piped through `jq` or `--jq`. Add `| tr -d '\r'` to the end of any pipeline parsing `gh` JSON output
- **`gh issue list --search` uses GitHub search syntax, not `gh` flags.** Label filtering in `--search` uses `label:name` (no `--label` flag). Multiple labels: `label:bug label:help-wanted` (AND) or `label:bug,help-wanted` (OR). Exclude: `-label:stale`. Sort: `sort:created-asc`, `sort:updated-desc`
- **`gh issue list` default limit is 30.** Always pass `--limit` explicitly when you need more results. Maximum single request: 100 (API page size). For >100, use multiple calls with `--search` date ranges
- **`gh issue edit` uses `--add-label`/`--remove-label`, not `--label`.** `--label` is for `gh issue create` only. Edit uses `--add-label` (additive) and `--remove-label` (subtractive). Same for `--add-assignee`/`--remove-assignee`
- **`gh issue close --reason` accepts only `completed` or `not planned`.** No other values. Omitting `--reason` defaults to `completed`
- **Rate limits: 5,000 req/hr (PAT), 80 content-generating/min.** The `add` and `work` actions create issues — respect the 80/min secondary limit. For bulk operations (migration), batch 30 items with 10s pauses
- **Recurring schedule lives in the consuming repo's `.github/`, not the plugin.** The conventional path is `.github/recurring-schedule.json`; it is version-controlled and shared by the whole team. Actions that read it degrade gracefully when it's absent
- **Concurrency protocol: hold→verify→claim.** `work` and `start` use a three-phase optimistic locking protocol to prevent collisions when multiple agents pick work concurrently. Phase 1 (hold): add `status:considering` label + hold comment with session metadata. Phase 2 (verify): check for concurrent holds using GitHub comment ID ordering (monotonically increasing, server-assigned — lowest ID wins ties). Phase 3 (claim): promote to `status:claimed` + assignee. Post-claim verification catches the remaining edge case of simultaneous promotions (multiple assignees → later claimant releases). Stale holds (`status:considering` >15min) are cleaned up by `audit`. The protocol adds ~3 API calls per selection (~1s total). At 50+ concurrent agents, consider an external queue — comment-based ordering is the best GitHub-native approach but degrades with extreme concurrency
- **Pre-computed context counts may be stale.** The open/claimed counts above reflect the state at skill invocation time. For current counts mid-session, run the `stats` action
- **Auto-labeling workflows don't fire on CLI creates.** If the consuming repo auto-labels issues via an Issue Forms workflow, `gh issue create` does NOT trigger it. Always apply labels explicitly via `--label` flags when creating issues programmatically
