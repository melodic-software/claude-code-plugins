# Findings artifact — the audit → realign contract

One markdown file is the whole seam between this plugin's skills. `audit` writes it and mutates
nothing else. `realign` is its **only** mutating consumer and the only writer of operator decisions
into it. `check` never reads it at all — it verifies the repository's state directly, so a stale
artifact can never make a broken repo look healthy.

All three skills read this document; none restates it.

## Deliberately not `type: review-findings`

This artifact declares `type: instruction-placement-findings` and must never declare
`type: review-findings`, nor be written where an auto-apply relay scans for that type.

The reasoning is structural. A findings file of that type is located by frontmatter alone, with
nothing authenticating the writer, and is therefore **auto-applicable by construction**. Every move
this plugin proposes is consent-gated per item, and every one of them edits a file that steers the
agent's own behavior. Routing these through an auto-apply relay would launder exactly the human gate
that makes the plugin safe to point at a repository nobody has reviewed.

Consequences, so the boundary is not re-litigated field by field: this artifact owes no
producer-side detector contract, carries no severity vocabulary, and emits no severity crosswalk.
Its verdict vocabulary is this plugin's own and is not a severity scale — mapping it onto one would
imply an auto-apply disposition that does not exist.

## Where it lives

Under the plugin data directory, **keyed by project**, never committed to the consuming repository.

```text
${CLAUDE_PLUGIN_DATA}/findings/<state-key>/<branch-slug>/findings.md
```

`<state-key>` comes from `lib/state-key.sh` — the plugin data directory is keyed to the plugin
identifier and nothing else, so an unkeyed filename is one file per *machine* and can serve one
project's findings as another's. The branch segment keeps concurrent branches and worktrees from
clobbering each other.

Two properties the contract fixes:

- **What proves an artifact belongs to a branch is its own `branch:` frontmatter**, never the
  directory it sits in. The slug mapping is lossy and two branch names can slug to one directory. A
  consumer that finds a mismatch reports it and refuses rather than proceeding.
- **One stable filename per key, rewritten in place.** A re-audit merges into the existing file
  rather than depositing a timestamped sibling; the run timestamp lives in frontmatter where a
  reader and a diff can both find it.

The artifact is **ephemeral by design** — a reclaimed container or removed worktree loses it. That
is fine for evidence and classifications, which are recomputed. It is not fine for operator
decisions, which is why `realign` records those inline (below) and why an applied move is
reconstructable from the repository's own git history regardless.

## Frontmatter

```yaml
---
type: instruction-placement-findings
schema: 1
date: <ISO-basic UTC, colon-free: YYYYMMDDTHHMMSSZ>
branch: <branch at audit time>
corpus: <core | core+expanded>
files_swept: <n>
files_skipped: <n>
claude_code_version: <version the mechanics were valid for, or "unknown">
---
```

`claude_code_version` is recorded because every routing decision rests on version-sensitive loading
mechanics. A `realign` run against an artifact produced on a materially different version re-checks
rather than trusting it.

## Finding record

One section per candidate, in ranked order. Fields are fixed; a field with nothing to say is written
as `—` rather than omitted, so a diff between runs stays aligned.

```markdown
### IP-007 — `**/*.cs` naming conventions

- **Status:** pending
- **Lane:** demote
- **Source:** `CLAUDE.md` lines 88–121, heading "C# naming"
- **Destination:** path-scoped rule `.claude/rules/csharp-naming.md`
- **Proposed `paths:`** `["**/*.cs"]`
- **Glob validation:** 412 tracked files matched; 3.1% of tracked files; budget ok; brackets ok
- **Ladder rung:** 4 — scope narrower than the repo, keyed to a file kind
- **Denied classes:** none
- **Cost:** ~34 always-loaded lines released; absent from subagents except via the index; returns
  after compaction only when a `.cs` file is read again
- **Confidence:** high
```

`Status` moves `pending` → `accepted` | `declined` | `applied` | `blocked`, written by `realign`
only. A `declined` finding keeps its record so a later run does not re-propose what the operator
already rejected — re-proposing a declined move is the fastest way to train an operator to
rubber-stamp.

## Held-back section

Every candidate excluded by a Gate 0 hard-deny class is listed in a separate section, with its class
and its source location, and **no destination**. It exists so the exclusion is visible and
auditable: an operator can see that the sweep considered the content and deliberately left it alone.

Nothing in this section is actionable by `realign`. It has no code path that can apply one, and
`accepted` is not a status a held-back record can take.

## Re-run merge semantics

A second `audit` on the same key merges rather than replacing:

- A finding whose source content is unchanged keeps its identifier and its status.
- A finding whose source content changed is re-classified and reset to `pending`, and the record
  notes that it was re-derived.
- A finding whose source content no longer exists is marked `stale` and kept for one further run
  before being dropped.
- A `declined` finding is never resurrected as `pending` by a re-run alone.

Identifiers are stable across runs and never reused after a finding is dropped.
