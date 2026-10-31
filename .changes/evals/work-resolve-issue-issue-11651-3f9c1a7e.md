---
bump: minor
---

### Added

- `skills/plugin-eval/scripts/convert-evals-json.py <plugin-dir>` converts one plugin's
  skill-creator `evals.json` cases into `claude plugin eval` cases under the plugin's `evals/`:
  a `prompt.md` with the prompt and expected outcome, a `case.yaml` with one `llm` grader per
  expectation, and a `skill-fired` grader with sample answers where the prompt is natural
  language and no expectation reads as the skill staying quiet. It prints the plugin's case count (`--dry-run` writes nothing), removes each converted
  `evals.json`, and refuses, writing nothing, when a case directory already exists.
