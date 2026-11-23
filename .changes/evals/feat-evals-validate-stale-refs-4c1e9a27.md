---
bump: minor
---

### Added

- `/evals:validate` fails a dangling reference: a prompt whose leading `/<plugin>:<skill>` names no skill, a `context.scaffold_script`, `history_file` or `add_dirs` entry missing from the case directory, a `tool_used` grader on `Skill` or `Agent` whose `input_match` names a skill or agent that does not exist as a literal token, and a `<plugin>:<skill>` tag that names no skill. The name checks resolve skills and agents under the nearest `plugins/` directory above the suite.
