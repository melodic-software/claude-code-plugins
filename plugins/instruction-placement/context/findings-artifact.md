# Findings artifact — the audit → realign contract

One markdown file is the whole seam between this plugin's skills. `audit` writes it and mutates
nothing else. `realign` is its **only** mutating consumer and the only writer of operator decisions
into it. `check` never reads it at all — it verifies the repository's state directly, so a stale
artifact can never make a broken repo look healthy.

`delta` also keeps a snapshot of its own, the delta baseline, described under "The delta baseline"
below. It is a capture of this artifact rather than a second record of findings, and it is the only
place a declined decision survives the artifact.

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

**Memory tier, concern-scoped, never committed.** The home is resolved through this plugin's
[`../reference/topic-docs.md`](../reference/topic-docs.md) binding, which owns the rung order, the
slug rule, the non-interactive collapse, and the self-ignore guard. This document names that binding
and **never restates it**, and a skill must run the *whole* rung order rather than assuming the
documented default's shape, or it writes where the other side never looks.

Two properties this contract does fix:

- **What proves an artifact belongs to a branch is its own `branch:` frontmatter**, never the
  directory it sits in. The slug mapping is lossy and two branch names can slug to one directory. A
  consumer that finds a mismatch reports it and refuses rather than proceeding.
- **One stable filename per home, rewritten in place.** A re-audit merges into the existing file
  rather than depositing a timestamped sibling; the run timestamp lives in frontmatter where a
  reader and a diff can both find it.

The artifact is **ephemeral by design**: a branch switch, a removed worktree, or a reclaimed
container loses it. That is fine for evidence and classifications, which are recomputed. It is not
fine for operator decisions, which is why `realign` records those inline (below), why the delta
baseline carries them forward as records of their own (see "The delta baseline"), and why an applied
move is reconstructable from the repository's own git history regardless.

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

A second `audit` on the same home merges rather than replacing:

- A finding whose source content is unchanged keeps its identifier and its status.
- A finding whose source content changed is re-classified and reset to `pending`, and the record
  notes that it was re-derived.
- A finding whose source content no longer exists is marked `stale` and kept for one further run
  before being dropped.
- A `declined` finding is never resurrected as `pending` by a re-run alone.

Identifiers are stable across runs and never reused after a finding is dropped.

## The delta baseline

**This artifact is rewritten in place, so a cross-run comparison must persist a snapshot of its
own.** "Re-run merge semantics" above makes an `audit` re-run merge into the existing file, and
`realign` edits statuses in it between runs. Diffing the artifact against itself therefore measures
whatever last touched it rather than what moved on the surface, and once an audit has re-run there is
no prior state left in the file at all. `delta` compares against a separately persisted baseline for
that reason.

**The baseline is captured at the end of a delta cycle**, from the state that cycle just merged into
the artifact, and it is what the *next* cycle compares against. Its home is the `baselines/` slot in
the resolved memory-tier home, `baselines/delta-baseline.md`, owned by
[`../reference/topic-docs.md`](../reference/topic-docs.md); this document owns only its shape.

```yaml
---
type: instruction-placement-delta-baseline
schema: 1
captured: <ISO-basic UTC, colon-free: YYYYMMDDTHHMMSSZ, end of the cycle that wrote it>
source-date: <the `date` frontmatter of the artifact this snapshot was taken from>
branch: <branch at capture; never `HEAD`, and never written at all when the branch identity is unresolved>
compared: <ISO-basic UTC, written by the LATER cycle that consumes this baseline, when its comparison completes; absent until then>
---
```

`captured:` and `compared:` belong to two different cycles: the one that wrote the baseline and the
one that consumed it. A fresh baseline carrying no `compared:` is the ordinary steady state, not a
fault.

Its body carries two lists and no prose field, ever:

- **Spine rows**, one per finding in the artifact: identifier, source location, status, the digest of
  the classified content, and the last glob-resolution verdict for a `RULE` record. These are the
  five things the five movement shapes are computed from, so a shape cannot be derived from a field
  the snapshot omits.
- **Declined records**, one per finding whose status is `declined`: identifier, source identity, the
  date of the decline, and the operator's stated reason. **These are copied forward into every later
  capture whether or not the finding still appears in the artifact.** A decline is the one judgment
  in this plugin that no other surface can reconstruct, and carrying it in the baseline means a lost
  or rewritten artifact cannot resurrect it.

Three rules bind the capture:

- **A capture never replaces a baseline this cycle did not consume.** The end-of-cycle capture is
  earned by having completed the comparison and by nothing else. Where the cycle stopped short (no
  prior baseline, an unrecognized schema, a `branch:` mismatch, the detector failed) the stored
  baseline is kept exactly as it is and the run writes none. Overwriting it would move the
  comparison's origin silently past a cycle nobody compared, and whatever moved in between would be
  reported by no cycle at all.
- **A baseline older than one cycle widens the span rather than being discarded.** Compare against it
  and say so: the report's window then covers more than one cycle and names the `source-date` it
  measures from.
- **A missing baseline is reported, never inferred.** The run names the resolved path it looked in
  and routes to a full audit. It does not fall back to diffing the artifact against itself, and it
  does not look for the retired plugin-data location, whose retirement the binding records.

The baseline is **not** a second record of findings. Its type is
`instruction-placement-delta-baseline`, deliberately neither `instruction-placement-findings` nor
`review-findings`; `realign` neither reads it nor is selected onto it; and every line in it was
copied from an artifact this contract already governs.

## Stability, and what promotion to a shared seam would require

This artifact is currently consumed by **three skills inside this plugin and nothing else**: `audit`
writes it, `realign` writes operator decisions into it, `delta` merges movement into it and captures its spine into the
baseline. `check`
deliberately reads it never, so a stale artifact can never make a broken repository look healthy.

It is therefore **not** a cross-plugin convention, and there is no owner doc under
`docs/conventions/` for it. That is deliberate. The convention registry's rule — a shared convention
lands in an owner doc *before a second plugin adopts it* — is a deadline, not an instruction to
publish a seam nobody shares yet. Writing one now would fix a shape against a consumer whose
requirements are unknown, which is the failure mode of designing an interface with one
implementation.

**What is guaranteed today**, so a future second consumer has something to hold:

- `schema: 1` is a real version. A change that breaks a reader increments it, and a reader may
  refuse an unrecognized value rather than guessing at the shape.
- Field names and the `Status` vocabulary do not change within a schema version. Fields may be
  *added*; a reader that ignores unknown fields keeps working.
- Identifiers are stable across runs within a home and are never reused.
- The location formula is fixed within a schema version, and it is owned by
  [`../reference/topic-docs.md`](../reference/topic-docs.md) rather than restated here: memory tier,
  concern-scoped, branch-keyed, one stable filename, with the delta baseline in the protocol's
  `baselines/` slot beneath it.

**What promotion would require**, recorded so the work is not rediscovered:

1. A real second consumer with stated needs. Until one exists, the shape is a guess.
2. A decision on the auto-apply boundary. The artifact is deliberately not
   `type: review-findings`, because that type is auto-applicable by construction and every proposal
   here is consent-gated per item. Any shared seam has to preserve that or explicitly justify
   dropping it — and dropping it would launder the gate that makes this plugin safe to run.
3. An owner doc under `docs/conventions/`, registered in the convention registry, carrying the
   rules, versioning, and adoption story — landing *before* the second consumer ships, per the
   registry's own rule.

Until then this document is the contract, and it binds only this plugin.
