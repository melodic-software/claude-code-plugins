# Justification lane, the lane binding

The third lane of this plugin's scrutiny method. Its item is whatever artifact the operator points
at, and its question is the two-part one: was there a stated reason for this, and does that reason
still hold today.

**The method is not restated here.** `${CLAUDE_PLUGIN_ROOT}/context/scrutiny-method.md` sections 1
to 12 are lane-independent and apply verbatim. This document supplies only the four things its
"Lane binding" section asks a lane for, plus the rules a pointed lane needs that a walking lane does
not. Every bare `§N` below is a section of that method document. This document's own sections are
numbered `## 1.` to `## 12.` and are referred to as "section N", never as `§N`.

Status: **shipping**. The skill that binds it is `/overengineering:justify`.

Pointers into sibling files name the file and the section's prose title. Follow the title, not a
line number, and read the section rather than a summary of it here.

## 1. Routing precedence, before anything else

**Test this first, on every target.** The enforcement lane's discovery probes are in
`${CLAUDE_PLUGIN_ROOT}/skills/audit/context/surface-walk.md`, sections "Layer 1" through "Layer 10".

- **Whole content inventoried by an enforcement probe.** The target routes to `/overengineering:audit`
  and **no row is written** in the findings artifact. The inline report names the layer that claimed
  it. A row here would file a spine entry for an item another producer owns.
- **Only part of it inventoried.** A skill file whose always-loaded portion an instruction probe
  inventories, an instruction file that imports others: the target is classified under a layer in
  section 3, its row names the routed part, and `Routed-to` hands that part to `audit`. What survives
  the routing is what gets judged, and the row says which part that was.
- **Nothing inventoried.** Classify under section 3.

**The test for "whole" is whether anything of the target is left over.** A probe inventories a target
whole when the probe's own item is that file and no part of the file falls outside it: a registration
manifest is entirely a registration surface, and a standing-instruction file that states rules and
nothing else is entirely instruction text. A target is only partly inventoried when some part of it
is an item the probe does not claim. A skill file is the plain case, because its always-loaded
frontmatter is instruction text while its on-demand body is not. An instruction file that imports
others is the same shape: the enforcement probe inventories each imported file's instruction text as
its own item, which leaves the host file's composition, this set of imports gathered here, as
something no probe claims and this lane judges. Where the leftover part is nothing a reader could
point at, the target was inventoried whole and routes.

**Imports are read, not inferred.** An instruction file that pulls in others is a different item from
the files it pulls in. Open them, decide which of them an enforcement probe claims, and classify only
what is left. Guessing at an import graph produces a verdict about a file nobody examined. **An
import that does not resolve is recorded as unresolved**, named in `Routed-to` as an import whose
target was not found, and never treated as though the file had been read: an unresolvable import is
itself evidence about the host file, and inventing its contents would put a verdict on a file that
does not exist.

## 2. Item inventory, what counts as one item

**The item is what the operator points at.** This lane does not enumerate; it is handed a target and
judges that target.

Allowed target forms:

| Form | Example shape | The item |
|---|---|---|
| Path | a file or a directory | the file, or the directory as one item |
| `path#heading` | a file plus one of its headings | that section, identified by its full ancestry |
| Kind-prefixed identifier | a package, an app, an integration | the named thing |

**An ambiguous heading is refused, never disambiguated.** A heading whose full ancestry is still not
unique in its file does not identify an item. Decline the target, name the collision, and ask for a
whole-file target or a disambiguating rename. Falling back to the first occurrence, or to an
occurrence count, is a positional ordinal under another name, and the id contract in
`${CLAUDE_PLUGIN_ROOT}/context/findings-artifact.md`, section "Finding ids", forbids those for the
same reason it forbids line numbers: the next edit renumbers them and the item derives a different
id.

**A line or a comment target widens.** A target naming a line, or a comment, is widened to its
enclosing heading where the file has headings, and to the file otherwise. **The report's first line
states the widening**, naming what was pointed at and what is being judged instead. The reason is the
id contract in `${CLAUDE_PLUGIN_ROOT}/context/findings-artifact.md`, section "Finding ids": an
identity may never rest on a positional ordinal, because the next edit above it moves the line and
the same item derives a different id. When the target was a comment, the widening line also names
`code-tidying:dissolve-comments` as the owner of comments themselves.

**Things that each configure their own subject are separate items, not repetitions of one.** Where a
target describes a pattern that recurs, such as every bundle shipping its own setup component or
every module carrying its own configuration file, count the items by what each one is *about*,
rather than by what they have in common. A component that configures its own bundle and names that bundle's own settings keys
is a different item from the one next to it, so a count of one violation per occurrence is refused
and the refusal is stated with its reason rather than the number being quietly reduced. Separate the
occurrences that actually differ from the ones that do not, and say what distinguishes them: a
manifest listing ten entries of which eight share a trait and two do not is describing two groups,
and the two are evidence about the pattern rather than exceptions to it. Where the pattern itself is
worth a finding, it is argued **once**, naming what a shared alternative would have to preserve, and
never once per occurrence.

**Per-member sub-verdicts only where the member list is mechanical.** The container rule is the
enforcement lane's, in `${CLAUDE_PLUGIN_ROOT}/skills/audit/context/surface-walk.md`, section
"Granularity". Applied here it means: a decision-record log whose entries are numbered, a manifest
whose entries are listed, a document whose headings enumerate its parts may carry per-member
sub-verdicts. Prose that merely reads as having parts may not.

## 3. Layer vocabulary and discovery probes

Five layers, defined **by exclusion** after section 1: an item reaches these only when no enforcement
probe claimed it whole. None of them ever inventories an enforcement kind.

### `decision-records`

An accepted decision, in whatever form the consumer keeps them.

**Discovery probes.** The record's own status line and date; whether a later record supersedes it;
which files cite it; whether the thing it decided still exists in the tree.

**Layer notes.** A superseded record is not automatically retirable: superseded records carry the
reasoning that explains the successor. Ask what a reader loses.

### `documents`

Prose documents that are not instruction surfaces a layer-2 probe inventories: guides, references,
explanations, design notes, READMEs.

**Discovery probes.** Inbound links and citations from elsewhere in the tree; the last substantive
commit to the file as against a formatting sweep; whether a generator owns the file, in which case
the generator is the item and the output is not.

### `components`

A plugin, skill, agent, or comparable unit **as a unit**, excluding its always-loaded text and any
hooks manifest, both of which route under section 1.

**Discovery probes.** Whether the component is listed where the consumer lists such things; any
record the consumer keeps of it being invoked; its catalog or registry entry.

**Layer notes.** Absence of invocation evidence is silence, not waste. Most consumers record nothing
about which component ran, which makes tier 1 unavailable here rather than empty, and §2's
distinction between the two is the whole difference between UNPROVEN and RETIRE.

### `dependencies`

Declared packages and pinned tools. The identifier form is `package:<ecosystem>/<name>`, the
ecosystem being the manifest that declares it, per the closed prefix set in
`${CLAUDE_PLUGIN_ROOT}/context/findings-artifact.md`, section "Finding ids". One name declared in
two ecosystems is two items.

**Discovery probes.** Import or call sites in the tree; presence in the lockfile as a direct rather
than transitive entry; the upstream project's own status, which is a live check with a date, not a
remembered fact.

### `source`

Code constructs, judged by their call sites and by §3's three liveness questions.

**Protected classes.** This layer binds
`${CLAUDE_PLUGIN_ROOT}/context/product-code-lane.md`, section "4. Protected-class defaults,
extending §7", by pointer. Read that section before any verdict here; its classes are not repeated.

**Hand-over rule.** The product-code lane owns code-level overengineering, and its skill is a
specification ahead of its implementation. When that skill ships, `source` findings close under that
lane's own layers in a schema bump. Until then this layer answers the existence question for a
construct the operator points at, and never runs as a sweep.

## 4. Routing table

| Target class | Layer or route | Row |
|---|---|---|
| Hooks manifest | route to `/overengineering:audit` | none |
| Rules or instruction file an enforcement probe inventories whole | route to `/overengineering:audit` | none |
| Skill or agent file | `components`, always-loaded part routed | row, routed part named |
| Instruction file that imports others | `documents`, imported instruction text routed | row, routed part named |
| Decision record | `decision-records` | row |
| Prose document | `documents` | row |
| Declared package or pinned tool | `dependencies` | row |
| Code construct | `source` | row |
| Comment | widen to the enclosing heading or file, name the comment owner | row for the widened item |
| Line | widen to the enclosing heading or file | row for the widened item |

## 5. Evidence sources, mapped onto the §2 tiers

| Tier | This lane's sources | Lane-specific caveat |
|---|---|---|
| 1 | Whatever runtime or usage record the consumer actually keeps for the kind of artifact in hand | Most consumers keep none for documents and components, which makes this tier unavailable rather than silent |
| 2 | The introducing commit, its change request and linked issue, churn since, revert history | The workhorse tier for this lane; a shallow clone makes it unavailable, not silent |
| 3 | Incident and post-incident records naming the artifact or the hazard it addresses | Absence stays ambiguous by construction (§7) |
| 4 | Operator attestation, **and** external context the consumer has connected: ticketing, meeting transcripts, planning records reachable through the consumer's own configured tools | Recorded as attestation with its date and source, never promoted to a measurement |
| 5 | The artifact's own text: its stated rationale, its headers, its comments | Claims to verify, nothing more |

**Escalate in order and name every tier consulted**, marking each **silent** or **unavailable**. A
tier that was never reached is named as not consulted rather than omitted.

**Ask when unsure.** Where tiers 1 to 3 are silent and tier 4 could exist, ask the operator before
writing UNPROVEN. An operator who was there is a tier the lane can reach only by asking, and
recording UNPROVEN without asking spends the operator's attention on a question they could have
answered in a sentence. An answer of "I do not know" is recorded as UNPROVEN with the tier named,
never resolved in either direction.

## 6. Protected-class defaults, extending §7

§7's classes apply wherever this lane's artifacts implement them. This lane adds:

- **Accepted decision records with citing consumers.** The record is the reason other things are
  shaped as they are; retiring it orphans every citation.
- **License, security, and compliance documents.** Their retention is externally constrained, and
  the constraint is rarely written in the file itself.
- **Anything with declared external consumers.** A document, component, or package another party is
  told to rely on is a commitment, and in-tree silence says nothing about it.
- **The intentionally-dormant class carries directly** (§7). A break-glass runbook that has never
  been read is in its designed steady state.
- **`source` adds the product-code lane's classes**, by the pointer in section 3.

## 7. Preflight additions

The shared preflight is `${CLAUDE_PLUGIN_ROOT}/skills/audit/context/surface-walk.md`, section
"Preflight", and it runs as written; its sanctioning-record probe is lane-independent and is not
restated here. This lane adds four:

- **Vary the query form before any absence claim.** A single grep is not a search. Vary the wrapping
  (a phrase broken across a line break defeats a single-line match), the hyphenation, the casing, and
  the obvious synonyms. Record which forms were tried. "Not found" is a finding only after this.
- **Retire costs more than keep.** A RETIRE row names the surfaces searched and what a counterexample
  would have looked like. A retirement resting on one document or one query form is refused, and the
  row stays UNPROVEN until the search is done properly.
- **Targeted mode always.** Every run of this lane writes `schema: 2` and `mode: targeted`, lists
  what it examined in `targets`, and writes a `scope` that carries the prior artifact's value
  forward with these targets' layers added. The frontmatter contract is in
  `${CLAUDE_PLUGIN_ROOT}/context/findings-artifact.md`, section "Frontmatter", and the merge
  consequences are in that document's section "Re-run merge semantics".
- **Re-read before write.** Load the artifact from disk immediately before writing, merge against
  that copy, and record its `date`. Another session may have written between the read that started
  this run and the write that ends it.

## 8. The two gates, answered separately

**Every row answers the earned-keep gate**: does this artifact's reason for existing still hold, on
the evidence cited.

**The ablation gate does not apply on this lane's five layers**, and every row says so with
`ablation: n/a`. Ablation means disabling a mechanism and watching what escapes; a document or a
decision record has no such observable. The gate applies only to the enforcement kinds section 1
routes away, and it is that lane's to answer.

**A class claim presented as the verdict is a defect.** "It is a convention document, so keep it" is
a class match, not an earned keep. The two are recorded in **different fields of one row**, not as
two rows and not as two `Basis` values: the class match and the pattern that matched it go in
`Protected`, and `Verdict` plus its single `Basis` carry the earned-keep judgment on its own
evidence. A row whose `Protected` names a class while its `Basis` reads `measured` is the honest
shape, and it says exactly which of the two the operator is being asked to trust.

Two rows would not merely be untidy, they would be invalid: ids are derived from `check`, `claim`
and `sites`, and `Verdict` and `Basis` are excluded from the constituents, so a second row about the
same item in the same layer derives the **same id** as the first. One item, one row, one verdict.

## 9. Basis assignment

`Basis` is defined in `${CLAUDE_PLUGIN_ROOT}/context/findings-artifact.md`, section "Per-finding
fields", and is not redefined here. Two consequences bind this lane directly:

- **A row that measured nothing, and rests on nothing else, is UNPROVEN and `unexamined`.** That
  covers a row with no tier consulted and a row whose every consult came back silent or unavailable
  alike. An `unexamined` row carrying any verdict other than UNPROVEN is a contract violation.
- **`class-inferred` takes precedence where the verdict actually rests on a class.** A row whose
  consults were all silent or tier-5-only, but whose verdict rests on the method's non-derivable
  oracle or on a protected-class match, is `class-inferred` and not `unexamined`. The two are
  distinguished by what the verdict leans on, never by how little came back: measuring nothing is
  the condition both share, so it cannot be the discriminator.
- **A KEEP is `measured` or it is not a KEEP.** A keep resting on a class match is the fused shape
  section 8 refuses. Where the oracle itself is cited, the row is `measured` and the citation is
  what makes it so.

## 10. No target, the fallback ladder

**Never enumerate the repository.** A bare invocation follows this ladder and states which rung it
used:

1. **Conversation context.** Where the session has been discussing an artifact, infer it, and
   **confirm the inference in one line before walking**. A compacted session's summary can name files
   nobody ever pointed at, so the confirmation is not a courtesy.
2. **Offer git-age discovery.** Offer to rank candidates by first-seen date, oldest first, and
   **wait**. Never run it unasked, and never present its output as findings.

   **Corroborate before presenting.** Age plus low churn ranks; it does not evidence disuse, and on
   this repository it was measured at 1 real candidate in 638 ranked ones. So the ranking is a
   shortlist to check, not a shortlist to show: every ranked path is searched for inbound references
   under section 7's varied query forms, and a path that has one is dropped before the operator ever
   sees it. The search counts a citation from **anywhere in the repository, the path's own directory
   included**. Present the survivors with both counts, the ranked and the surviving, so the operator
   can tell a path nothing cites from a path nobody searched for properly.
3. **Ask.** With no context and no accepted offer, ask the operator what to point at.

## 11. Boundary against existing owners

The enforcement route is section 1. Beyond it, this lane reports and hands off; it never applies a
remedy.

| The finding is about | Owner |
|---|---|
| Instruction text, its wording or its effect on a model | `claude-config:audit-instructions`, `claude-config:unhobble` |
| Comments, their content or their residue | `code-tidying:dissolve-comments`, `code-tidying:audit-comment-residue` |
| Unreachable or dead code | `code-tidying:audit-dead-code` |
| A document derivable from its source, or noise inside a document | `docs-hygiene:audit-derivability`, `docs-hygiene:audit-noise` |
| Duplication of what the harness ships natively | `claude-ops:audit-native-overlap` |
| Ranking candidates across several dimensions at once | `improvement:find` |
| The scrutiny posture itself | `discipline:reason-dont-recite`, `discipline:recheck-against-upstream`, `discipline:scrutinize-dont-coast` |

**Non-sibling routes are presence-gated.** Where the named skill is not installed, say so inline,
state what it would have owned, and record the fallback in `Routed-to`. A route to a surface that
does not exist is a dropped finding wearing a handoff.

**The §10 boundary, restated.** The remedy is refactor or remove, decided by the operator after the
report. This lane never proposes an addition, and a finding whose recommendation is "build something
new" is outside the method.

## 12. Known limits, each of them chosen

- **`overengineering:realign` presents this lane's rows and never executes them.** Its rollback
  ladder is enforcement-shaped, and a per-layer ladder for these five layers does not exist yet. The
  row is displayed with its owner from section 11 and no rung is offered.
- **`overengineering:delta` never compares this lane's findings.** It composes the enforcement lane,
  whose scope names only the ten enforcement layers, so these rows are outside every comparison it
  makes rather than missing from one.
- **A `Basis` move is invisible to `delta`.** `Basis` sits outside the spine on purpose, so the
  cross-run diff stays a statement about verdicts. A row whose evidence improved from
  `class-inferred` to `measured` reports as unchanged.
- **Two sessions writing one artifact rely on re-read-before-write, not a lock.** The obligation
  binds both producers and lives in the shared contract rather than here, so neither lane can honour
  it alone. It makes the window small. It does not close it, and no lock is claimed.
- **A citation search scoped by location misses citations, the way one scoped by name does.** Section
  7 varies the query form, which catches a document cited under a different name. The matching trap
  is a document cited from a place the search does not look. Excluding a document's own directory is
  the common form: neighbouring documents cite each other, so that exclusion drops exactly the
  citations a tightly-grouped set has, and reports a cited document as uncited. Section 10's
  corroboration step is therefore scoped to the whole repository, and any narrowing of a citation
  search by location is a new instance of this limit rather than an optimization.
