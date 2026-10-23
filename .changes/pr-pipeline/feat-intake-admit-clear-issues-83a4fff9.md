---
bump: minor
---

### Added

- Intake admits clear issues with no person in the loop (owner decision Q51): after apply-verdict sets `status: ready`, `.github/scripts/intake-triage/admit.mjs` adds `agent-ready` as the lanes App when the issue meets the rules in `.github/actions/resolve-config/admission-rules.json` (type Bug or Task, or Feature under an open parent a listed human filed; class read-only, mechanical or scoped; Size Small or Medium; Uncertainty Known; a `- [ ]` task list; no open blocker (a blocking issue counts as done only when a listed human or a merge closed it), open pull request or refusing label; a listed author) and the issue lane's caps have room. Over a cap, or while an open pull request in the repository names the issue, it adds `admission-deferred`, which work-unblock's sweep admits once there is room and no such pull request is open; a refusal swaps `status: ready` for `status: needs-decision` and says why in one App comment ([#9214](https://github.com/melodic-software/claude-code-plugins/issues/9214)).

### Changed

- `wip.pause-from` is set (2026-10-22), so over the WIP or held cap the issue lane pauses its runs, and over the queued cap admissions pause, instead of only alerting.
- Intake holds an issue on security only for a very-high risk, the security review's CRITICAL tier: the triage prompt sets the `security` flag only when the work would expose a credential, bypass a trust boundary or open an external attack surface, and apply-verdict no longer keeps an issue from `status: ready` for the `area: security` label alone.
- work-unblock admits nothing, newly unblocked or deferred, while the issue lane is paused over its WIP or held cap, so its sweep no longer undoes intake's deferral during a pause.
