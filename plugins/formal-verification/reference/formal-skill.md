# The shape of a formal-area skill

The contract a consumer's `formal-<area>` skill follows. It is the one surface this plugin's skills
share: a skill that writes or checks a `formal-<area>` skill reads this file, never another skill's
commands. A test checks the cases that someone thought to write. Formal verification checks every
case in a stated scope: every order of steps in a model, every input up to a bound, or every input.
A `formal-<area>` skill verifies one area's property and lets the next agent check a change against
it. Write it for an agent who reads it cold, mid-change, and has never seen your work. The user must
be able to trust the result and act on it without learning the verification language.

## Contents

- Layout
- The contract check
- Frontmatter
- Sections
- sync.yaml
- The view file
- Where files go
- What makes it good

## Layout

```text
.claude/skills/formal-<area>/
├── SKILL.md      the frontmatter and sections below
├── sync.yaml     one entry per check
└── model/        spec, config, view file and any harness
```

`<area>` names the promise in this repository's nouns, in lowercase words joined by `-`. The
folder holding these skills is the `skills_dir` key of `docs/conventions/formal-verification.yaml`,
`.claude/skills` by default.

## The contract check

`/formal-verification:specify check` runs a script that passes or fails each `formal-<area>` skill
against this file and edits nothing. It fails on missing or wrong frontmatter, a missing section or
sections out of the order below, a missing or invalid `sync.yaml` (an `outside_model` entry that is
absolute or holds a `..` segment included), a sync commit that is not an ancestor of `HEAD`, a
covered path missing at `HEAD`, a check whose command `## Run` does not give on a line of its own,
and a folder, `SKILL.md` or `sync.yaml` that is a symlink or lies outside the repository, which it
never reads. It warns on covered code changed
since the sync commit (a failure under `on_stale: fail`), naming the check and
`/formal-verification:specify refresh`, and on a skill folder that holds a
`sync.yaml` or a `model/` but is not named `formal-<area>`. Given the default branch's ref
(`--default-ref`), it also fails a sync or seeded-break commit that is not on that branch, and
warns once, skipping that check, when the ref does not resolve.

## Frontmatter

`name` is `formal-<area>`, and `description` names the area and says when to use the skill: the
files whose change calls for the check, and the question it answers. Without frontmatter the skill
never registers. Nothing else is required.

## Sections

The body holds these sections, in this order, each under its own `##` heading:

| Section | Holds |
|---|---|
| `## Property` | The promise, in one plain sentence per checked rule. For each rule, the line of code or contract it encodes, quoted, with its path. |
| `## Harm` | What breaks for a user when the property fails, in one plain sentence. |
| `## Tool and why` | The verification tool, and why it fits this question. |
| `## Bounds and assumptions` | Every bound the check runs under (constants, state limits), and every assumption the model makes about the world. A pass covers the model or the bound, not the whole system. |
| `## Not covered` | What the check leaves out, and the documented limits it reports as known limits rather than defects. |
| `## Run` | The command for each check, the same one its `sync.yaml` entry records, with any per-model bound as an argument. |
| `## Reading a result` | How to tell a real bug from a modeling error: replay each counterexample against the real code, one step per action. "If a bug does not occur, think that the model is wrong until you show that it is not." |
| `## Updating` | How to change the model when the code changes on purpose, and when to move a sync commit: only after confirming the verification describes the code at the new commit, and only to a commit on the default branch. When a change edits the covered code itself, its stale-coverage warning is expected until the change lands; the sync commit moves in a follow-up change after it lands. |

Use this repository's real commands, paths and nouns, and leave no placeholders.

## sync.yaml

One entry per check, under a top-level `checks:` list. Every key is required.

| Key | Holds |
|---|---|
| `id` | The check's name, unique in the file. |
| `covers` | The repository paths whose change can make the check stale: files, or globs where `**` crosses `/`. |
| `commit` | The sync commit: the last commit at which someone confirmed the verification describes the covered code. It is a commit already on the repository's default branch, resolved from the repository (the merge base of the working branch and the default branch, or a later default-branch commit) at which the covered files are identical to the ones confirmed, never a commit only a feature branch holds: a squash or rebase merge discards that commit. |
| `command` | The command that runs the check, as `## Run` gives it. |
| `seeded_break` | The break that showed the check can fail: `change` (what was broken in the covered code), `caught` (`true` once the check caught it) and `commit` (the default-branch commit the break was made against, chosen as for the sync commit). |

Before the check has run against a seeded break, `seeded_break.caught` is `false`, and the skill
says so under `## Bounds and assumptions`. An optional top-level `outside_model:` list names model
files kept outside `model/`. An optional `on_stale` on an entry, `warn` or `fail`, says what the
contract check reports when that check's covered code changed after its sync commit; without it the
`check.on_stale` key of `docs/conventions/formal-verification.yaml` decides, and that key defaults
to `warn`.

```yaml
checks:
  - id: lease-arbitration
    covers:
      - plugins/work-items/tools/work-item-tracker/adapters/github/claim.sh
    commit: 0123456789abcdef0123456789abcdef01234567
    command: /formal-verification:chart .claude/skills/formal-claims/model/Claims.tla --view .claude/skills/formal-claims/model/view.mjs
    seeded_break:
      change: arbitration picks the latest live lease instead of the earliest
      caught: true
      commit: 0123456789abcdef0123456789abcdef01234567
outside_model: []
```

## The view file

A TLA+ check carries `model/view.mjs`, the view module `/formal-verification:chart` takes with
`--view`. It exports `state(vars)` and, as the chart needs them, `step(action, from, to)`,
`group(vars)`, `colors` and `title`. Its labels use the reader's words: what the reader can see or
cares about, never a variable name or a TLA+ action. The chart skill's own reference describes what
each export returns.

## Where files go

- Model files live in `formal-<area>/model/`. A file outside it is allowed only when `sync.yaml`
  lists it under `outside_model`.
- An unattended run writes only inside the `formal-<area>` folder and the paths `outside_model`
  lists. A seeded break made in a throwaway worktree is discarded with that worktree and is outside
  this boundary.
- The skill never edits product code. A change to product code is a separate change of its own.

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

A TLA+ check is read with `/formal-verification:chart`, named by its slash command only: its
scripts, options and file paths change between releases and machines, so a `formal-<area>` skill
copies none of them.
