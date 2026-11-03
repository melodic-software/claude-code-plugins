# Boundary, the built-in `plugin eval` command

- The **CLI** (`plugin eval`, a built-in command) owns execution, grading, the ablation arms, the JSON and the HTML report. It is gated
  by the version floor under the hub's [Preflight](../SKILL.md#preflight), so this skill reads the version and never assumes the
  command is available. This skill owns what surrounds a spend: the preflight, the no-spend
  validation, the estimate and ceiling, target routing and the reading discipline. It never re-implements grading and never simulates a run or a score.
- Success criteria and case design belong to `/evals:design`; come here once a suite exists.
- The skill-creator JSON eval format is not a suite this command reads. Convert its cases to case
  directories (`/evals:design skill <name>` writes them), check those with `/evals:validate`, then
  run them here. To move one plugin's `evals.json` cases into its suite, run `python3 "<skill-dir>/scripts/convert-evals-json.py" <plugin-dir>` (`--dry-run` prints the case count and writes nothing; `--help` prints what it writes), then `/evals:validate` on the plugin's `evals/`.
