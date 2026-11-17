# Create a formal-area skill

The steps of `/formal-verification:specify create`, in order. The bare form runs the first two and
stops. Write the generated skill for an agent who reads it cold, mid-change, and has never seen your
work. The user must be able to trust the result and act on it without learning the verification
language.

## Contents

- Before anything
- Choose the target from the code
- Let the question choose the tool
- Make sure the tool runs
- Write the rules and the model
- Generate the verify skill
- Prove it before you hand off
- When no verifier runs on the language
- Hand off

## Before anything

1. Resolve the settings: `node "<plugin-root>/scripts/settings.mjs" --project-dir "$PWD"`, with
   `<plugin-root>` as the skill renders it.
   `skills_dir` is where `formal-<area>` folders live.
2. Read every existing `formal-*` skill under `skills_dir`: its `## Property`, `## Tool and why`
   and `sync.yaml`. A promise one of them already verifies is not a new target: say which skill
   covers it. A tool one of them records is the first candidate for a like question.
3. Decide the mode. Unattended (`--unattended`, or no person present) is a dry run: carry out the
   reading and the choosing below, write nothing, and end with the plan and its open questions.

## Choose the target from the code

Answer from the codebase, and ask the user only what you cannot observe. If the user named an area,
a bug or a promise, start there.

A good target is a promise the code makes, where a break harms users and tests rarely reach the case
that breaks it. Choose the strongest such target in the repo, not the one that is easiest to verify.

With a promise given as the argument, find the code that makes it and quote that line. With none,
attended, show the bare form's proposal (promise, harm, tool, folder) and write nothing until the
user says yes to one of them.

Name the area in this repository's nouns: the folder is `<skills_dir>/formal-<area>/`.

## Let the question choose the tool

Follow [`choose-a-tool.md`](choose-a-tool.md). When the area has no tool recorded, research, recommend
one with its reason, and ask; record the answer only in the area's `## Tool and why`. Unattended, the
tool choice is an open question unless an existing `formal-*` skill already records one for this
area.

## Make sure the tool runs

Never install a verification tool. Run the tool's own version or help command, as its official
documentation gives it, before writing anything:

- **It runs:** go on.
- **It is missing, and `<plugin-root>/prerequisites.json` declares it with a `/formal-verification:setup`
  check:** attended, tell the user to type `/formal-verification:setup` and stop; unattended, report
  `blocked: tool missing: <tool>` and stop.
- **It is missing, and nothing in this plugin declares it:** name the tool, the reason it fits, and
  its official install page, and stop. Unattended, report `blocked: tool missing: <tool>` with the
  same three facts.

When a skill of this plugin declares the chosen tool in its description, that skill runs it: the
generated skill's `## Run` names it by its slash command, and its commands, options and paths are
copied nowhere.

## Write the rules and the model

1. Draft each rule the property needs, in one plain sentence, with the line of code or contract it
   encodes quoted beside it, and its path. Show the list and wait for the user's yes before any check
   runs: the user owns the rules. Unattended, the list is an open question.
2. Write the model, proof or harness under `formal-<area>/model/`, in this repository's names. When a
   skill of this plugin declares the tool, write it by that skill's own writing rules. A file outside
   `model/` is allowed only when `sync.yaml` lists it under `outside_model`.
3. Run the check on the code as it stands. A rule that breaks is a finding: replay it against the
   real code, one step per action, before calling it a bug. If a bug does not occur, think that the
   model is wrong until you show that it is not. Write a reproduced bug up with `/bugs:write` (if
   installed; otherwise as a report with title, steps, expected and actual, severity and where to
   fix). Never weaken a rule to make it hold.

## Generate the verify skill

Write the `formal-<area>` skill the contract describes: frontmatter that names the area and says
when to use it, the eight sections in order, and `sync.yaml`. Without frontmatter, the skill never
registers. From the skill alone, the next agent must be able to tell whether a change touches the
verified code, run the check, tell a real bug from a modeling error, and update the verification when
a change is intended. Put the coverage record and the sync commit in `sync.yaml`, and tell the next
agent to move the sync commit forward only after it confirms that the verification describes the
code at the new commit. Use this repo's real commands, paths, and nouns, and leave no placeholders.

Each `sync.yaml` entry's `command` is the same text its `## Run` gives. Until the seeded break below
is caught, `seeded_break.caught` is `false`.

## Prove it before you hand off

Follow the generated skill once, as the next agent would, on a scratch change that breaks the
property in the real code. It must catch the break.

1. Make the scratch change in a throwaway git worktree, never the person's working tree:
   `git worktree add --detach <scratch folder outside the repository> HEAD`, then copy the new
   `formal-<area>` folder into it.
2. Break the property there, such as a removed check or a reordered step. Where the check reads a
   model rather than the code, follow the skill's `## Updating` in the worktree to carry the break
   into the model copy.
3. Run the skill's `## Run` command from the worktree. The check must fail on the rule the break
   targets.
4. Remove the worktree (`git worktree remove --force <scratch folder>`). It is outside the unattended
   write boundary, and nothing from it is kept.
5. Record the break in `sync.yaml`: `change` in the code's words, `caught: true`, and the commit it
   was made against.
6. Run every check in `sync.yaml` again on the unbroken tree: each is back where it started,
   passing, or failing only on the findings you will report.

When `sync.yaml` already records a seeded break for a check, reuse it in step 2, and still run the
full rerun in step 6. A verify skill that was never run is a draft. If the skill misses the break or
a step does not run, fix the skill or the verification, not the scratch change.

Then run `/formal-verification:specify check` on the new folder: it must pass.

## When no verifier runs on the language

Say so, and test the real code with generated inputs, not a hand model of the function. Hand off to
`/testing:write` for its property-based tests (if installed; otherwise write generated-input tests
with the repository's own test framework and conventions). Write no `formal-<area>` skill, and report
that the area has property tests, not formal verification.

## Hand off

Tell the user what you verified, which tool you used and why, the bounds, what the check found in
plain words, how to run it, and what it does not cover. Suggest a second target only if you found a
close one.

Unattended, the hand-off is the dry run: the target, the tool and its status, the folder, the rules
drafted, and each open question with a recommended answer.
