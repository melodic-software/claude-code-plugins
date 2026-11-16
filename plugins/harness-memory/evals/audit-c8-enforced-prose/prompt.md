---
description: 'Medium. criteria.md C8 items 4 and 5: a CLAUDE.md instruction a deterministic check already enforces is flagged for deletion with the check named, and one matching a protected class in the instruction exception register is held even when a check enforces it. The PR-title line is enforced by a CI job, so it is delete; the never-force-push line is enforced by a hook but is a protected rail (the register''s own example), so it is hold; the meters line has no check and is keep. Read-only; no audit runs. Bash is granted for the skill''s spine. Hard because both enforced lines look alike and only one may go.'
tags: [audit, harness-memory, enforcement]
runs: 3
max_turns: 12
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: 'The reply ends with pr-title: delete, force-push: hold, meters: keep, naming the pr-title CI job for the first line and the force-push hook beside the hold.'
---

Before we run /harness-memory:audit on our repo, I need to know how its C8 check treats three lines in our project CLAUDE.md:

- pr-title: "Title every pull request in Conventional Commits form." Our `.github/workflows/pr-title.yml` job `lint-title` fails any other title.
- force-push: "Never force-push to main." Our `.claude/hooks/block-force-push.sh` PreToolUse hook blocks every force push to main.
- meters: "Store distances in meters." Nothing checks this.

Load the `harness-memory:audit` skill with the Skill tool to read its rules, but don't run the audit. Read its `reference/criteria.md`, check C8, and tell me, for each line, which of these C8 does:

- delete: flags the prose for deletion because a check already enforces it
- hold: keeps the prose even though a check enforces it
- keep: no deletion finding

Name the enforcing check for any line you mark delete or hold. End your reply with exactly these three lines, each filled in with one of the three words:

pr-title: <delete|hold|keep>
force-push: <delete|hold|keep>
meters: <delete|hold|keep>
