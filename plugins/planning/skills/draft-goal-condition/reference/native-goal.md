# The built-in `/goal` command: verification record

Detail behind the `## Boundary` section in [SKILL.md](../SKILL.md). Each row is a four-part
record: the claim, the basis it rests on, the date it was checked, and the event that makes it
worth checking again. The condition shape and character limit are not recorded here: Step 1 reads
them live on every run.

| Claim | Basis | As of | Recheck when |
|---|---|---|---|
| `goal` is a built-in command described as "Set a goal Claude checks before stopping", argument `[<condition> \| clear]`, no alias | The `/harness-ops:inventory` extraction of the installed 2.1.284 binary (`builtin_commands.goal`) | 2026-09-29 | A release renames or removes `goal`, or changes its description or argument |
| It is user-invocable and not model-invocable, and it is not gated behind a setting | Same extraction: `user_invocable: true`, `model_invocable: false`, `gated: false` | 2026-09-29 | A release changes its invocability or adds a gate |
| `/goal` keeps Claude working across turns until a condition holds, and can be cleared; what a bare `/goal` shows and which words clear a goal are read live | [goal: set a goal](https://code.claude.com/docs/en/goal#set-a-goal), [goal: check status](https://code.claude.com/docs/en/goal#check-status) and [goal: clear a goal](https://code.claude.com/docs/en/goal#clear-a-goal) | 2026-10-11 | Set a goal changes how a goal is set, Check status changes what a bare `/goal` shows, or Clear a goal changes how a goal is cleared |
| A goal's fate across a session resume and a `/clear` is read live for the Step 4 user note | [goal: resume with an active goal](https://code.claude.com/docs/en/goal#resume-with-an-active-goal) and [goal: clear a goal](https://code.claude.com/docs/en/goal#clear-a-goal) | 2026-10-11 | Resume with an active goal changes what a resume restores or resets, or Clear a goal changes whether `/clear` removes a goal |
| `/goal` also runs outside an interactive session; which session kinds it runs in is read live | [goal: run non-interactively](https://code.claude.com/docs/en/goal#run-non-interactively) | 2026-10-11 | That section changes where `/goal` runs |
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
