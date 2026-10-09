---
bump: patch
---

### Changed

- **block-root-delete-target outside-tree message.** The block now names the allowed roots and the session scratchpad first, says "do not retry the delete with another tool (find -delete, rmtree, git clean)", and keeps the user hand-off as the last resort.
- **block-dangerous-git lease-width hint.** When the repository's hash format cannot be read, the hint is now `git -C <repo> push --force-with-lease=<ref>:<full-sha>`, a form the width probe follows, in place of "Run the push from inside the repository", whose `cd <repo> && git push` spelling the guard itself refuses from a session root that is not a repository.

### Fixed

- **block-credential-read missed jq and two credential files.** `cat`, `Get-Content`, `gc` and `type` of `.credentials.json` or `.docker/config.json`, `jq` of either file, and `jq env` / `jq '$ENV'` (which print every variable) now block. The pre-filter admits `docker` and `env`, so these shapes reach the matcher. `jq . package.json`, `jq -n '$ENV.HOME'` and a `.env` jq filter still pass.
