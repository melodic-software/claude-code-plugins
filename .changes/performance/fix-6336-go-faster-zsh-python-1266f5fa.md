---
bump: patch
---

### Fixed

- go-faster: Step 1 now resolves Python when the Bash tool's shell is zsh. The preamble runs the bash-only `harness-lib.sh` under `bash` itself instead of sourcing it into the calling shell, where zsh rejected `type -P` and reported `PY=unresolved`. The go-faster-sweeper agent now names `scripts/` as the home of `harness-lib.sh` and `findings.py`, so it looks there when reproducing a reported failure.
