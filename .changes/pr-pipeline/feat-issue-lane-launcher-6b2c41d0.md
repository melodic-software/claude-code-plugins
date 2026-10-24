---
bump: minor
---

### Changed

- `work-resolve-issue`'s `resolve-issue` runs on ci-workflows' `run-claude-cli` instead of claude-code-action, on `ISSUE_LANE_CLAUDE_API_KEY` first, in `dontAsk` with an explicit allow list. When that call hands off (an empty key, a credit stop, or a 401 or 402), a new `resolve-issue-handoff` job reads so from the run's jobs and `resolve-issue-subscription` runs the activity again on `ISSUE_LANE_CLAUDE_CODE_OAUTH_TOKEN`; every later job takes the call that ran. See [Issue mode](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/pr-run-activity.md#issue-mode).
- On the launcher, an issue lane's check and verify-script wrappers are staged under `.lane/` (read-only, denied to the file tools), `issue.json` goes to the writable `.lane/scratch`, and its skill reads git only through a staged `git-read` wrapper that runs `git status`, `diff`, `log` and `show` and refuses options that write a file or read one outside the checkout. See [Two calls on one credential each](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/pr-run-activity.md#two-calls-on-one-credential-each).
- The read runner's launcher step and leg timeouts now derive from the run job's `timeout-minutes` (10 and 15 minutes under it); the issue sizes' timeouts grow by 15 minutes (small 65, medium 115, 40 without dimensions) so each leg keeps the time its turn budget was set for, and a first call hands off on `run-claude-cli`'s `handoff` output, which adds a 401 or 402 to the credit stop, in PR mode too.
- `resolve-issue` routes to the `code-fix` model profile, since the launcher needs a model alias; the reuse summary pass also runs on the launcher.
- A run the launcher stopped at its leg timeout (class `timeout`) with no outcome of its own is now a turn-cap stop: it keeps `agent-ready`, work-unblock restarts it within `limits.turn-cap-restarts`, and the next run resumes its branch, instead of handing back as `stopped`.
