# corrections

The skills of `plugins/corrections`. Each one is driven with `<plugin-dir>` set to `plugins/corrections`.

## Parts

- `codify`: Count a recurring mistake, pick the strongest rung and prove the check.

## Sub-features

none

## Entry points

- `/corrections:<skill> <args>` as the `logs` prompt, in print mode | driven
- `/corrections:<skill> <args>`, typed at the prompt of the terminal session | driven
- A request in plain words that names the skill's job, typed at the prompt | driven
- The same skill in Claude Desktop | not driven: terms

## Reset

The `## Reset` of the driving tool's `skills/invoke` feature.

## Drive

The action to drive for `codify` is `count-checks`, so `<args>` is `count-checks`: it counts the
checks the default branch's history records and changes nothing. Its result is text, and a
capture's public report redacts every observed text, so the terminal-session screenshot is what
shows it.

1. In the terminal session, `type "/corrections:codify count-checks" --key Enter --session <session>`.
   Result: the driver prints `typed`, and the slash command shows in the transcript.
2. `wait-for "not counted:" --session <session>`, then capture `screenshot`. Result: below the
   command the transcript shows the script's output: the headline `blocking checks: <n> new in the
   window, <n> cumulative; advisory: <n> new, <n> cumulative`, the table, and each list's title
   with its count and one line per record it names; the driver prints `seen: not counted:` and
   `screenshot` prints the `.png` path; with no such text by `stepMs`, `wait-for` exits 1.
3. For the plain-words and print-mode entry points, run steps 3 and 4 of the driving tool's
   `skills/invoke` feature with the same command. Result: the steps there state theirs.
4. **Proof.** Result: the screenshot shows, below `/corrections:codify count-checks`, the
   headline's blocking and advisory counts and every record line the output lists.
   Captures: screenshot

## Gotchas

- A skill marked `No slash command.` runs only from its plain-words entry point; one marked `No plain-words entry.` runs only from its slash command.
