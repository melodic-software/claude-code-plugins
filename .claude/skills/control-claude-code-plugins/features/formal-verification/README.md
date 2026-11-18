# formal-verification

The skills of `plugins/formal-verification`. Each one is driven with `<plugin-dir>` set to `plugins/formal-verification`.

## Parts

- `chart`: Check a TLA+ spec with TLC, chart its states, path each broken rule.
- `setup`: Report the formal-verification toolchain, or install the pinned model checker or renderer on request. No plain-words entry.
- `specify`: Propose, create, check and refresh a repository's formal-area skills.

## Sub-features

none

## Entry points

- `/formal-verification:<skill> <args>` as the `logs` prompt, in print mode | driven
- `/formal-verification:<skill> <args>`, typed at the prompt of the terminal session | driven
- A request in plain words that names the skill's job, typed at the prompt | driven
- The same skill in Claude Desktop | not driven: terms

## Reset

The `## Reset` of the driving tool's `skills/invoke` feature.

## Drive

Drive `chart` and `setup` as the driving tool's `skills/invoke` feature, with `<plugin>` set to
`formal-verification` and `<skill>` from Parts. The skill's own
`plugins/formal-verification/skills/<skill>/SKILL.md` gives its arguments.
The action to drive for `specify` is `check`, so `<args>` is `check`: it runs the contract check
over every `formal-<area>` skill and edits nothing. Its result is text, and a capture's public
report redacts every observed text, so the terminal-session screenshot is what shows it.

1. In the terminal session, `type "/formal-verification:specify check" --key Enter --session <session>`.
   Result: the driver prints `typed`, and the slash command shows in the transcript.
2. `wait-for "formal-verification check:" --session <session>`, then capture `screenshot`. Result:
   below the command the transcript shows each `FAIL` or `WARN` line the check printed and its
   summary line, `formal-verification check: <n> formal-<area> skill(s), <n> failure(s), <n>
   warning(s)`; the driver prints `seen: formal-verification check:` and `screenshot` prints the
   `.png` path; with no such text by `stepMs`, `wait-for` exits 1.
3. For the plain-words and print-mode entry points, run steps 3 and 4 of the driving tool's
   `skills/invoke` feature with the same command. Result: the steps there state theirs.
4. **Proof.** Result: the screenshot shows, below `/formal-verification:specify check`, the
   summary line's skill, failure and warning counts and each `FAIL` or `WARN` line.
   Captures: screenshot

The three counts are the numbers in the summary line of the print-mode `logs` capture, in the
order it prints them; a count is `null` when the capture holds no summary line.

Budget: formal_area_skills_count | logs
Budget: check_failures_count | logs
Budget: check_warnings_count | logs

## Gotchas

- A skill marked `No slash command.` runs only from its plain-words entry point; one marked `No plain-words entry.` runs only from its slash command.
- `check` runs its script through Bash and reads git history, so it needs the shell and the clone the hub's Gotchas describe; the skill's own `## Gotchas` says what a shallow clone does.
