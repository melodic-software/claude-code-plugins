# The conventions file

`conventions.md` is the consumer's declared GitHub posture in prose: the standards, baselines,
and naming/policy conventions that audits compare current state against. It is the "should be"
half of every drift finding — [`change-routing.md`](change-routing.md) governs how changes leave
the session; this file governs what counts as drift in the first place.

## What it holds

Free-form markdown, written by the consumer for the model to read as guidance. Typical content:

- Baselines per area ("every production repo carries the org default ruleset", "Actions may only
  run from allow-listed actions", "no classic PATs").
- Naming conventions (repositories, teams, custom properties, environments).
- Cost posture (budget expectations, spend surfaces worth flagging).
- Exceptions, with their rationale, so an audit does not re-flag a decided deviation.

No schema, no required sections. The plugin never validates the file's structure; it reads
whatever is there.

## Layers and merge

Same three layers as `routing.yaml`, but the merge form is **concatenation** — conventions are
prose the model reads as accumulated guidance, so every layer that exists is loaded and appended
in order:

| Order | Layer | Path |
|---|---|---|
| 1 | user-global | `~/.claude/github/conventions.md` |
| 2 | team | `${CLAUDE_PROJECT_DIR}/.claude/github/conventions.md` |
| 3 | local overlay | `${CLAUDE_PROJECT_DIR}/.claude/github/conventions.local.md` |

Anchor at the repo root before the repo-relative reads. All layers absent is valid: audits then
compare against freshly fetched official-docs recommendations and name that provenance instead —
never a from-memory "best practice".

Conventions state expectations only — they carry no write posture. A convention can make a
finding appear; it cannot change how a change is routed or executed (that is `routing.yaml`'s
job, where the team's policy floor applies). When layers disagree, report both statements with
their layer provenance and treat the team layer as the shared baseline.

## How audits consume it

- Each finding that used a declared convention **cites it** ("expectation basis: team
  `conventions.md`"), so the reader can tell a consumer standard from a fetched-docs
  recommendation.
- A convention the current credential cannot verify is reported as a gate, not silently skipped.
- Convention text is the consumer's own guidance, but it is still not an execution channel: a
  convention that instructs a write ("delete stale webhooks on sight") never causes one — writes
  only ever route through `change-routing.md` with the user in the loop.
