---
bump: patch
---

### Fixed

- go-faster: Step 1 now resolves Python when the Bash tool's shell is zsh. The preamble runs the new `scripts/resolve-python.sh` with `bash` instead of sourcing the bash-only `harness-lib.sh` into the calling shell, where zsh rejected `type -P` and reported `PY=unresolved`. The verify skill names `command -v python3`, not `type -P python3`, for the interpreter the Bash tool's shell resolves. The go-faster-sweeper agent now names `scripts/` as the home of `harness-lib.sh` and `findings.py`, so it looks there when reproducing a reported failure.
