# Report the permission plane as in effect, and never write to it

- Status: accepted
- Date: 2026-08-12

## Context

Claude Code's permission plane is legible only to the harness. `/permissions` lists rules and the file
each came from, but nothing resolves which of two conflicting rules wins, nothing distinguishes a
scope that was empty from one that could not be read, and there is no machine-readable export. Auto
mode became the default permission mode for new sessions, and on entry it silently drops broad allow
rules — so a consumer's grants can stop taking effect with no signal at all.

Research across roughly thirty third-party tools found nobody auditing an `autoMode` block, resolving
cross-scope precedence, or validating managed policy against the scopes beneath it. The highest-adoption
linter in the space carries one permission rule out of 447. The official marketplace ships 284 plugins
and none manage permission configuration.

Two questions had to be decided before building anything, and both had a defensible opposite answer.

## Decision 1 — report, never write

**These skills write nothing, in any scope, under any flag.** No `--fix`, no "shall I apply this",
no follow-up offer.

Enforcement was available: hook `deny` and exit-2 both work, measured. This is a posture choice, not a
capability limit. Editing a consumer's settings file is making a permission decision on their behalf,
and a plugin that will silently adjust what the agent may do is a worse failure than one that reports
a problem the human then fixes. The authoring lane draws the same line — it prints a block and the
human pastes it.

The cost is real: an operator with 77 dead allow rules must fix them by hand. That is accepted.

## Decision 2 — compute the merge locally, bounded by decidability

**Claims follow from documented mechanics over readable inputs, each citing the mechanic it follows
from.** Anything resting on classifier judgment, runtime demotion state, or an open upstream
discrepancy becomes a **named caveat on the affected finding** — never a silent drop, never an
assertion.

The alternative was to wait for an official export. Nothing suggests one is coming, and the local
merge is decidable for the part that matters.

Two mechanics carry the result, and conflating them produces confident wrong answers:

- **Permission rules merge across scopes rather than override.** A rule at two scopes has no winner —
  both are live. Electing one would assert an override the documentation denies.
- **Kind is decided by evaluation order — deny, then ask, then allow — from any scope, in both
  directions.** A user-level deny blocks a project-level allow just as the reverse. Scope rank does
  not enter into it, and an implementation that ranked scopes here gets the low-scope-deny case
  exactly backwards.

Every effective-set claim states two standing bounds: the command-line scope outranks the files and
has none to read, and rules are compared by exact text, so a narrow allow blocked only by a broader
deny **pattern** is still reported effective. The error direction is known — over-reporting allow,
never over-reporting blocking.

## Consequences

- Reports are trustworthy about their own limits. `absent` means looked and found nothing; `skipped`
  means could not look. A surface that could not be read is never reported as absence of policy —
  an administrator reading silence as "no policy deployed" is the failure this exists to prevent.
- **Managed policy is read-only by construction**, not by restraint: those are admin-write OS
  locations or a claude.ai Owner role. The conformance report says what a consumer's own policy does
  and does not achieve, and ships no security floor of its own.
- Server-managed settings have no local path, so every managed claim is scoped to the local surfaces.
- One optional lane needs `python3`, because `claude auto-mode config` emits raw control characters
  inside JSON string values that no line-oriented POSIX filter can repair. Absent it, that lane skips
  visibly and everything else still runs.
- **Re-opens if** an official machine-readable export of resolved permission state ships, or if
  `claude permissions` becomes a real subcommand — either would retire the local merge as the read
  path. A debug-channel oracle already exists as corroboration but is not a read path: it costs a
  session spawn and parses undocumented `[DEBUG]` strings with no stability contract.
- **The write posture re-opens only on an explicit decision**, not on a feature request. It is the
  contract these skills are trusted under.
