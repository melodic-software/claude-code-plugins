---
bump: minor
---

### Changed

- The pull-request skill's merge preflight runs `skills/pull-request/scripts/merge-readiness.sh`, the same readiness script the guardrails merge guard runs ([#18822](https://github.com/melodic-software/claude-code-plugins/issues/18822)), at the pinned head, so the skill and the guard cannot judge a merge differently, and the skill alone still checks everything when guardrails is not installed. It holds on any read it cannot make.
- Hold labels (`do-not-merge`, `pr-verify-failed`, `security: outside-actor`) now hold in any case, a reviewer whose latest review requests changes holds, and a `timed_out`, `cancelled`, `action_required`, `startup_failure` or `stale` check holds.
- A failed check is never classified informational: it clears only by passing or through the guardrails `merge_guard_ignored_checks` setting.
- The pr-verify wait ends 30 minutes after the head's last check finished, measured from the checks rather than from when the session started waiting.
