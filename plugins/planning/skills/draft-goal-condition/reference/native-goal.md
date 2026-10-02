# The built-in `/goal` command: verification record

Detail behind the `## Boundary` section in [SKILL.md](../SKILL.md). Each row is a four-part
record: the claim, the basis it rests on, the date it was checked, and the event that makes it
worth checking again. The condition shape and character limit are not recorded here: Step 1 reads
them live on every run.

| Claim | Basis | As of | Recheck when |
|---|---|---|---|
| `goal` is a built-in command described as "Set a goal Claude checks before stopping", argument `[<condition> \| clear]`, no alias | The `/harness-ops:inventory` extraction of the installed 2.1.284 binary (`builtin_commands.goal`) | 2026-09-29 | A release renames or removes `goal`, or changes its description or argument |
| It is user-invocable and not model-invocable, and it is not gated behind a setting | Same extraction: `user_invocable: true`, `model_invocable: false`, `gated: false` | 2026-09-29 | A release changes its invocability or adds a gate |
| `/goal [condition\|clear]` keeps Claude working across turns until the condition is met; no argument shows the current or most recently achieved goal; `clear`, `stop`, `off`, `reset`, `none`, or `cancel` removes an active goal | The `/goal` row on <https://code.claude.com/docs/en/commands> | 2026-09-29 | The commands page row changes or disappears |
| The command arrived in 2.1.139, working in interactive, `-p`, and Remote Control sessions | Claude Code changelog, 2.1.139 ("Added `/goal` command") | 2026-09-29 | A release note changes where `/goal` runs |
| `ProposeGoal` is a built-in tool described as "Propose a session goal condition, with one-keypress user approval; once set, Claude keeps working until a separate evaluator confirms it is met"; model-invocable, not user-invocable, gated, deferred; not on the tools reference | The `/harness-ops:inventory` extraction of the installed 2.1.285 binary (`builtin_tools.ProposeGoal`); <https://code.claude.com/docs/en/tools-reference> has no row | 2026-10-01 | A release renames or removes the tool, changes its invocability or gate, or the tools reference documents it |
| A `ProposeGoal` condition is at most 500 characters, measured after canonicalizing for display (tabs expand to spaces); a longer one is refused. The `/goal` command's own limit is read live in Step 1 and is not this one | The tool's prompt (`in at most ${500} characters`) and its refusal string in the same 2.1.285 binary, read by string search. No upstream page documents the tool: <https://code.claude.com/docs/en/tools-reference> has no row and <https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md> has no entry for it | 2026-10-01 | A release changes the cap or how the condition is canonicalized, or either upstream page starts documenting the tool |
| `ask_user` defaults to true (one-keypress approval dialog); false sets the goal with no dialog and is meant only when the person's own words stated the outcome; the tool cannot clear a goal; it is refused in agent contexts, outside interactive local sessions, and while plan mode is active | The tool's prompt and refusal strings in the same 2.1.285 binary, read by string search; undocumented upstream on the same two pages | 2026-10-01 | A release changes the `ask_user` default or any of these restrictions, or either upstream page starts documenting the tool |

## Why the verdict is complementary

`/goal` runs a condition; it does not write one. This skill writes the condition: it checks the
lever fits, drafts against the live shape, and proves the length with a counter. The person then
runs the native command with the drafted text. The model never arms a goal, so the two compose in
sequence and neither replaces the other. `ProposeGoal` only changes how the drafted text reaches
the person: a one-keypress approval instead of a paste. The person still decides. Because the
tool's cap and restrictions are known only from the binary, a wrong reading costs one refused
proposal and nothing more: the paste-ready `/goal` line is emitted whether or not the tool is
used.
