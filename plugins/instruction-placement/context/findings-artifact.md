# Findings artifact — the audit → realign contract

One markdown file is the whole seam between this plugin's skills. `audit` writes it and mutates
nothing else. `realign` is its **only** mutating consumer and the only writer of operator decisions
into it. `check` never reads it at all — it verifies the repository's state directly, so a stale
artifact can never make a broken repo look healthy.

`delta` reads the artifact and writes a second, smaller file — the placement baseline — whose shape
this document also owns, under "The baseline-capture obligation".

All four skills read this document; none restates it.

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

In the repository's memory tier, resolved through the plugin's topic-docs binding
([`../reference/topic-docs.md`](../reference/topic-docs.md)), never committed to the consuming
repository. Default:

```text
<memory_dir>/instruction-placement/<branch-slug>/findings.md
```

**Resolve the home; never hardcode the default's shape.** The binding owns the rung order, the
constant slug, the branch axis, and the guards. It is also where the plugin's `baselines/` slot
lives — the shared lifecycle artifact protocol names that slot
([`../reference/artifact-protocol.md`](../reference/artifact-protocol.md)), and this plugin's
baseline is its use of it.

Two properties the contract fixes:

- **What proves an artifact belongs to a branch is its own `branch:` frontmatter**, never the
  directory it sits in. The slug mapping is lossy and two branch names can slug to one directory. A
  consumer that finds a mismatch reports it and refuses rather than proceeding.
- **One stable filename per home, rewritten in place.** A re-audit merges into the existing file
  rather than depositing a timestamped sibling; the run timestamp lives in frontmatter where a
  reader and a diff can both find it.

The findings artifact is **branch-scoped by design** — its line ranges are only true for the branch
it was derived on, and a deleted memory root loses it. That is fine for evidence and
classifications, which are recomputed. It is not fine for operator decisions, which is why a
`declined` decision is mirrored into the baseline below, whose path carries no branch segment and no
checkout discriminator, and why an applied move is reconstructable from the repository's own git
history regardless.

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

## The baseline-capture obligation

`delta` compares this run's detector output against the **previous run's** state, so that state has
to be persisted somewhere the next run can find it. The findings artifact cannot serve: a re-audit
merges into it in place, so after the sweep there is nothing left to diff against. A separately
persisted baseline is therefore mandatory, and it is the one file `delta` writes.

It lives in the `baselines/` slot the lifecycle artifact protocol names, at the location the
topic-docs binding resolves — **one per repository, with no branch segment and no checkout
discriminator in the path**. Default `<memory_dir>/instruction-placement/baselines/placement-baseline.md`.

```yaml
---
type: instruction-placement-baseline
schema: 1
date: <ISO-basic UTC, colon-free: YYYYMMDDTHHMMSSZ>
captured_from_branch: <branch at capture time, or "unknown">
compared: <ISO-basic UTC of the run that last consumed this baseline, or —>
---
```

Two body sections, both required, both written as tables so a diff between runs stays aligned:

- **`## Spine`** — one row per detector record, `SECTION` and `RULE` alike: its key, its kind, and a
  digest of the content the classification depends on. This is what `changed`, `broken-glob`, and
  `stale` are computed against. It is a snapshot, never a second record of a finding: nothing here
  is actionable, and `realign` has no code path that reads it.
- **`## Decisions`** — one row per finding the operator has ruled on: its stable id, its status
  (`declined` or `applied`), the source heading it was raised against, and the date. This is the
  durable half. `delta` reads it before it reports and suppresses every id in it.

Four rules bind the capture:

- **`captured_from_branch` is provenance, not a gate.** A baseline is never refused for describing
  another branch. The branch check belongs to the findings artifact, whose line ranges are
  branch-specific; a decline is a judgment about content and outlives the branch it was made on.
- **The decisions table is additive.** A capture merges this run's decisions into the stored set and
  never drops a row it did not observe: a run on a branch where a declined finding does not appear
  has learned nothing about that decision. A row leaves only when `realign` moves that id's status
  off `declined` in the findings artifact, which is the operator reversing themselves explicitly.
- **The capture happens at the end of a cycle that completed its comparison.** A run that stopped
  early — no detector output, an unrecognized `schema:`, a resolution that yielded no home — leaves
  the stored baseline exactly as it is and writes none. A half-captured spine reports the missing
  half as movement on the next run.
- **`type: instruction-placement-baseline`, never `review-findings`.** The reasoning is the one
  stated above for the findings artifact and it applies with more force here: nothing in this file
  is a proposal, so an auto-apply relay that located it by frontmatter would be acting on a
  snapshot.

An unrecognized `schema:` is a stop with a visible message, not a silent re-baseline: silently
discarding a baseline discards the declined set with it.

## Stability, and what promotion to a shared seam would require

This artifact is currently consumed by **three skills inside this plugin and nothing else**: `audit`
writes it, `realign` writes operator decisions into it, `delta` diffs it across runs. `check`
deliberately reads it never, so a stale artifact can never make a broken repository look healthy.

The baseline is narrower still: `delta` is its only reader and its only writer.

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
- Identifiers are stable across runs within a key and are never reused.
- The location formula — memory tier, constant slug, branch segment, one stable
  filename — is fixed within a schema version.

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
