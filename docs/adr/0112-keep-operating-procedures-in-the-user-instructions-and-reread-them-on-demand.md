# Keep operating procedures in the user instructions and reread them on demand

- Status: accepted
- Date: 2026-11-18
- Refs: owner decision of 2026-11-18

## Context

The owner pasted a standing operating-procedures prompt of about 6,000 characters into sessions 229
times from 2026-10-27 to 2026-11-18, most often late in long or resumed sessions, because agents
drift from the procedures as context builds up. The same procedures already live in the owner's
user instructions, rendered from a private dotfiles template that also renders the Codex
instructions. A reminder skill in this public marketplace needs those procedures, and the owner
asked for one source of truth: two copies drift apart, and a conflict between them has no rule to
settle it.

[AGENTS.md](../../AGENTS.md) "Team standards" places a rule that changes what a stage produces or
permits in this repository or a plugin, and keeps user scope for personal style. The procedures
mix both kinds.

## Decision

1. **The user instructions own the procedures.** `/discipline:follow-operating-procedures` stores no
   procedure text, no fallback baseline and no personal values. Each invocation rereads the
   instruction files Claude Code loads for the session and audits the work in flight against them.
   When no instruction file exists, it says so and stops.
2. **An exception to the placement rule.** Procedures the owner keeps in user scope stay there, even
   where a rule changes what a stage produces or permits. The skill only rereads them; moving a
   rule into this repository or a plugin remains the placement rule's call, made rule by rule.
3. **Outward drift is reported, not acted on.** The skill reports drift that needs a pull request,
   an issue or a comment as open and takes no outward action, because the shared loop's
   outward-artifact rule is a non-negotiable no skill may override
   ([`re-anchor-audit-correct.md`](../../plugins/discipline/context/re-anchor-audit-correct.md)
   "Non-negotiables"). The instructions' own authority applies again after the report.

## Considered options

- **Copy the procedures into the skill.** Rejected: the marketplace is public, the text holds
  personal values, and a second copy drifts from the dotfiles one with no rule to settle a
  conflict.
- **Keep a generic baseline in the skill as the shared loop's fallback rung.** Rejected: a
  baseline is a second, weaker set of procedures; a session with no instruction files has nothing
  to remind it of.
- **Move the procedures into this repository's instructions.** Rejected: they apply in every
  repository the owner works in, and the dotfiles template already renders them for Claude Code
  and Codex.
- **Let the skill act on outward drift under the owner's standing authority.** Rejected: the shared
  loop forbids any corrector from filing an outward artifact, and a declared delta cannot override
  a non-negotiable.

## Consequences

- Changing a procedure is a dotfiles change; no plugin release is needed.
- Each invocation rereads every instruction file in force, 38,418 characters in this repository on
  2026-11-18, so the skill is invoked on demand, never batched or triggered automatically.
- Outside the owner's machines, the skill rereads whatever instructions that user and project have.

## Revisit triggers

- A second user needs procedures the skill cannot find in their instruction files.
- The reread cost brings on compaction in normal use.
