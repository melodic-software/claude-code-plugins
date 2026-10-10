---
bump: minor
---

### Added

- **Prep lists the suppressions a change adds.** For a diff that is not docs-only,
  `/source-control:pull-request` prep runs `/code-metrics:audit-suppressions` against the pull
  request's base when that skill is among the available skills, and lists each added suppression
  with its file, line, rule ids and reason in the prep report. The scan is advisory and blocks
  nothing: when the skill is unavailable or the scan fails, the report says
  `suppression check not run: <reason>` and prep continues. No dependency on the code-metrics
  plugin is declared.
- **Narrow pull requests, red-first review fixes, and disk freed by cleanup.**
  `/source-control:pull-request` prep flags a diff that splits into independent changes and
  proposes one pull request per part (advice the user may decline); a review finding about behavior
  gets a failing test before its fix (D6 and `monitor`); the briefing body links a longer record
  instead of reciting review or CI lanes; and `ready` gathers the evidence a plan phase's
  `Review:` value asks for before the flip, leaving the draft in place when it is missing (a
  review-concern tag such as `Review: security` asks for none and never holds the flip).
  `/source-control:worktree cleanup` reports free space before and after, and on macOS with
  `xcrun` (a new optional prerequisite) lists Xcode build output and unavailable simulators,
  deleting each only on its own yes.
- **`/source-control:worktree` runs the consumer's Workspace environment verbs.** `create` runs the
  declared `setup` after the worktree exists and before entering it, on the helper path and the
  plain `git worktree add` path; `cleanup` runs `down` after its guards clear and before removal.
  The entry is read from the fetched default branch, the verbs run through the Bash tool with
  `WORKSPACE_ID` and `WORKSPACE_ROOT`, and none runs for an untrusted-input worktree. The
  `WorktreeCreate` and `WorktreeRemove` hooks are unchanged.
- **`pr_open_state` chooses whether `/source-control:pull-request create` opens a draft.** `draft`
  (the default, as before) or `ready`. The per-user value is the new `pr_open_state` `userConfig`
  option; a repository sets it in `docs/conventions/source-control.yaml`, which wins and is
  validated by the new `schemas/source-control.schema.json`. `create` reports which level supplied
  the value, and a value other than `draft` or `ready` opens a draft. `.claude/source-control.md`
  does not carry the key.
- **A repository can keep a review-bot triage rubric.** A `## Review-bot triage rubric` table in
  `docs/conventions/source-control.md` (pattern, optional reviewer, `dismiss`/`fix`/`ask`,
  `high`/`medium`/`low` confidence) is read at the PR's base branch by
  `/source-control:pull-request` `monitor` and `comments` and by `/source-control:babysit-prs`, so
  both triage a recurring bot finding the same way. It never dismisses a security or data finding,
  and an `ask` row in a run with no one to answer leaves the thread open and reports it instead of
  prompting. Without the section, triage is unchanged.
- **`/source-control:babysit-prs` reruns a failing check at most once per PR head.** The new
  `manage_feedback_ledger.py record-rerun` records each rerun in the durable mutation ledger, keyed
  by PR, head SHA and check, before the rerun is triggered, and refuses a second one for the same
  check at the same head (exit 4): that failure is treated as real and fixed or reported. A new
  head starts the count again. The command names the check by its hex id, which the snapshot
  text prints first on each `failing check: rerun_id=<id> name="<name>"` line (check names are now
  JSON-escaped, one check per line), never by its name, because a fork PR controls its job
  names. `reference/native-autofix-pr.md` now states that an `/autofix-pr` session never
  merges, and how a repository puts the same triage rules in front of that cloud session.

### Changed

- **`/source-control:pull-request create` drafts a short-briefing PR body by default.** When no
  layer sets `pr_body_required_sections`, the body now has `Why`, `What changed`, `Scope` and
  `Verification` (all required), plus `Tradeoffs` and `Risk` when they have content, in place of
  `Summary` and `Test plan`. The key accepts two new keywords beside `none`: `briefing` (this
  default, stated explicitly) and `summary-test-plan` (the previous default). A repository that wants
  the old body sets `summary-test-plan`; a repository that already sets a heading list sees no
  change. `/source-control:setup` reports and recommends the new default.

### Fixed

- **GitHub-sourced names stay out of typed shell commands and jq programs.** The readiness
  duplicate-check verification lists every check run and matches the name in the output instead
  of typing it into a `--jq` regex. The push-verify (`pull-request` D6 and review discipline),
  remote-branch delete (`merge`) and read-only `git show` (`babysit-prs`) commands single-quote
  the PR head branch, pass it after `--end-of-options`, and use it only when it matches
  `^[A-Za-z0-9._/-]+$`, does not start with `-` and holds no `..`; any other name is reported,
  never run. The pull-request checklist template's Phase 4 line shows the same quoted delete
  command and points to that rule, and worktree cleanup's suggested remote delete applies it too.
