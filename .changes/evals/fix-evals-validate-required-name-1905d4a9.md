---
bump: patch
---

### Fixed

- **`/evals:validate` fails every case field `claude plugin eval` marks required.** A case with a `case.yaml` but no `name` (or `schema_version`) in it or in `prompt.md` frontmatter, a case with no prompt, a grader missing an option its type requires (regex `pattern`, tool_used `tool`, tool_order `before`/`after`, file_exists `path`, llm `criteria`, baseline `baseline_file`/`criteria`), and a `schema_version` that is unquoted or has no leading major now FAIL instead of passing at exit 0. The required set is re-derived from the Claude Code 2.1.296 case schema and each rejection was reproduced with the CLI (#6673).
