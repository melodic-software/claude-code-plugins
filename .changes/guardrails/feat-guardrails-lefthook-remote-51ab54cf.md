---
bump: minor
---

### Added

- `apply install-git-hooks scope=shared` in a lefthook repository, or one with no hook manager yet, now adds one `remotes:` entry to the committed `lefthook.yml` instead of committing copies under `.githooks/guardrails/`: lefthook fetches `git-hooks/lefthook-remote.yml` and its scripts from this marketplace repository's `main` and refetches them every 24 hours, so every clone runs the current hooks with no refresh pull request and no lint exclusion. `install.mjs plan --scope remote` returns the snippet; `verify` reports each entry `ok` once the config carries the remote, `lefthook install` has written the event hook and the remote is fetched, and `missing` with "run lefthook install" otherwise, so the session-start notice also catches a first install made offline. A repository holding the earlier shared copies gets a `migrate` decision (`from: shared`) naming `.githooks/guardrails/` and the old `guardrails-<entry>` jobs to remove. Husky and plain hooks keep the shared copies, and so does a lefthook config that sets its own `source_dir` (a `remote-source-dir` decision), because lefthook then looks for the remote's scripts in a directory the fetched copy does not have.
