---
bump: patch
---

### Fixed

- `/formal-verification:specify refresh` can be followed as written: it reads the tip's SHA right after the fetch instead of relying on `FETCH_HEAD`, unlocks a scratch worktree this session locked before removing it, treats a missing runtime the tool needs like a missing tool (the check is `blocked`, its reading and classification still go in the report), says how to run a `## Run` slash command and resolve `<plugin-root>` when the plugin is not installed, says how a ticket-branch pass treats a folder the ticket does not touch, commits the refreshed verification with a subject that passes the repository's commit convention, reuses the recorded seeded break when the changes added no new behavior, and says the stale-coverage warning stays until the follow-up moves the sync commit.
- A seeded break's `change` in `sync.yaml` also names the model edit that carried it, where the check reads a model.
