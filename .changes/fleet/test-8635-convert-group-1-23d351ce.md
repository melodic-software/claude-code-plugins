---
bump: patch
---

### Changed

- The eval suite moved from `skills/*/evals/evals.json` to `evals/<case>/case.yaml` and `prompt.md`, with deterministic graders where an expectation is mechanical ([#8635](https://github.com/melodic-software/claude-code-plugins/issues/8635)).
- Each converted case runs against the made-up fleet manifest the other cases use, with no Bash grant, and is named for what it checks.
- `/fleet:reach` reads FLEET.md under the session's `$HOME` and, when that read is refused, finds it with a Glob there; its description also triggers on a failing ssh to the desktop, one account for every lane, and an allow rule for remote claude runs.
