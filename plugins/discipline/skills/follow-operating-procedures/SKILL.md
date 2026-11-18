---
description: "Rereads the user's and the project's instruction files in force, checks the work in flight against them, and corrects drift or reports the work clean. Use when: 'follow operating procedures', 'follow your operating procedures', 'reread my instructions', 'reread CLAUDE.md', 'remember how I want you to operate', 'you're operating outside my instructions', 'remind yourself how we work here'."
user-invocable: true
disable-model-invocation: false
allowed-tools: Bash(date -u +%Y-%m-%dT%H:%M:%SZ), PowerShell(date -u +%Y-%m-%dT%H:%M:%SZ)
metadata:
  discipline-batch: never  # invoked only: rereading every instruction file is too costly to batch
  workflow-stage: anytime
  summary: Reread the instruction files in force and audit the work in flight against them
---

# Follow operating procedures

A drift corrector for the operating procedures the user and the project have written into their
instruction files. The shared method (re-anchor, audit the work in flight, correct forward, report)
lives in
[`${CLAUDE_PLUGIN_ROOT}/context/re-anchor-audit-correct.md`](../../context/re-anchor-audit-correct.md).
Read it; this file adds only what is specific to operating procedures.

Invocation marker: !`date -u +%Y-%m-%dT%H:%M:%SZ`

The marker is there so each invocation renders differently: when a repeat invocation's content
matches the copy in context, Claude Code adds only a note instead of the content
([Skill content lifecycle](https://code.claude.com/docs/en/skills#skill-content-lifecycle)). It is
not the time: never report or use it as one.

This skill holds no procedures of its own. The instruction files are the only source.

## The source set

Every instruction file Claude Code loads for this session, and no other agent's instruction files.
Claude Code decides which files those are and in what order; read
[CLAUDE.md files](https://code.claude.com/docs/en/memory#choose-where-to-put-claude-md-files) and
[How CLAUDE.md files load](https://code.claude.com/docs/en/memory#how-claude-md-files-load) when
unsure, and include every file each one imports. That set covers the files above the working
directory loaded at launch, wherever the walk ends, and every file loaded on demand since: nested
instruction files in subdirectories and rules files already in this session's context.

An import the instructions themselves call optional, or skip when absent, is not missing.

## Declared deltas from the shared loop

1. **Step 1 rereads the files.** The method treats loading the skill as the re-anchor. Here, read
   each file in the source set with the Read tool in this turn, on every invocation, even when an
   earlier copy is in context. Then read an on-demand file those instructions point to only when
   its stated trigger matches the current work.
2. **No portable baseline.** This skill replaces the method's baseline rung. When no file in the
   source set exists, say so in one line and stop.
3. **Missing or unreadable file.** Name each file in the source set that is missing or could not be
   read, then continue with the rest.

Step 1 is done when every file in the source set was read in this turn or named as missing.

## Audit and report

- Audit only against text read in this turn, and cite the file and line each finding breaks.
- Drift with a clear rule is corrected in the working tree this turn. Drift that turns on judgment
  follows the method's verification level.
- Drift that needs an outward action (a pull request, an issue, a comment) is reported open. This
  skill takes no outward action; the instructions' own authority applies again after the report.
- Report in a few lines: the files read, any file missing or unreadable, each finding with its
  citation and what was done, or `clean`.
- **Verification level.** Resolve it once with
  `bash "${CLAUDE_PLUGIN_ROOT}/lib/read-verification.sh" --plugin discipline --skill follow-operating-procedures --file docs/conventions/discipline.yaml`
  and report its line ([levels](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/contracts/verification-level/README.md)):
  `light` and `off` skip the method doc's step 2 and step 3 subagents, as it says, and the final
  reply then carries the line `verification: skipped (<level>)` verbatim, such as
  `verification: skipped (light)`.

## Gotchas

- Fired before any work exists, re-anchor only, as the method's conversation-start case says.
- A summary of the instructions from earlier in the session is not a source. Read the files.
- Each invocation rereads every file in the source set, which adds their full text to the session.
  Invoke it when the work needs it, not as a routine.
