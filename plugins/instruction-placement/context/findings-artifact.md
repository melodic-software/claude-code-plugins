# Findings artifact — the audit → realign contract

One markdown file is the whole seam between this plugin's skills. `audit` writes it and mutates
nothing else. `realign` is its **only** mutating consumer and the only writer of operator decisions
into it. `check` never reads it at all — it verifies the repository's state directly, so a stale
artifact can never make a broken repo look healthy.

`delta` reads the artifact and writes a second, smaller file — the spine baseline — whose shape this
document also owns, under "The baseline-capture obligation". Operator decisions have a third home:
the tracked finding-suppression surface, whose keys are the marketplace's and whose constituents are
this document's, under "Finding ids and their constituents".

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

The findings artifact is **branch-scoped and checkout-local by design** — its line ranges are only
true for the branch it was derived on, and a removed worktree or deleted memory root loses it. That
is fine for evidence and classifications, which are recomputed. It is not fine for operator
decisions, which is why a `declined` decision is also written to the tracked finding-suppression
surface `.claude/instruction-placement.md`
([`../reference/consumer-config.md`](../reference/consumer-config.md)), where git carries it to
every other checkout, and why an applied move is reconstructable from the repository's own git
history regardless.

## Frontmatter

```yaml
---
type: instruction-placement-findings
schema: 2
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
- **Source:** `CLAUDE.md` lines 88–121, heading path `["C# naming"]`
- **Suppression key:** `check` `instruction-placement/audit/demote`; `claim`
  `narrower-scope:path-scoped-rule`; `anchor/v1` `4b322d9c`; `finding_id` `6e9976d9d2e2c5a4`
- **Destination:** path-scoped rule `.claude/rules/csharp-naming.md`
- **Proposed `paths:`** `["**/*.cs"]`
- **Glob validation:** 412 tracked files matched; 3.1% of tracked files; budget ok; brackets ok
- **Ladder rung:** 4 — scope narrower than the repo, keyed to a file kind
- **Denied classes:** none
- **Cost:** ~34 always-loaded lines released; absent from subagents except via the index; returns
  after compaction only when a `.cs` file is read again
- **Confidence:** high
```

**`Source` records the ordered enclosing heading path, not the leaf heading, and `Suppression key`
is written by `audit` at sweep time.** Both are fields added under this document's own
fields-may-be-added rule, and they exist so `realign` never recomputes an anchor. Only `audit` holds
the detector stream the chain is derived from; `realign` has neither `detect.sh` nor a `SECTION`
stream in its pre-computed context, so its only other route is re-reading the file with its own
heading parse — which does not track fenced blocks and frontmatter the way the detector does. A
divergent parse there produces a well-formed entry whose constituents hash to their own key, so
nothing reports it malformed and `delta` simply never matches it. The decline would vanish with no
error, which is the one failure mode this record's durability exists to prevent.

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

## Finding ids and their constituents

A `declined` decision outlives the artifact that carried it, and the surface it outlives into is the
tracked finding-suppression record `.claude/instruction-placement.md`. That convention owns the
entry's keys, the `finding_id` hash, the `anchor/v<N>` versioning, and the four entry dispositions.
**What each constituent holds for a placement finding is owned here**, because deriving it is this
plugin's business and nobody else's.

| Constituent | For a placement finding |
|---|---|
| `check` | `instruction-placement/audit/<lane>` — `demote` or `promote`, the lane that raised it. |
| `claim` | The canonical claim id with its destination bound: `narrower-scope:<destination>` on the demote lane, `unloaded-convention:<destination>` on the promote lane. Destinations are the rubric's ladder rungs (`path-scoped-rule`, `nested-agents-md`, `skill`, `linter`, `deletion`). Never free prose. |
| `sites` | Exactly one: `surface` is the source file's repo-relative path, `anchor/v1` is the anchor below. A placement finding is about one section of one file, so a second site would describe a finding this plugin does not raise. |

**`anchor/v1` is `sha256` of the `US`-joined ordered enclosing heading path of the section,
truncated to 8 hex** — for the section `### Release checklist` under `## Deployment`, the path is
`["Deployment", "Release checklist"]`. It is deliberately **not** a digest of the section's text and
never a positional ordinal.

**The chain is reconstructed from the detector stream, and only `audit` and `delta` may do it.** A
`SECTION` record carries `path`, `start`, `end`, `level`, and its own `heading`; the ancestors are
recoverable because the records for one file arrive in document order with their levels, so a
section's enclosing path is the nearest preceding record at each lower level, walked up to level 1.
Both skills that run the detector derive it that way and never by re-reading the file.

**`realign` never derives one.** It has no detector stream, so it reads `anchor/v1` and `finding_id`
from the Finding record `audit` wrote and carries them into the suppression entry verbatim. That is
what keeps the anchor a decline is stored under identical to the anchor a later `delta` computes; a
second derivation path is a second parse, and the two disagreeing is a silent lost decline rather
than an error.

Two consequences worth stating, since neither surfaces as a failure:

- **A finding whose record predates these fields cannot be suppressed durably.** No anchor, no
  entry. Re-run `audit` to re-derive the record rather than composing an entry from a hand-read
  heading.
- **A record whose `Source` heading path was edited by hand is not evidence.** The anchor is what
  the entry is keyed by; a hand-edited path that no longer hashes to the stored anchor makes the
  record internally inconsistent, and `realign` reports that and re-audits rather than guessing
  which half is right. A reworded paragraph inside a section whose scope and class are unchanged
is not a new finding, and an anchor over the bytes would resurrect an accepted decline on every
copy-edit. Renaming or re-nesting the heading does change it, and that is correct: the finding is
then a different one, and the convention's `OLD CLOSED, NEW OPENED` disposition reports the old entry
stale rather than dropping it.

`finding_id` is the convention's own formula over `[check, claim, surface, anchor]` — the
constituents are authoritative and the key is derived from them, so an entry whose stored
constituents do not hash to its own key is reported as malformed and suppresses nothing.

**The trade this anchor makes, recorded so it is not re-litigated.** The marketplace contract's own
anchor keeps a heading-path hash as a *duplicate discriminator* inside a larger anchor that also
carries an excerpt hash; this plugin's `anchor/v1` is the heading-path hash alone. The cost is real:
two sections in one file sharing an enclosing heading path, a lane, and a destination collapse to
one `finding_id`, so declining one suppresses both. That is accepted rather than mitigated. Adding
the excerpt half back would make every copy-edit inside a declined section mint a new id and
resurrect a decision the operator already made — the failure this plugin's whole delta lane exists
to prevent — and the collision it avoids requires two same-named headings under the same parent,
which is a malformed document a reader cannot navigate either. Revisit if a consumer demonstrates
the collision on a document they consider correct; the fix would be `anchor/v2` with a
position-independent tiebreak, not a text digest.

The artifact's own `IP-007`-style identifiers are unrelated and stay local to one artifact: they are
short, human-quotable handles for a run's report. The `finding_id` is what crosses checkouts.

## The baseline-capture obligation

`delta` compares this run's detector output against the **previous run's** spine, so that spine has
to be persisted somewhere the next run can find it. The findings artifact cannot serve: a re-audit
merges into it in place, so after the sweep there is nothing left to diff against. A separately
persisted baseline is therefore mandatory.

It lives in the `baselines/` slot the lifecycle artifact protocol names, **branch-keyed**, at the
location the topic-docs binding resolves. Default
`<memory_dir>/instruction-placement/<branch-slug>/baselines/spine-baseline.md`.

```yaml
---
type: instruction-placement-baseline
schema: 1
date: <ISO-basic UTC, colon-free: YYYYMMDDTHHMMSSZ>
branch: <branch at capture time>
compared: <ISO-basic UTC of the run that last consumed this baseline, or —>
---
```

One body section, `## Spine`, written as a table so a diff between runs stays aligned: one row per
detector record, `SECTION` and `RULE` alike, carrying its key, its kind, and a digest of the content
the classification depends on. That is what `changed`, `broken-glob`, and `stale` are computed
against.

Four rules bind the capture:

- **The spine is a snapshot, never a second record of a finding.** Nothing in it is actionable,
  `realign` has no code path that reads it, and **no operator decision is stored here.** A decline
  recorded in a file the topic-docs contract marks invisible outside its own checkout is a decline
  the next worktree never sees; that is why judgments live on the tracked surface instead.
- **`branch:` is a gate, not provenance.** A baseline whose `branch:` does not match the resolved
  branch identity is not this branch's spine — the comparison is refused, both names are reported,
  and the run proceeds as a first run on this branch. The directory alone is never the proof.
- **The capture happens at the end of a cycle that completed its comparison.** A run that stopped
  early — no detector output, an unrecognized `schema:`, no resolved home, no branch identity —
  leaves the stored baseline exactly as it is and writes none. A half-captured spine reports the
  missing half as movement on the next run.
- **`type: instruction-placement-baseline`, never `review-findings`.** The reasoning is the one
  stated above for the findings artifact and it applies with more force here: nothing in this file
  is a proposal, so an auto-apply relay that located it by frontmatter would be acting on a
  snapshot.

An unrecognized `schema:` is a stop with a visible message rather than a silent re-baseline: a run
that quietly discards a spine reports the whole surface as movement and calls it a delta.

## Stability, and what promotion to a shared seam would require

This artifact is currently consumed by **three skills inside this plugin and nothing else**: `audit`
writes it, `realign` writes operator decisions into it, `delta` reads this branch's copy for the
statuses a report has to respect. `check` deliberately reads it never, so a stale artifact can never
make a broken repository look healthy.

The baseline is narrower still: `delta` is its only reader and its only writer. The suppression
surface is the one home in this plugin that is not local to a checkout, and its keys are the
marketplace's rather than this document's.

It is therefore **not** a cross-plugin convention, and there is no owner doc under
`docs/conventions/` for it. That is deliberate. The convention registry's rule — a shared convention
lands in an owner doc *before a second plugin adopts it* — is a deadline, not an instruction to
publish a seam nobody shares yet. Writing one now would fix a shape against a consumer whose
requirements are unknown, which is the failure mode of designing an interface with one
implementation.

**What is guaranteed today**, so a future second consumer has something to hold:

- `schema: 2` is a real version, and it is 2 rather than 1 because this document's location formula
  changed: a reader holding the retired formula looks in a home nothing writes any more, which is a
  reader-breaking change by the rule in the next bullet. A reader may refuse an unrecognized value
  rather than guessing at the shape.
- Field names and the `Status` vocabulary do not change within a schema version. Fields may be
  *added*; a reader that ignores unknown fields keeps working.
- Identifiers are stable across runs at one resolved home and are never reused. The cross-checkout
  identity is the `finding_id` above, not this handle.
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
