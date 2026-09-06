# Findings artifact — the audit → realign contract

## Contents

- [Deliberately NOT `type: review-findings`](#deliberately-not-type-review-findings)
- [Where it lives](#where-it-lives)
- [Frontmatter](#frontmatter)
- [No branch identity, no artifact](#no-branch-identity-no-artifact)
- [Layer vocabulary](#layer-vocabulary)
- [Document shape](#document-shape)
- [Finding ids](#finding-ids)
- [Ordering](#ordering)
- [The stable spine / free prose split](#the-stable-spine--free-prose-split)
- [The spine-capture obligation](#the-spine-capture-obligation)
- [Aggregating containers — the container is the finding](#aggregating-containers--the-container-is-the-finding)
- [Per-finding fields](#per-finding-fields)
- [Status vocabulary](#status-vocabulary)
- [Status transitions are owned by realign](#status-transitions-are-owned-by-realign)
- [Re-run merge semantics](#re-run-merge-semantics)
- [The durable judgment record](#the-durable-judgment-record)
- [Obligations, by skill](#obligations-by-skill)
- [External authority](#external-authority)

One markdown file is the whole seam between this plugin's four skills. **Two of them produce it**:
`overengineering:audit` writes a `mode: walk` run over the ten enforcement layers, and
`overengineering:justify` writes a `mode: targeted` run over the five justification layers. Both are
read-only on everything else. `overengineering:realign` is its **only mutating** consumer and its
only writer of operator judgment. `overengineering:delta` reads it across runs and writes nothing
here at all. All four skills read this document; **none restates it**, and no other plugin is
assumed to read it.

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
  **A branch identity that does not resolve therefore keys no home at all.** A detached checkout has
  no branch name, and every substitute collapses the axis this segment exists to separate: `HEAD` is
  the same string for every ref, and the commit sha is a different one every commit. The producer
  writes nothing rather than writing somewhere shared — see "No branch identity, no artifact" below.
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
schema: 2
mode: walk
# targets: omitted under `mode: walk`; required, one item per line, under `mode: targeted`
date: <ISO-basic UTC, colon-free: YYYYMMDDTHHMMSSZ>
scope: <the layers actually walked this run>
branch: <branch at audit time; never `HEAD`, and never written at all when the branch identity is unresolved>
---
```

| Key | Required | Contract |
|---|---|---|
| `type` | yes | Exactly `overengineering-findings`. The selector realign matches on. |
| `schema` | yes | Integer contract version, currently `2`. A consumer reading an unrecognized value **stops with a visible message** rather than guessing at the shape. |
| `mode` | yes | `walk` or `targeted`. A `walk` run inventories whole layers and is what `overengineering:audit` writes. A `targeted` run examines only the items named in `targets` and is what a pointed lane such as `overengineering:justify` writes. The merge rules below branch on this key, so a run that omits it cannot be merged safely. Required of every run this contract governs, which means every `schema: 2` run: a `schema: 1` artifact predates the key and legitimately carries none, and merging into one upgrades it, so the writer supplies `mode` for its own run rather than reading an absence as a fault. |
| `targets` | when `mode: targeted` | The item identifiers this run examined, one per line, each a repo-relative path, a `path#heading`, or a kind-prefixed identifier from the closed set under "Finding ids". A `walk` run omits the key. It is the merge rules' authority for what this run did and did not look at; `scope` in a targeted run carries the prior artifact's value forward and adds the layers those targets fall in, and the added layers are for ordering only and assert no exhaustive walk. |
| `date` | yes | ISO-basic UTC (`YYYYMMDDTHHMMSSZ`): compact, unambiguous about its zone, and lexically sortable — string order is chronological order. The only record of when the audit actually ran. (Colon-freedom buys nothing *inside* a file; it is a **filename** property, and this contract fixes one stable filename per home rather than a timestamped one.) |
| `scope` | yes | The layers walked, from the layer vocabulary below. A layer-scoped pass says so here; **a layer absent from `scope` was not walked, and is not the same as a layer walked and found empty.** The merge rules depend on this distinction. |
| `branch` | yes | The branch at audit time, resolved with `git symbolic-ref` — **never the literal `HEAD`**, which is what `git rev-parse --abbrev-ref HEAD` answers on a detached checkout. Realign refuses an artifact whose `branch:` does not match the current branch, naming the mismatch, and equally refuses one whose `branch:` is absent, empty, or `HEAD`. The field is required because the artifact is: where no branch identity resolves, there is no artifact to carry it (below). |

## No branch identity, no artifact

Every skill in this plugin resolves the branch with `git symbolic-ref`, which **fails** on a detached
checkout rather than answering the literal string `HEAD` the way `git rev-parse --abbrev-ref HEAD`
does. `HEAD` is not an identity: it is the same string for every ref, so it keys every ref to one
home and compares equal to itself. Scheduled and dispatched runners commonly check out detached, so
this is an ordinary condition for this artifact, not an exotic one.

Where the identity does not resolve, and no logical ref is supplied by the environment:

- **`audit` writes no artifact.** Not the file with `branch:` omitted, not the file with a placeholder
  value, not the file at a home keyed by something else — none of it. The walk still runs and the
  inline summary is still emitted; only the persisted write is declined, and the run says so.
- **`justify` writes no artifact either**, on the same terms and for the same reason. The pass still
  runs and its inline report is still emitted in full; the persisted write is declined and the run
  says why. Both producers decline alike, because the hazard is the home key rather than the lane.
- **`realign` refuses**, both when its own checkout has no identity and when an artifact it finds
  carries `branch:` absent, empty, or `HEAD`. It never reaches the comparison, because a degenerate
  `HEAD`-to-`HEAD` match passes by construction and would authorize mutations from another ref's
  findings.
- **`delta` compares nothing and captures nothing**, per its own section on the same condition.

**Omitting the key is deliberately not the remedy.** An artifact whose identity cannot be established
is one `realign` must refuse anyway, so writing it moves the failure later, leaves a file the next
run merges into, and puts a partial record where the operator reasonably reads a complete one. The
asymmetry decides it: refusing costs a re-run on an attached checkout, while accepting costs evidence
and verdicts from one ref presented as another's, silently and with nothing in the report to reveal
it.

## Layer vocabulary

Fixed enum, in this order — the order is load-bearing for sorting (below):

`agent-hooks` · `agent-instructions` · `repo-hooks` · `vcs-hooks` · `ci-lanes` · `gate-scripts` ·
`satellite-workflows` · `branch-protection` · `forge-apps` · `external-integrations` ·
`decision-records` · `documents` · `components` · `dependencies` · `source`

The vocabulary is deliberately forge-neutral and platform-neutral: a consumer whose forge, CI
system, or agent harness differs still maps onto these. A lane that needs a sixteenth adds it to
this enum with a `schema` bump, never as a free-text value.

**The first ten are the enforcement lane's**, walked by `overengineering:audit`. **The last five are
the justification lane's**, examined one target at a time by `overengineering:justify`, and they
never inventory an enforcement kind: a target whose whole content an enforcement layer's discovery
probe would inventory routes to the enforcement lane and produces no row at all. The order remains
load-bearing for sorting, so the five are appended rather than interleaved.

## Document shape

````markdown
---
<frontmatter above>
---

# Overengineering audit — findings

## Evidence availability

<per-tier present / partial / unavailable, with the probe that established each — scrutiny-method §8
 obligation 1. This section leads the report; it changes what UNPROVEN means for every row below.>

<a targeted run appends its own lines here, each prefixed `targeted <target>:` and never replacing a
 per-tier token above. The prefix is required, and it is what lets a consumer separate the two: the
 spine capture copies only the unprefixed per-tier tokens, and a cross-run comparison reads only
 those, so an appended line can never be mistaken for a tier moving.>

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
| `check` | `overengineering/<producer>/rule-<layer>` — lowercase `[a-z0-9-]` per segment, `<producer>` one of `audit` or `justify`, the layer taken from the enum above. The producer segment is part of the identity: two lanes judging the same surface would otherwise derive one id, and each run would carry or close the other's finding. |
| `claim` | `enforcement-item` for an ordinary finding of the enforcement lane; `artifact-item` for one of the justification lane; either with `(member=<name>)` where an aggregating container carries per-member sub-verdicts. A canonical id with bound parameters — never free prose. |
| `sites` | One `{surface, anchor/v1}` per artifact the finding is about. `surface` is the repo-relative path or kind-prefixed identifier; `anchor/v1` is `sha256` of the ordered locator path within that surface, truncated to 8 hex — `[<artifact-identity>]` for a whole item, and for a sub-member the member's path within its container: `[<container>, <member>]` where the member list is flat, and the member's full ancestry where the members are nested headings, per "A heading is a member, not an ordinal" below. **Never a positional ordinal.** A cross-artifact finding (a CONSOLIDATE naming two mechanisms covering one concern) carries *every* site here — the constituents are where all of a finding's sites bind, and that is what makes such an id reproducible across runs. See "Cross-artifact findings" below for how the sites then appear in the finding. |

The id is `sha256` over the `US`-joined `[check, claim, *flattened canonically-sorted sites]`,
truncated to 16 hex — the convention owns that computation and this document does not re-derive it.

**Deliberately excluded from the constituents: the verdict, the evidence, the status, and every
prose field.** They are recomputed every run. An id that moved when a verdict moved would break
carry-forward by construction, which is the one property the whole contract exists to provide.

**`check` is a hash input, never a serialized field, so no consumer can read the producer off a
finding.** The id is `sha256` and does not invert. A consumer that needs to know which lane produced
a row reads **`Layer`**, which is in the spine and present on every row including rows carried
forward from `schema: 1`. The layer enum partitions cleanly by producer and stays partitioned by
construction: `overengineering:audit` writes only the ten enforcement layers, and a pointed lane
routes an enforcement target away rather than judging it, so it never writes one. The five
justification layers are therefore reachable only from a justification-lane run. Any future producer
must either take its own layers or make its rows indistinguishable to every existing consumer, which
is the reason this partition is stated here rather than left as an observation about today's enum.

**Cross-artifact findings: the id binds every site; the body names every site.** The spine's
`Artifact` field is single-line by contract and carries the finding's **primary subject** — the one
path or identifier it is filed under and sorts by. It is not the site list and cannot be, because
identity lives in the `sites` constituents above. A finding about more than one artifact therefore
names **every** site in its body, saying what each one contributes, rather than one site plus a
footnote.

**Kind prefixes for items with no path in this repo.** `protection:<rule-name>`, `app:<name>`,
`integration:<name>`, `package:<ecosystem>/<name>` for a declared dependency or pinned tool in the
`dependencies` layer, and — for layers 1–7 — `settings:<path>` for a *registration surface* outside
the repo tree, such as a user- or machine-scope settings file that registers a mechanism governing
work here. The prefix set is closed here and is the same set a `sites` `surface` draws from; a new
one is added to this list, never coined per run, or two runs derive two different ids for one item.

**`package:` carries its ecosystem because a name alone is not an identity.** The `<ecosystem>`
segment is the manifest that declares the dependency — `npm`, `pypi`, `nuget`, `go`, `cargo`, or
`tool` for a pinned CLI binary with no package manifest. A polyglot consumer routinely declares one
name in more than one of them, and an unqualified `package:ruff` would derive a single id for the
PyPI package, an npm package of the same name, and a pinned binary, so a suppression or a status an
operator wrote against one would carry onto two they never judged. This is the same collision the
heading-ancestry rule below prevents for sections of a file.

**A heading is a member, not an ordinal.** Where a target names a section rather than a whole file
(`path#heading`), its `anchor/v1` locator path is the heading's **full ancestry** within the file,
outermost first: `[<file>, <h2>, <h3>]` for a subsection, `[<file>, <heading>]` only where the
heading is top-level. Ancestry is what makes the locator a member path rather than a label, and it
is required because heading text repeats: a file with `### Rationale` under two different sections
would otherwise derive one anchor for both, and a status or suppression an operator wrote against
one section would carry onto a section they never judged.

**An ambiguous heading is refused, not disambiguated.** Where the full ancestry is still not unique
in the file, the lane **declines the target**, names the collision, and asks for a whole-file target
or a disambiguating rename. It does not fall back to "the first one" or to an occurrence count:
both are positional ordinals under another name, and the `sites` rule above forbids those precisely
because the next run renumbers them. A line number is not admissible for the same reason, so a lane
pointed at a line widens to the enclosing heading or file and says so in its report rather than
coining an id no second run would reproduce.

**A routed target produces no id and no row.** Where a lane hands a target to another lane rather
than judging it, there is nothing to identify: the routing is reported inline by the lane that
declined it, and the owning lane derives its own id when it runs.

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
**line-formatted** — the `id` as the finding's own heading line (`### <finding-id>`), and each
remaining field on its own line, in the fixed order shown in "Document shape", with the literal
bold label and a single-line value drawn from a closed vocabulary or a path. Nothing else may
appear on a spine line.

**Everything else is free prose**, recomputed fresh each run: evidence, liveness, intent,
rediscovery, cost, owner, and the conditional fields below.

The split is a contract, not a formatting preference, and it exists for two consumers:

- **Diffing across runs compares the spine only.** The spine of a run is the ordered sequence of
  `(id, layer, artifact, verdict, status)` tuples, extractable with a line filter and comparable
  with a line diff. Two independent prose passes over the same tree will never be byte-identical,
  and live evidence sources move between runs by design (an appending log grows; a history query
  returns more). A comparison over full prose rows reports model noise as change and is worthless.
- **The delta lane inherits this as its contract.** `overengineering:delta` reports "what changed
  since the last run" by reading the spine; the prose is context for a human, not an input to a
  comparison.

Two rules keep the spine extractable: a spine value never contains a newline, and a spine value is
never a sentence. Anything that wants to be a sentence is prose and belongs below the spine.

## The spine-capture obligation

**This artifact is rewritten in place, so a cross-run comparison must persist a spine of its own.**
"Re-run merge semantics" below makes a re-audit merge into the existing file, and the audit writes
per layer as it walks, so the prior content starts disappearing at the first layer rather than at the
end of the run. **After an audit has run, there is nothing left to compare against.** A consumer that
tries to "audit, then diff the file" does not fail loudly; it reports "no baseline" every cycle
forever. A separately persisted spine is mandatory.

**That spine is captured at the end of a cycle, from the post-audit artifact**, and it is the
baseline the *next* cycle compares its own post-audit spine against. The timing is load-bearing, and
`Status` is why: `overengineering:realign` is the sole writer of a status and a human runs it
**between** cycles, while an audit only ever writes `OPEN` on a newly-seen id and carries every other
status forward untouched. A capture taken at the *start* of a cycle therefore already holds whatever
status realign wrote, the audit carries that same status through, and both sides of the comparison
agree on it for every pre-existing finding — the one class that reports "a human acted" becomes
unobservable in exactly the case it exists for. Capturing after the audit leaves a later realign on
the far side of the baseline, where the next cycle sees it.

**One pre-audit capture is sanctioned: the bootstrap.** A home holding this artifact and no
`spine-baseline.md` — audits were run manually here before any comparing consumer existed — captures
the artifact's spine pre-audit, so that first cycle has a baseline at all. A bootstrap cycle **cannot
detect a status change**, for the reason above, and a consumer says so rather than implying coverage
it does not have. Every later cycle can.

**The capture is a sibling file in the same resolved home, not a second artifact.** `spine-baseline.md`
beside `findings.md`, memory tier, branch-keyed, and ephemeral on exactly the same terms:

```yaml
---
type: overengineering-spine-baseline
schema: 1
captured: <ISO-basic UTC, colon-free — end of the cycle that wrote it>
source-date: <the `date` frontmatter of the artifact captured from: this cycle's post-audit artifact, or on a bootstrap the pre-audit one>
source-scope: <that same artifact's `scope`>
branch: <branch at capture; never `HEAD`, and never written at all when the branch identity is unresolved>
compared: <ISO-basic UTC, written by the LATER cycle that consumes this baseline, when its comparison completes; absent until then>
---
```

`captured:` and `compared:` therefore belong to two different cycles: the one that wrote the baseline
and the one that consumed it. A freshly written baseline carrying no `compared:` is the ordinary
steady state, not a fault.

Its body carries only material already fixed by this contract — each finding's `### <finding-id>`
heading and its four spine lines verbatim, each container's `**Members (<n>):**` lines verbatim, and
the per-tier tokens from `## Evidence availability` — and no prose field, ever.

Three properties keep it from becoming a second record of findings:

- **Its `type` is `overengineering-spine-baseline`**, deliberately neither `overengineering-findings`
  nor `review-findings`. `overengineering:realign` neither reads it nor is selected onto it, and no
  fix relay can locate it.
- **It carries no judgment of its own.** Every line in it was copied from an artifact this contract
  already governs; it asserts nothing the artifact did not already assert, and it is never merged
  into.
- **It is a snapshot, not a history.** One file per home, overwritten by the next end-of-cycle
  capture — but **only by a cycle that consumed it.** A capture is earned by having completed the
  comparison and by nothing else: where the cycle stopped short (the audit never ran or failed, the
  schema was unrecognized, two homes disagreed, the branch identity did not resolve) the stored
  baseline is kept exactly as it is and that cycle writes none. Overwriting it would move the
  comparison's origin silently forward past a cycle nobody compared, and whatever moved in between
  would be reported by no cycle at all. The kept baseline instead widens the next comparison's span,
  which that cycle names from its `source-date`.

## Aggregating containers — the container is the finding

Where an item aggregates independent members — a hooks manifest registering several entries, a lane
whose own definition carries its member list — **the container is the finding**: one spine row, one
container verdict, one id. Members are deliberately **not** spine rows. Promoting them would make
the container's own judgment unlocatable, and it would put two grains of thing in one sort order.

*When* per-member reporting is warranted is a question about the lane's item inventory and belongs
to the lane's own walk document. This section owns only the shape it takes in the artifact.

Member verdicts must stay extractable, so they are **line-formatted inside the container's body**,
under a `**Members (<n>):**` label, one entry per member:

```markdown
**Members (2):**

- `<member-id>` `<member-name>` — **<VERDICT>** — <prose, wrapping freely below>
- `<member-id>` `<member-name>` — **<VERDICT>** — <prose, wrapping freely below>
```

The three fixed constituents — id, name, verdict — lead the entry in that order and stay on its
first physical line; everything after the second em dash is prose. A member id derives from the same
rule as every other id, with `claim` = the producing lane's own claim carrying `(member=<name>)` —
`enforcement-item(member=<name>)` on the enforcement lane, `artifact-item(member=<name>)` on the
justification lane — and its site anchored at the member's ordered locator path within the
container: `[<container>, <member>]` where the member list is flat, and the member's full ancestry
where the members are nested headings, per the ancestry rule under "Finding ids". A member keyed by
name alone would collide wherever a container repeats a member name at two depths. So a suppression
or a realignment can key on a member without keying on the container.

**A member's verdict is its own.** The container's spine verdict judges the aggregating surface as a
whole; it neither overrides a member's verdict nor is computed from them.

**A member's basis goes in its prose.** The entry format is fixed at three leading constituents, so
a member carries no `Basis` field. Where a lane's rules bind a verdict to a basis — a `KEEP` that
must be `measured`, say — the member's prose states the basis in those same words, and a member
verdict whose prose states none is read as unsupported rather than as measured.

**What the cross-run diff covers.** The documented spine diff compares **container spines** — that
is what the spine's line format guarantees, and it is unaffected by how many members a container
carries. Member lines are comparable **within a finding**: same container id, members matched by
member id, read for a changed verdict token. A run reporting member verdicts states how many, so a
reader can never mistake a member count for a finding count.

## Per-finding fields

| Field | Spine | Required | Content |
|---|---|---|---|
| `Layer` | yes | always | One enum value. |
| `Artifact` | yes | always | Repo-relative path; or, for an item with no path in this repo, a kind-prefixed stable identifier from the closed set under "Finding ids" so it cannot collide with a path. On a multi-site finding this is the primary subject only, and the body names every site. |
| `Verdict` | yes | always | One of the six tokens. Argued per `context/scrutiny-method.md` §6. |
| `Status` | yes | always | One vocabulary value (below). Written `OPEN` by the audit on a new finding; otherwise carried forward. |
| `Protected` | no | when a class match bore on the verdict, whether or not that class carries a cap | Which class and which pattern matched; whether a retirement cap was applied; and, when it was, the retirement-direction verdict it would otherwise have been. A class that carries no cap says so, and the row's `Verdict` and `Basis` still carry the earned-keep judgment on the item's own evidence. Recording an uncapped class match here is what keeps a class claim out of the verdict, where it would read as an answer to a question it does not answer. |
| `Evidence` | no | always | At least one empirical citation with its tier (`scrutiny-method` §2), or `UNPROVEN` naming the tier consulted and whether it was **silent** or **unavailable**. Doc-only support is marked `unverified`. |
| `Liveness` | no | always | Three independently-answered lines — source posture, wiring, runtime enforcement — each naming what was actually read. An unread question is recorded as unread, never inferred. |
| `Intent` | no | always | The reconstruction and its confidence; `OPEN-INTENT` where the run was unattended and confidence was low. |
| `Rediscovery` | no | always | The simplest adequate re-solution, native-first, with the tech-drift check and its date — or one of the two sanctioned dispositions below. |
| `Cost` | no | always | Removal, refactor, and testing cost as it entered the verdict. |
| `Owner` | no | always | The resolved owner, or `operator (last resort)`, with the authorship evidence that resolved it. |
| `Threshold` | no | when one was applied | Which threshold row fired, its source, and its analogical label carried verbatim. A threshold cited without its label is a contract violation, not a style slip. |
| `Routed-to` | no | when routed | The neighbor surface the finding was handed to, and whether that surface was present. |
| `Delegation` | no | `DELEGATED-EXTERNAL` only | The pointer to the delegation artifact. |
| `Ablation` | no | `ABLATION-*` only, and `n/a` on every row in a justification layer | Rung reached, window length, window end date, and the durable pointer. On a justification-layer row the literal `n/a`, because a document or a decision record has nothing to disable and watch, and a row that simply omitted the field would leave a reader unable to tell a gate that does not apply from one nobody answered. |
| `Judgment` | no | when one was persisted | The suppression entry id and the layer it was written to. |
| `Basis` | no | on every row a `schema: 2` run writes or rewrites | The evidentiary basis of the verdict, one of three values. `measured`: at least one tier-1–4 citation supports it. `class-inferred`: it rests on §6's non-derivable-oracle clause or a §7 protected-class match, and every consult was silent or tier-5-only. `unexamined`: nothing was measured, either because no tier was consulted or because every tier consulted came back silent or unavailable, and this value is legal **only** with `Verdict: UNPROVEN`. The two readings share a value on purpose: a consult that returned nothing supports a verdict no better than a consult never made, and the `Evidence` field already records which tiers were tried and what each returned. **`class-inferred` wins the overlap.** Its condition and `unexamined`'s are both satisfied by a row that measured nothing, so measuring nothing cannot be the discriminator; what the verdict rests on is. A row whose consults were all silent or tier-5-only is `class-inferred` where the verdict rests on the oracle or the class match, and `unexamined` where it rests on neither. This precedence binds **both** producers, not only the pointed lane. A `KEEP` is `measured` or it is not a `KEEP`, because §6 already requires a tier-1–4 citation for one; a `class-inferred` KEEP would have to cite its own oracle, which makes it `measured`. A row carried forward from a `schema: 1` run has no `Basis` until it is re-evaluated, and consumers display `not recorded (schema 1)` rather than inventing one. |

**The audit perturbs the telemetry it reads.** Writing this artifact fires the very recorders whose
rows the run is reading, so a tier-1 window read late in a run contains the run itself. Two
obligations follow: **bound the tier-1 read window at walk start** and state the bound, so no
verdict's evidence grows underneath it; and where rows are attributable to the audit run itself,
**exclude them and say so** — how many, and on what attribution. Self-generated rows admitted as
evidence would let an audit prove a mechanism live by auditing it.

**`OPEN-INTENT` is an `Intent` value and never a `Status`.** The status vocabulary below is closed
and does not contain it, so a finding is never "status OPEN-INTENT". A report's *count of
OPEN-INTENT rows* counts **findings** whose `Intent` is `OPEN-INTENT`; a run that also counts
members says so explicitly and reports the two numbers separately.

**Rediscovery without a live drift check.** `scrutiny-method` §5 requires the tech-drift check to be
dated rather than remembered; it does not require one *per item*, and per-item checks across a large
surface are both unaffordable and, for some items, meaningless. Two dispositions are sanctioned, and
each is written into the field in these words:

- `Deferred — no tech-drift check claimed` — a re-solution is stated, but no current-documentation
  check was made this run. Nothing else in the finding may then read as though one was.
- `Not applicable — <reason>` — no re-solution is this run's to make: custody is upstream (§12), or
  liveness is unread, so there is no reconstructed problem to re-solve yet.

**Batch the drift check per lane or per class rather than per item.** One dated check against the
platform's current documentation covers every item that would be re-solved against the same native
mechanism, and each of those findings cites that one check with its date. Twenty items sharing one
native answer do not need twenty fetches, and pretending they do is what makes the field get skipped
in silence instead of dispositioned in the open.

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

**Every producer re-reads immediately before it writes.** Two lanes write this file, so a producer
that merges against a copy it loaded earlier in its run silently drops whatever the other wrote in
between — and drops it with no record, because rule 3 writes a closure row only for a layer this run
walked, and the two producers walk disjoint layers. Load the on-disk artifact immediately before
each write, merge against that copy, and read a `date` newer than the one this run loaded as another
producer's work to merge rather than to overwrite. This is a producer obligation binding on every
writer, not one lane's convention, and it is what stands in for a lock this contract does not claim.

**A targeted run merges narrowly, and this clause governs rules 1 to 4 and rule 6 below it.** Rule 5
fires only on a verdict this run recomputed, which in a targeted run is only a target, and rule 7 is
read-only, so neither needs scoping. Where `mode: targeted`, the run examined only what `targets`
names, so:

- **A site is in `targets` when this run derived that site from a `targets` entry**, never when its
  `surface` string matches one. The two are different value spaces: a `targets` entry may be a
  `path#heading`, whose site carries the file as its `surface` and the heading's ancestry in its
  `anchor/v1`, and a directory target is one item whose site is the directory itself. So a target
  naming a heading covers the single site whose anchor is that heading's ancestry and no other
  section of the same file, and a target naming a directory covers the directory's own site and
  never the separate sites of the files beneath it. Matching on `surface` alone fails both ways: a
  heading target would match no site at all, stranding the pointed run so it could not write its own
  finding, and a directory or file target would sweep in findings about sections the run never
  opened, which rule 3 would then close.
- **Rules 1 and 2 apply to a finding ANY of whose sites is in `targets`.** A run that examined one
  site of a multi-site finding examined that finding: it derived the row from the target in front of
  it, and the row names every site it binds. So the verdict is recomputed and the status carried.
- **Rule 3 applies only to a prior id EVERY of whose sites is in `targets`** and whose item is now
  absent. A pointed run at one artifact must never close a finding about another.
- **The two quantifiers differ on purpose, and unifying them breaks the contract either way.** Rule 3
  closes a finding, so it must be conservative: closing on partial coverage would retire a finding
  the run never fully examined. Rules 1 and 2 only refresh one, so they must be permissive: this lane
  takes one target per run, and a finding binding two sites can never have every site in a one-entry
  `targets`. Made restrictive, such a finding would fall to rule 4 on every subsequent run, stamped
  `not re-evaluated this run` by runs that demonstrably did re-evaluate it, and no walk could rescue
  it because `overengineering:audit` walks only the ten enforcement layers. It would carry a stale
  verdict and a stale date forever.
- Every other prior id **carries forward per rule 4**, regardless of `scope`. In a targeted run
  `scope` records the layers the targets fall in, for ordering; it never asserts a walk.
- The run-level sections `## Evidence availability`, `## Suppressed`, and `## Closed since last run`
  are **not rewritten for anything outside `targets`**. A targeted run appends its own per-target
  evidence-availability lines, each carrying the `targeted <target>:` prefix the section's shape
  requires, rather than replacing the walk's per-tier tokens, and computes
  suppression dispositions only for entries whose ids have **any** site in `targets`, reporting the
  rest as **not evaluated this run**. This follows rules 1 and 2 rather than rule 3, for their
  reason: a disposition reports whether a live finding is currently suppressed, which is a refresh
  and not a closure, and an entry the run examined at one of its sites is one the run can speak to.
  Stamping it `not evaluated this run` would be the same false staleness rule 4 would apply to the
  row itself. `## Summary` is still recomputed from the spine actually written, as rule 6
  requires.
- **In a targeted run `scope` carries forward and grows; that run never overwrites it.** A walk still
  records exactly the layers it walked, which is what the `scope` frontmatter row defines and what
  merge rule 3 reads; this bullet governs the pointed producer only, which walks nothing. A targeted
  run keeps the prior
  artifact's `scope` and adds the layers its own targets fall in. Replacing it would narrow the
  file's record of what the last walk actually covered, which is the one thing rule 4 and the spine
  baseline's `source-scope` both read it for.

The reason is asymmetry: a walk that omits a layer says so in `scope` and rule 4 protects it, but a
targeted run walks no layer at all, so without this clause rule 3 would read every un-examined
finding in the target's layer as a deleted artifact and close it. That is the loss the section below
exists to prevent, arriving through the other door.

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
6. **The spine is authoritative over the prior artifact's own prose.** Only the fields in rule 1 are
   carried; a prior run's summary, counts, and narrative are **recomputed from the spine actually
   written this run** and never inherited. A prior summary that contradicts its own spine is a
   miscount, not a second source — recompute it and say nothing more about it.
7. **Prior-artifact prose claims about status are not authoritative; the `Status` spine lines are.**
   A sentence elsewhere in the file asserting that something was accepted, rejected, or already
   realigned carries no weight against the spine line for that id. Where the two disagree, the spine
   wins and the disagreement is reported, because one of them was written by a judgment and the
   other by a narrator.

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

| Obligation | `audit` | `justify` | `realign` | `delta` |
|---|---|---|---|---|
| Writes the artifact | yes — the walking producer, `mode: walk` | yes — the pointed producer, `mode: targeted`, and only rows in the five justification layers | yes — status and status-bound fields only | **never** — a reader, and no writer of any field here |
| Mutates anything outside the artifact | **never** | **never** | only behind explicit per-item acceptance | the spine baseline, plus one queue route gated on config and presence; never the surface |
| Writes `Status` | `OPEN` on new findings; carries the rest forward | `OPEN` on a finding it has not seen; carries every other status forward | the sole owner of every transition | **never** — it reports that one moved, which stays realign's alone |
| Leads with the evidence-availability assessment | yes, before any finding | appends its own per-target lines; never replaces the walk's per-tier tokens | reads it; never recomputes it | reads the tokens and compares them run to run; never recomputes them |
| Refuses on a mismatched `branch:` or an unrecognized `schema:` | n/a — it writes them | yes for `schema:`, with a visible message, because it merges against what it finds; `branch:` is its own to write | yes, with a visible message | mismatched `branch:` → no baseline, naming both branches; unrecognized `schema:` → stop before invoking anything |
| Behavior when no branch identity resolves | writes **no artifact** — the walk runs, the inline summary is emitted, the persisted write is declined and the run says so | the same: the pass runs, the inline report is emitted in full, the persisted write is declined and the run says why | **refuses**, whether its own checkout or the artifact's `branch:` is the unresolved side; never compares | compares nothing and captures nothing, saying why |
| Behavior when the artifact is missing | n/a | n/a — it creates one, since a first pointed run has nothing to merge against | **stop** with a visible message naming both producers, `overengineering:audit` for a walk and `overengineering:justify` for a pointed run — the artifact-protocol missing-prerequisite rule; never scan on its own | not a stop but a **first run**: it says so, establishes the baseline, and reports nothing as a delta |
| Re-reads immediately before writing | yes — the producer obligation above binds every writer | yes | yes | n/a — it writes nothing here |

The `delta` column follows from what that lane is: it composes `audit` to produce this cycle's
artifact, compares that artifact's spine against the baseline the previous cycle left behind, and
captures a fresh baseline at the end of the cycle per the obligation above — so every write it makes
belongs to that mechanic, and the artifact's own writes stay in `audit`'s column.

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
