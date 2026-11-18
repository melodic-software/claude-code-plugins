---
description: "Write, check and refresh formal-area skills: bare proposes what to prove; create PROMISE writes the model and skill, proving a seeded break is caught; check gates the contract; refresh realigns checks with changed code. Use when: 'what should we formally verify', 'model-check this race', 'prove this invariant', 'check our formal skills', 'is the model still true', or a race or state machine needs more than tests."
argument-hint: "[create [<promise>]|check [<dir> ...]|refresh [<dir> ...] [--convert <dir>]] [--unattended]"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: verify
  summary: Propose, create, check and refresh a repository's formal-area skills
---

**Arguments.** `[create [<promise>]|check [<dir> ...]|refresh [<dir> ...] [--convert <dir>]] [--unattended]`.
Each `<dir>` is a skill folder; `--unattended` applies to `create` and `refresh`. Quote a promise of
more than one word.
e.g. /formal-verification:specify, /formal-verification:specify create "a claimed item has one
holder", /formal-verification:specify check, /formal-verification:specify refresh

# Specify

A test checks the cases that someone thought to write. Formal verification checks every case in a
stated scope: every order of steps in a model, every input up to a bound, or every input. This skill
finds the part of the repo where that matters most, verifies one property of it, and leaves a
`formal-<area>` skill that lets the next agent check a change against that property. That skill
follows [the formal-area contract](../../reference/formal-skill.md)
(`${CLAUDE_PLUGIN_ROOT}/reference/formal-skill.md`); read it before any form below.

The reference files write this plugin's folder as `<plugin-root>`, which is `${CLAUDE_PLUGIN_ROOT}`;
when the plugin is not installed and runs from a checkout of its source, it is the folder that holds
its `.claude-plugin/plugin.json`. `"$PWD"` in a command is the repository root: pass its absolute
path where the shell's working directory does not carry between calls.

This skill names no verification tool. The question and the repository choose it, by
[`reference/choose-a-tool.md`](reference/choose-a-tool.md), and the choice is recorded only in the
area's `formal-<area>` skill, under `## Tool and why`.

## Forms

| Form | Writes | What it does |
|---|---|---|
| bare | nothing | Proposes the target. |
| `create "<promise>"` | the `formal-<area>` folder, after the yeses below | Builds and proves one check. |
| `create` with no promise | nothing until a yes | Shows the bare form's proposal and waits for a yes. |
| `create --unattended` | nothing | A dry run: the plan, and the open questions a person must answer. |
| `check [SKILL_DIR...]` | nothing | Runs the contract gate over each `formal-<area>` skill. |
| `refresh [SKILL_DIR...]` | the `formal-<area>` folder, in a commit of its own | Brings each check back in line with the code. |
| `refresh --convert SKILL_DIR` | that skill, as a `formal-<area>` folder | Converts a verification skill outside the contract, attended only. |

A run with no person present (a lane, CI, a model that invoked this skill with nobody to answer)
is unattended, whatever its arguments.

### Bare: propose

Follow [`reference/create.md`](reference/create.md) "Choose the target from the code" and "Let the
question choose the tool", and stop before anything is written. Give the strongest candidate first,
then up to two more, each as:

- **Promise:** one plain sentence, with the file and line that makes it.
- **Harm:** what breaks for a user when it fails, in one plain sentence.
- **Tool:** the tool and why, and whether it runs here: declared by this plugin's setup, found on
  this machine, or missing (with its official install page).
- **Folder:** the `formal-<area>` folder `create` would write, under the `skills_dir` setting.

Say once whether the repository's project instructions opt in to formal verification
([`reference/create.md`](reference/create.md) "Before anything" step 2). Then name the command that
takes it: `/formal-verification:specify create "<promise>"`.

### `create`

Follow [`reference/create.md`](reference/create.md) from the top. It checks the enforcement
ladder's opt-in first: without it, it goes on only on an attended yes for this run, and an
unattended run reports `blocked: formal verification not opted in`. It reads every existing
`formal-*` skill first, asks before it records a tool, makes its seeded break in a throwaway git
worktree, and hands off only after the check caught that break.

### `check`

Run the contract check. It reads each `formal-<area>` skill and its `sync.yaml`, and edits nothing:

```bash
node "${CLAUDE_PLUGIN_ROOT}/scripts/check.mjs" --project-dir "$PWD" [--default-ref <ref>] [SKILL_DIR...]
```

With no folder named it checks every `formal-*` folder under the `skills_dir` setting. Pass
`--default-ref` with the default branch's tip, read from its remote, as any ref or SHA git resolves
to a commit (a remote-tracking branch or the fetched SHA), so a sync commit that only the working
branch holds fails now rather than after the merge. It prints one
`FAIL` or `WARN` line per finding and a summary, and exits 0 with no failure, 1 with one, 2 when it
cannot run. The findings it reports are listed in the contract's "The contract check". Report the
lines as printed. A stale-coverage warning means the check needs another look, not that it fails:
say which check and which files.

### `refresh`

Follow [`reference/refresh.md`](reference/refresh.md) from the top. It finds each check, runs it
unchanged, reads every change to its covered code since the sync commit, updates the verification
from the code in a throwaway git worktree, reruns it with a seeded break, and ends each check
`in sync`, `updated`, `bug` or `blocked`. A property changes only on a person's yes. On a ticket
branch it commits there; otherwise on its own upkeep branch, through one pull request. Unattended,
it writes only for a check that ends `in sync` or `updated` with its seeded break caught.

## What makes it good

- **True to the code.** Every part of the model or proof points to code that a reviewer can open.
  What the verification treats as one indivisible step is one indivisible step in the code. Names
  come from this repo.
- **Able to fail.** A check that you have never seen fail proves nothing. Show each property failing
  on a broken variant of the code it guards, such as a removed check or a reordered step.
- **Findings stay findings.** When the current code breaks the property, report it with the
  counterexample in the code's terms. Do not weaken the property or the model until it passes, and
  do not change product code unless the user asks.
- **Honest about scope.** Say what is verified, under which bounds and assumptions, and what is left
  out. A pass covers the model or the bound, not the whole system.
- **Readable without the tool.** State the property and the harm in one plain sentence each. Tell a
  counterexample as a short sequence of steps in the code's words.
- **Cheap to rerun.** One command, a reproducible tool version, and a run short enough that the next
  agent will use it on every relevant change.
- **Kept in step with the code.** Record which files and functions each check covers, and the commit
  at which you last confirmed that the verification describes them. When the covered code changes
  after that commit, the next agent can see that the verification needs another look.

## Boundaries

- Never installs a verification tool, Java or a runtime. `/formal-verification:setup` installs only
  what this plugin declares, and only on a typed request.
- Reaches other skills by their slash command only, each with the fallback its step names when that
  plugin is not installed.
- Writes only inside the `formal-<area>` folder, the paths its `sync.yaml` lists under
  `outside_model`, and a skill `refresh --convert` names. Product code changes only in the throwaway
  worktree, which is discarded.

## Next

- A `formal-<area>` skill written and its seeded break caught: /verification:confirm.
- A counterexample that reproduces against the real code: /bugs:write.
- Covered code changed since a sync commit: /formal-verification:specify refresh.
- No verifier runs on the language: /testing:write.

## Gotchas

- `check` reads git history: in a shallow clone the sync commit is not there, and it fails as not
  an ancestor of `HEAD`.
- A `## Run` that words the command differently from its `sync.yaml` entry, or puts more on that
  line, fails `check`: give the command exactly, on a line of its own.
