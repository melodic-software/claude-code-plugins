---
bump: patch
---

### Security

- The convention resolver (`resolve-convention-pattern.sh`, run by `block-convention-violation`) and `stale-path-verify` no longer start the `core.fsmonitor` command a repository's own config names: their `git ls-files` and `git check-ignore` calls pass `--no-pager -c core.fsmonitor=false -c core.hooksPath=/dev/null`. The other git calls guardrails hooks make (`rev-parse`, `show`, `config`, `branch`, `log`) take the same overrides, through `hook::git_untrusted` where the hook loads `hook-utils.sh`.
