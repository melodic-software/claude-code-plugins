# Clean-tree / no-scope fallback — shared contract

SSOT for how docs-hygiene audit skills behave when invoked with **no target and
no inherited working set**. Each skill cites this file and keeps only its
skill-specific prescribed defaults in its own `SKILL.md`.

## Shared shape (all audit skills)

When the invocation is bare — empty arg, clean tree (or no inherited scope),
and nothing in the conversation already naming a corpus — the skill:

1. **Reports** that no default local target exists (uncommitted `.md` empty, or
   no inherited detect scope).
2. **Offers** a confirmation-gated escalation to a repo-wide (or skill-default)
   corpus run — never starts it unprompted.
3. Presents **prescribed defaults** (overridable) so a bare "yes" suffices.
4. On **decline or silence**, ends as the friendly no-op (skill-specific exit
   message). Unattended / non-interactive sessions surface the offer as blocked
   and stop — never launch the repo-wide run on silence.
5. An **explicit opt-in** keyword (`sweep`, `audit` with an explicit corpus
   flag, or a user-stated "whole repo") skips the confirmation and runs.

This is the audit-noise 0.12.0 clean-tree fallback generalized. Skills that
already had a close cousin (derivability's empty-target escalation,
encapsulation's no-scope confirmation, compress's interview fallback) converge
here rather than drifting.

## Who participates

| Skill | Trigger | Explicit opt-in that skips confirm | Notes |
|---|---|---|---|
| `audit-noise` | empty arg + clean tree | user-stated whole-repo / confirmed offer | Read-only; report-first; chunked `detect.sh` |
| `audit-derivability` | empty arg + clean tree | `sweep <dir\|repo>` | Read-only; confirmed escalation runs as `sweep` |
| `audit-progressive-disclosure` | empty arg + clean tree | user-stated whole-repo / confirmed offer | Read-only; report-first; corpus = tracked agent-facing instruction `.md` |
| `audit-encapsulation` | bare detect with no inherited scope | `sweep` | Domain is already repo-wide; confirm is about intent, not discovery |
| `compress` (default + `audit`) | empty arg + clean tree, interactive | user-stated whole-repo / confirmed offer | Mutating default stays interview-gated after a free audit pass; bare `compress audit` on a clean tree offers the same free audit corpus (report-only) instead of no-opping |
| `extract-ssot` | bare invocation with no scope | path/glob-scoped survey after confirm | Already documented as "Bare invocation — confirm scope first"; cites this shape |
| `rename-references` | *(out of scope)* | — | Always needs an old/new token pair; no clean-tree corpus offer |

## Deliberate divergences (do not "fix" these away)

- **compress is mutating.** Its clean-tree path is audit-first then a second
  confirmation before any Edit. Read-only siblings stop after the report.
- **encapsulation's trigger is "no inherited scope", not only "clean tree".**
  A dirty tree with unrelated edits still needs the confirm when nothing
  names the detect surface.
- **Prescribed defaults differ by skill** (fixture exclusions, concurrency,
  spot-test caps, report-vs-fix). Those knobs stay in each skill's
  `SKILL.md`; this file owns only the offer/confirm/no-op skeleton.
- **Non-interactive contexts** (subagent, headless/CI): no-op / blocked
  offer — never auto-escalate. Compress states this explicitly; the others
  inherit it from step 4 above.

## Citation

Skill bodies point here with a one-line cross-ref under their auto-detect /
no-scope section, e.g. "Shared shape: `../../context/clean-tree-fallback.md`
(plugin root)." Paths are relative to the citing `SKILL.md`.
