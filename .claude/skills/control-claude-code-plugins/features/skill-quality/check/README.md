# skill-quality/check

Lints a skill's `SKILL.md` and evals against the skill standard, and reports the shared listing budget.

## Parts

- `check <skill-or-root>`: the static contract gate, PASS or FAIL with warnings.
- `validate-evals <skill>`: checks `evals/evals.json` against the bundled schema.
- `listing-budget <root>`: the shared listing-budget estimate.
- `measure-invocation`: scores description auto-invocation probes.

## Sub-features

none

## Entry points

- `/skill-quality:check check <skill-or-root>` as the `logs` prompt, in print mode | not driven: the restricted launch removes Bash, which every action runs
- `/skill-quality:check check <skill-or-root>`, typed at the prompt of the terminal session | not driven: the restricted launch removes Bash, which every action runs
- A request in plain words to lint a skill, typed at the prompt | not driven: the restricted launch removes Bash, which every action runs
- The same skill in Claude Desktop | not driven: terms

## Reset

None: every action only reports.

## Drive

No step runs: every entry point is `not driven`.

## Gotchas

- Run the action's script under `plugins/skill-quality/scripts/` directly instead; dropping the
  driver's `--restricted` flag to reach Bash is not an option.
