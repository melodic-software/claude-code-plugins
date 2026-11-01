# skill-quality/check

Lints a skill's `SKILL.md` and evals against the skill standard, and reports the shared listing budget.

## Parts

- `check <skill-or-root>`: the static contract gate, PASS or FAIL with warnings.
- `validate-evals <skill>`: checks a skill's existing legacy `evals/evals.json` against the bundled
  schema. New cases use the plugin suite format, `plugins/<plugin>/evals/<case>/case.yaml`, checked
  with `/evals:validate`.
- `listing-budget <root>`: the shared listing-budget estimate.
- `measure-invocation`: scores description auto-invocation probes.

## Sub-features

none

## Entry points

- `/skill-quality:check check <skill-or-root>` as the `logs` prompt, in print mode | not driven: every action runs Bash, absent from the tools of the restricted launch in the init event of the 2026-10-28 `discipline/tighten-your-output` proof run (pointer: hub Gotchas)
- `/skill-quality:check check <skill-or-root>`, typed at the prompt of the terminal session | not driven: every action runs Bash, absent from the tools of the restricted launch in the init event of the 2026-10-28 `discipline/tighten-your-output` proof run (pointer: hub Gotchas)
- A request in plain words to lint a skill, typed at the prompt | not driven: every action runs Bash, absent from the tools of the restricted launch in the init event of the 2026-10-28 `discipline/tighten-your-output` proof run (pointer: hub Gotchas)
- The same skill in Claude Desktop | not driven: terms

## Reset

None: every action only reports.

## Drive

No step runs: every entry point is `not driven`.

## Gotchas

- Run the action's script under `plugins/skill-quality/scripts/` directly instead; never drop the
  driver's `--restricted` flag to reach Bash.
