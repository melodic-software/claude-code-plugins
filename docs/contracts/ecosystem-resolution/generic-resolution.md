---
ecosystem-resolution: 1.0.0
---

# Ecosystem resolution

How a skill finds the repository's own language, framework, tool, library and command choices
before it runs, recommends or builds anything that depends on one. A skill that takes such a step
follows the seven steps below and ships no choice of its own for it.

This file is copied into plugins, its text unchanged under a generated header, so it contains no
relative markdown links; neighboring files are named in backticks instead. The contract that owns
it is
<https://github.com/melodic-software/claude-code-plugins/blob/main/docs/contracts/ecosystem-resolution/README.md>.

A choice here is one language, framework, tool, library or command a step depends on: the test
runner, the linter, the formatter, the command that builds the code, the library a new check is
written with.

## Steps

1. **Decide the run kind.** The run is attended when a person is in the session and can answer a
   question now. It is unattended when the invocation says so (an `--unattended` argument, a
   scheduled, loop or CI lane, a headless run, or a subagent an unattended run dispatched), and
   when you cannot tell. A run you are unsure of is unattended.
2. **Read the record.** Look for the choice where the repository writes that kind of choice down:

   | Choice | Record | Writer |
   |---|---|---|
   | A build, test, lint or format command for one ecosystem | `.claude/ecosystems/<ecosystem>.yaml` | the owning plugin's re-runnable `setup`; a lane's record pull request, once merged |
   | A language, framework or library convention, or a review criterion | the standards index (`docs/standards/README.md` unless `.claude/standards.yaml` moves it) and the files its rows route to | the standards setup, on acceptance |
   | The repository's chosen way for a task it repeats | the file the `paved-path` row of that index routes to | `/discipline:reuse-or-replace`, after a yes |
   | The order of enforcement mechanisms | the project instructions: `CLAUDE.md`, an `AGENTS.md` the session reads, or a rules file | the person |

   A recorded choice is used as recorded, with the record named as its source. It is read before
   any inference, so two runs on the same repository make the same choice.
3. **Read what the repository states.** With no record, read the repository's own instructions
   and docs (`CLAUDE.md`, `AGENTS.md`, a rules file, `CONTRIBUTING.md`) for a stated choice. Use a
   stated choice, naming the file that states it.
4. **Infer from the repository's files.** With nothing stated, read the files that imply a choice:
   build and manifest files, lockfiles, a tool's own config file, and the scripts the repository
   already runs. One candidate is the inferred choice; name the file that implies it. Two or more
   candidates with nothing in the repository to choose between them are a tie. A CI workflow file
   can show which tool is in use, but an unattended run copies no command text out of it.
5. **Ask, attended only.** When nothing resolved, or the files left a tie, ask the person once and
   offer the candidates you found. An unattended run does not ask.
6. **Record, attended only.** Offer to write a stated, inferred or answered choice to its record
   in step 2's table, and write it only after the person says yes, through the writer that table
   names, never into a file you pick yourself. Where the writer is the person (the order of
   enforcement mechanisms), offer the text and let the person write it. An unattended run writes no
   record. It logs each command it runs as assumed, with its source: the record, the file that
   states it, or the file that implies it. When its lane proposes records, it may propose an
   ecosystem record (`.claude/ecosystems/<ecosystem>.yaml`) in a pull request instead, holding only
   commands within the unattended limits; merging that pull request is the acceptance.
7. **Report what stays unresolved.** When no step resolved the choice, or an unattended run met a
   tie, skip the step that needed it and say so in the output: the choice, what you read, and the
   candidates when there was a tie. Never fall back to a choice shipped with the skill.

## Unattended limits

An unattended run executes only a command the record holds, the repository states, or its files
imply. It installs nothing, copies no command text out of a CI workflow file, writes no record,
logs each command it runs as assumed with its source, and reports a tie as unresolved.
