# Findings artifact — the audit → realign contract

One markdown file is the whole seam between this plugin's two skills. `overengineering:audit`
produces it and is read-only on everything else; `overengineering:realign` is its **only** consumer
and its only writer of operator judgment. Both skills read this document; **neither restates it**,
and no other plugin is assumed to read it.

The artifact is the single source of truth for a run: everything that drives the reasoning —
evidence citations, liveness answers, intent reconstruction, rediscovery, cost weighing, verdict —
lives here. An inline terminal summary is a view of it, never a second record.

## Deliberately NOT `type: review-findings`

This artifact declares `type: overengineering-findings` and **must never be made to declare
`type: review-findings`**, nor be written into the directory where a fix relay scans.

The reasoning is structural, not stylistic. The `review:fanout` fix relay locates its input purely
by frontmatter — files declaring `type: review-findings` whose `branch:` matches the current branch
— and never by provenance; nothing authenticates the writer
(`docs/conventions/detector-findings/README.md`). A findings file of that type is therefore
**auto-applicable by construction**. Realignment is consent-gated *per item*: routing it through the
relay would launder exactly the human gate that makes this plugin safe to run — the same reasoning
that convention states for a rule whose only remediation is a consent-gated write.

Consequences, so the boundary is not re-litigated one field at a time:

- This artifact is **not** a detector-findings producer. It owes none of that contract's four
  producer-owned fields (`Tier`, `Confidence`, `Location`, cell escaping), carries no severity
  crosswalk row, and emits no severity vocabulary.
- Its verdict vocabulary is this plugin's own (`context/scrutiny-method.md` §6) and is not a
  severity scale. Mapping it onto one would imply an auto-apply disposition that does not exist.
- A mechanical, contained fix that happens to fall out of an audit does not belong here either. It
  belongs to whichever neighbor surface owns that class of finding, reached by routing, not by
  changing this artifact's type.

## Where it lives

**Memory tier, concern-scoped, never committed.** The home is resolved through this plugin's
`reference/topic-docs.md` binding, which owns the rung order, the slug rule, the non-interactive
collapse, and the self-ignore guard. This document names that binding and **never restates it** —
and a skill must run the *whole* rung order rather than assuming the documented default's shape, or
it writes where the other side never looks.

Two properties the contract does fix:

- **Branch-keyed sub-path.** The resolved home carries a branch-derived segment, so concurrent
  branches, worktrees, and clones never clobber each other's runs. What proves an artifact belongs
  to a branch is its own `branch:` frontmatter, never the directory it sits in — the branch-slug
  mapping is lossy by design and two branch names can slug to one directory.
- **One stable filename per home, rewritten in place.** A re-audit merges into the existing file
  (see "Re-run merge semantics") rather than depositing a timestamped sibling. A per-run filename
  would turn the merge into a search problem and make the artifact's history a guess; the run's
  timestamp lives in frontmatter, where a reader and a diff can both find it.

The artifact is **ephemeral by design**: a branch switch, a removed worktree, or a reclaimed
container loses it. That is acceptable for evidence and verdicts, which are recomputed, and
unacceptable for operator judgments — see "The durable judgment record".

## Frontmatter

```yaml
---
type: overengineering-findings
schema: 1
date: <ISO-basic UTC, colon-free: YYYYMMDDTHHMMSSZ>
scope: <the layers actually walked this run>
branch: <branch at audit time>
---
```

| Key | Required | Contract |
|---|---|---|
| `type` | yes | Exactly `overengineering-findings`. The selector realign matches on. |
| `schema` | yes | Integer contract version, currently `1`. A consumer reading an unrecognized value **stops with a visible message** rather than guessing at the shape. |
| `date` | yes | Colon-free UTC, Windows-safe, lexically sortable. The only record of when the audit actually ran. |
| `scope` | yes | The layers walked, from the layer vocabulary below. A layer-scoped pass says so here; **a layer absent from `scope` was not walked, and is not the same as a layer walked and found empty.** The merge rules depend on this distinction. |
| `branch` | yes | The branch at audit time. Realign refuses an artifact whose `branch:` does not match the current branch, naming the mismatch. |

## Layer vocabulary

Fixed enum, in this order — the order is load-bearing for sorting (below):

`agent-hooks` · `agent-instructions` · `repo-hooks` · `vcs-hooks` · `ci-lanes` · `gate-scripts` ·
`satellite-workflows` · `branch-protection` · `forge-apps` · `external-integrations`

The vocabulary is deliberately forge-neutral and platform-neutral: a consumer whose forge, CI
system, or agent harness differs still maps onto these ten. A lane that needs an eleventh adds it to
this enum with a `schema` bump, never as a free-text value.

## Document shape

````markdown
---
<frontmatter above>
---

# Overengineering audit — findings

## Evidence availability

<per-tier present / partial / unavailable, with the probe that established each — scrutiny-method §8
 obligation 1. This section leads the report; it changes what UNPROVEN means for every row below.>

## Summary

<counts per verdict class, per layer.>

## Findings

### <finding-id>

- **Layer:** <enum value>
- **Artifact:** <repo-relative path, or kind-prefixed stable identifier>
- **Verdict:** KEEP | RETIRE | DOWNGRADE | CONSOLIDATE | UNPROVEN | FLAG-FOR-HUMAN
- **Status:** OPEN | ACCEPTED | REJECTED | REALIGNED | DELEGATED-EXTERNAL | ABLATION-*

<free prose fields — see "Per-finding fields">

## Suppressed

<findings whose id carries a durable judgment entry, each with its reason, date, and contributing
 layer; plus every entry that did NOT suppress and why.>

## Closed since last run

<findings present in the prior artifact and absent from this one, with the reason class.>
````

## Finding ids

Ids are **content-hashed and stable across runs**, derived exactly as the finding-suppression
convention derives a `finding_id` (`docs/conventions/finding-suppression/`), so an id in this
artifact and an id in the consumer's suppression record are the same value by construction rather
than by a mapping someone has to maintain.

Constituents, and nothing else:

| Constituent | Value for this producer |
|---|---|
| `check` | `overengineering/audit/rule-<layer>` — lowercase `[a-z0-9-]` per segment, the layer taken from the enum above. |
| `claim` | `enforcement-item` for an ordinary finding; `enforcement-item(member=<name>)` where an aggregating lane carries per-member sub-verdicts. A canonical id with bound parameters — never free prose. |
| `sites` | One `{surface, anchor/v1}` per artifact the finding is about. `surface` is the repo-relative path or kind-prefixed identifier; `anchor/v1` is `sha256` of the ordered locator path within that surface, truncated to 8 hex — `[<artifact-identity>]` for a whole item, `[<container>, <member>]` for a sub-member. **Never a positional ordinal.** A cross-artifact finding (a CONSOLIDATE naming two mechanisms covering one concern) carries *every* site, not one plus a footnote. |

The id is `sha256` over the `US`-joined `[check, claim, *flattened canonically-sorted sites]`,
truncated to 16 hex — the convention owns that computation and this document does not re-derive it.

**Deliberately excluded from the constituents: the verdict, the evidence, the status, and every
prose field.** They are recomputed every run. An id that moved when a verdict moved would break
carry-forward by construction, which is the one property the whole contract exists to provide.

**Renames are honest, not smoothed.** Renaming an artifact changes its site and therefore its id:
the old finding closes and a new one opens. Record the rename in `## Closed since last run`, naming
the successor id where the rename is evidenced. Silently re-pointing an id at a different path would
carry an operator's judgment onto something they never judged.

## Ordering

Findings are emitted in a **stable total order**: layer (in the enum's declared order, not
alphabetically) → artifact identifier (byte-wise ascending on the encoded value, so the order is
locale-independent) → finding id (byte-wise ascending). Ties are impossible at the third key, so the
order is total and reproducible.

A diffable artifact needs this: two runs over an unchanged tree must place unchanged findings on the
same lines, or every diff is noise.

## The stable spine / free prose split

**The spine** is the machine-stable part: `id`, `layer`, `artifact`, `verdict`, `status`. It is
**line-formatted** — each field on its own line, in the fixed order shown in "Document shape", with
the literal bold label and a single-line value drawn from a closed vocabulary or a path. Nothing
else may appear on a spine line.

**Everything else is free prose**, recomputed fresh each run: evidence, liveness, intent,
rediscovery, cost, owner, and the conditional fields below.

The split is a contract, not a formatting preference, and it exists for two consumers:

- **Diffing across runs compares the spine only.** The spine of a run is the ordered sequence of
  `(id, layer, artifact, verdict, status)` tuples, extractable with a line filter and comparable
  with a line diff. Two independent prose passes over the same tree will never be byte-identical,
  and live evidence sources move between runs by design (an appending log grows; a history query
  returns more). A comparison over full prose rows reports model noise as change and is worthless.
- **A future delta lane inherits this as its contract.** Whatever reports "what changed since the
  last run" reads the spine; the prose is context for a human, not an input to a comparison.

Two rules keep the spine extractable: a spine value never contains a newline, and a spine value is
never a sentence. Anything that wants to be a sentence is prose and belongs below the spine.

## Per-finding fields

| Field | Spine | Required | Content |
|---|---|---|---|
| `Layer` | yes | always | One enum value. |
| `Artifact` | yes | always | Repo-relative path; or, for an item with no path, a kind-prefixed stable identifier (`protection:<rule-name>`, `app:<name>`, `integration:<name>`) so it cannot collide with a path. |
| `Verdict` | yes | always | One of the six tokens. Argued per `context/scrutiny-method.md` §6. |
| `Status` | yes | always | One vocabulary value (below). Written `OPEN` by the audit on a new finding; otherwise carried forward. |
| `Protected` | no | when a protected class matched | Which class and which pattern matched; whether the cap was applied; and, when it was, the retirement-direction verdict it would otherwise have been. |
| `Evidence` | no | always | At least one empirical citation with its tier (`scrutiny-method` §2), or `UNPROVEN` naming the tier consulted and whether it was **silent** or **unavailable**. Doc-only support is marked `unverified`. |
| `Liveness` | no | always | Three independently-answered lines — source posture, wiring, runtime enforcement — each naming what was actually read. An unread question is recorded as unread, never inferred. |
| `Intent` | no | always | The reconstruction and its confidence; `OPEN-INTENT` where the run was unattended and confidence was low. |
| `Rediscovery` | no | always | The simplest adequate re-solution, native-first, with the tech-drift check and its date. |
| `Cost` | no | always | Removal, refactor, and testing cost as it entered the verdict. |
| `Owner` | no | always | The resolved owner, or `operator (last resort)`, with the authorship evidence that resolved it. |
| `Threshold` | no | when one was applied | Which threshold row fired, its source, and its analogical label carried verbatim. A threshold cited without its label is a contract violation, not a style slip. |
| `Routed-to` | no | when routed | The neighbor surface the finding was handed to, and whether that surface was present. |
| `Delegation` | no | `DELEGATED-EXTERNAL` only | The pointer to the delegation artifact. |
| `Ablation` | no | `ABLATION-*` only | Rung reached, window length, window end date, and the durable pointer. |
| `Judgment` | no | when one was persisted | The suppression entry id and the layer it was written to. |

## Status vocabulary

| Status | Meaning |
|---|---|
| `OPEN` | Emitted; no operator judgment yet. The only status the audit ever writes on a new finding. |
| `ACCEPTED` | The operator accepted the finding; remediation is authorized. |
| `REJECTED` | The operator judged the finding and declined it; the mechanism stays. |
| `REALIGNED` | Remediation executed and the change landed. |
| `DELEGATED-EXTERNAL` | Accepted, but the remediation lies **outside this repository** — organization-level policy, a managed or synced upstream, a forge control plane. Carries a `Delegation` pointer to the artifact that carries the request: an upstream change request, an administrator issue, or written instructions handed to the owner. Realign never edits an out-of-repo surface in place, and never patches a managed copy locally. |
| `ABLATION-PENDING` | Accepted into a bounded ablation batch; not yet disabled. |
| `ABLATION-ACTIVE` | Disabled at rung 1 of the rollback ladder; observation window running; `Ablation` carries the end date. |
| `ABLATION-CONCLUDED-RETIRE` | The window elapsed with nothing escaping; deletion at rung 3 is authorized. |
| `ABLATION-CONCLUDED-KEEP` | The window showed the mechanism load-bearing; it was re-enabled and the finding closes as KEEP with the evidence the window produced. |

The vocabulary is closed. A consumer encountering a value not in this table **reports it and takes
no action on that finding** — soft degradation, never a guess about what an unknown state meant.

Every `ABLATION-*` state carries a **durable pointer** (a suppression entry or a tracked issue) as
well as its window. An observation window recorded only in an ephemeral artifact is an abandonment:
the artifact can vanish before the date it is waiting for.

## Status transitions are owned by realign

`overengineering:realign` is the **only** writer of `Status`. It is also the only mutator of
anything outside this artifact, and every transition it makes sits behind an explicit per-item
acceptance from the operator.

`overengineering:audit` writes `OPEN` on a finding it has not seen before and otherwise **carries
the prior status forward** verbatim. It never advances, downgrades, or clears one. This is not a
courtesy: the audit's verb contract is read-only, and a read-only producer that rewrote statuses
would silently erase decisions a human made — the failure the durable judgment record exists to
prevent, reintroduced by the producer itself.

## Re-run merge semantics

A re-audit **rewrites the artifact in place**, merging against the prior content by stable id. For
each finding:

1. **Id present in the prior artifact.** The merge **carries forward** the prior `Status` verbatim,
   together with its status-bound fields (`Delegation`, `Ablation`, `Judgment`). Everything else —
   evidence, liveness, intent, rediscovery, cost, owner, and **the verdict** — is recomputed and
   replaces the prior value. A stale verdict is worse than no verdict; a wiped status is worse than
   both.
2. **Id absent from the prior artifact.** A new finding, `Status: OPEN`.
3. **Prior id absent from this run, and its layer WAS walked.** The underlying artifact is gone
   (deleted, renamed, or already retired). The finding is **dropped with a note**: a
   `## Closed since last run` row records the id, its last verdict, its last status, and the reason
   class — `artifact absent`, `renamed to <successor id>` where the rename is evidenced, or
   `layer no longer configured`. A finding that vanishes with no row is the failure this section
   exists to prevent.
4. **Prior id absent from this run because its layer was NOT walked** (`scope` says so). The finding
   is **carried forward untouched**, prose and all, marked not re-evaluated this run and stamped
   with the `date` of the run that produced it. A layer-scoped pass must never read as a retirement
   of everything it did not look at.
5. **A verdict that changed direction under a carried-forward judgment is surfaced, never applied.**
   An `ACCEPTED` finding whose verdict recomputed to `KEEP`, or a `REJECTED` one that recomputed to
   `RETIRE`, is flagged for the operator: the evidence moved under a decision they already made, and
   that is precisely what they need to see.

The carry-forward rule is why operator judgments are never wiped and re-reported. Re-reporting a
judged finding forever is the noisy-repeat failure the finding-suppression convention exists to
prevent, and an audit whose report is permanently noisy is an audit nobody reads.

**Partial artifacts are valid.** An audit may write per layer as it walks, so an interrupted run
leaves a checkpoint rather than nothing; a later run merges into it by exactly the rules above, with
`scope` distinguishing "not walked" from "walked and empty". Interruption therefore costs the
unwalked layers only.

## The durable judgment record

The artifact is memory-tier and ephemeral; an operator's judgment must outlive it. So a judgment is
**offered** persistence as a suppression entry in the consuming repository's **tracked**
`.claude/overengineering.md`, per `docs/conventions/finding-suppression/`, written by realign behind
the **same per-item gate** that authorized the remediation.

- **Offered, never taken.** A producer that wrote a suppression entry unprompted would record an
  acceptance nobody made. Realign proposes the entry, shows it, and writes only on an explicit yes.
- **Which judgments qualify.** A `REJECTED` finding (the operator judged it and kept the mechanism)
  and an `ABLATION-CONCLUDED-KEEP` one. A `REALIGNED` finding needs no entry — the mechanism is
  gone, so the finding cannot recur.
- **The ids already match.** The artifact's finding id *is* the `finding_id` the suppression record
  keys on, because both derive from the same constituents by the same rule. No translation step
  exists to get wrong.
- **The entry's keys are the convention's** (`check`, `claim`, `sites`, `reason`, `date`), and the
  constituents are authoritative with the key derived from them. The `reason` is the **operator's**
  words: a suppression with no stated reason cannot be reviewed and cannot be retired, and audit
  prose recycled into that field is not a stated reason.
- **The team-tracked layer, not a personal overlay.** This surface class is policy-floor: a
  personal-layer entry for an id the team layer does not carry does not suppress. Writing there
  would leave the operator believing a judgment is in effect when it is not.
- **The record is excluded from the audit's own scan set**, so recording a judgment does not perturb
  the next run's inputs.
- **Suppression is visible, never silent.** On the next run, a finding whose id carries an entry is
  reported in `## Suppressed` with its reason, date, and contributing layer — and every entry that
  did *not* suppress (personal-only, malformed, stale) is reported there too.

The key shapes and merge forms for the consumer's concern file are owned by this plugin's
`reference/consumer-config.md`; this document owns only what the artifact contributes to them.

## Obligations, by skill

| Obligation | `audit` | `realign` |
|---|---|---|
| Writes the artifact | yes — it is the producer | yes — status and status-bound fields only |
| Mutates anything outside the artifact | **never** | only behind explicit per-item acceptance |
| Writes `Status` | `OPEN` on new findings; carries the rest forward | the sole owner of every transition |
| Leads with the evidence-availability assessment | yes, before any finding | reads it; never recomputes it |
| Refuses on a mismatched `branch:` or an unrecognized `schema:` | n/a — it writes them | yes, with a visible message |
| Behavior when the artifact is missing | n/a | **stop** with a visible message naming `overengineering:audit` as the skill that produces it — the artifact-protocol missing-prerequisite rule; never scan on its own |

## External authority

- `docs/PLUGIN-ARTIFACT-PROTOCOL.md` — the lifecycle profile this artifact conforms to: memory-tier
  placement, resolution through the current plugin's `reference/topic-docs.md` binding, and the
  missing-prerequisite stop.
- `docs/conventions/finding-suppression/` — the `finding_id` derivation, the required entry keys,
  the constituents-are-authoritative rule, and the policy-floor precedence inversion.
- `docs/conventions/detector-findings/README.md` — the fix relay's type-only selection, which is why
  this artifact's type is deliberately not `review-findings`.
- `docs/conventions/config-cascade/README.md` — the layering axis the consumer's tracked concern
  file resolves through.
- `context/scrutiny-method.md` — the verdict ladder, evidence taxonomy, protected-class cap,
  thresholds, and rollback ladder whose output every field above records.
