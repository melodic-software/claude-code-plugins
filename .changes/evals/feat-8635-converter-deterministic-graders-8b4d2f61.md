---
bump: minor
---

### Added

- `convert-evals-json.py` writes a deterministic grader instead of an `llm` judge when an expectation's whole wording is a mechanical check: the case's own skill invoked or one of the plugin's skills not invoked (`tool_used` on Skill), a backticked command run or not run (`tool_used` on Bash, its words in order), a backticked literal or `/<plugin>:<skill>` named in the reply (`regex`), or a file written at a path when the case can create files (`file_exists`). Each gets pass and fail samples that `/evals:validate` grades offline. Any qualifier, placeholder, slash command or other plugin's skill keeps the expectation an `llm` judgment.
