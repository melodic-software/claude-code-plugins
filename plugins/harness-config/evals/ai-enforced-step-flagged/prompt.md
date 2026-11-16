---
description: "Medium. criteria.md Deletion tiers (enforced) and row I5: prose restating a rule a deterministic check already enforces is flagged for deletion with the check named, while I8's cull keeps a hard constraint no check enforces. In the 9-step PR procedure, step 8 (Conventional Commits PR title, which CI rejects otherwise) is enforced by the named pr-title.yml lint-title CI job, so it is flagged for deletion naming that job; step 5 (run tests and stop on failure) has no stated check, so it stays; step 1 (git status) is narration I8 culls. Read-only; no audit runs. Hard because a step CI enforces reads like an external contract a cull should keep."
tags: [audit-instructions, outcome, deletion-tiers]
runs: 3
max_turns: 12
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "The reply ends with step 1: cull, step 5: keep, step 8: delete-enforced, and names the pr-title.yml lint-title job as what enforces step 8."
---

Before we run /harness-config:audit-instructions on our repo, I need to know how its catalog treats one of our skills. It spells out a 9-step numbered procedure for opening a PR:

1. run git status to see what changed
2. run git diff to review the changes
3. stage the files with git add
4. write a commit message
5. run the test suite and stop if it fails
6. commit
7. push the branch
8. title the PR per Conventional Commits (CI rejects other titles)
9. open the PR with gh pr create

Our `.github/workflows/pr-title.yml` job `lint-title` fails any PR whose title is not in Conventional Commits form. Nothing checks that tests ran before a commit.

Load the `harness-config:audit-instructions` skill with the Skill tool to read its rules, but don't run the audit. Read the skill's catalog (its `reference/criteria.md`: Deletion tiers, rows I5 and I8) and tell me, for steps 1, 5 and 8, which of these the catalog does with that step:

- keep: stays in the procedure as a hard constraint
- cull: removed as narration a current model sequences on its own
- delete-enforced: flagged for deletion because a deterministic check already enforces it, with that check named

Name the check for any step you mark delete-enforced. End your reply with exactly these three lines, each filled in with one of the three words:

step 1: <keep|cull|delete-enforced>
step 5: <keep|cull|delete-enforced>
step 8: <keep|cull|delete-enforced>
