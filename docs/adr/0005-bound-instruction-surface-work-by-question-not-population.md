# Bound instruction-surface work by the question it asks, not the files it reads

- Status: accepted
- Date: 2026-07-25

## Context

[ADR 0004](0004-rightsize-instruction-surfaces-by-incumbent-first-arbitration.md) commits this
repository to two deliverables — a cross-surface instruction-conflict detector (L2) and an
evidence-tiered criteria catalog (L3) — under two constraints that pull against each other:

- **D-11** requires reconciling with issue #1225 before anything sweep-shaped is built, on the
  stated grounds that *two repo-wide sweeps become two routers*.
- **D-3** forbids a bulk sweep of `plugins/**` and rules that findings land as checks in the plugin
  that already owns each surface — **no new router**.

Issue #1225 (*"Sub-agent conventions: codify from latest official docs, then audit all plugins"*)
audits sub-agent definitions in two gated parts: codify three conventions (existence qualifier,
frontmatter surface, rationale/feature catalog), then audit every plugin against them — both the
plugins that ship sub-agents and *"every plugin that lacks sub-agents but would benefit"*. Its own
locked decisions require extending the existing plugin-authoring conventions surface rather than
standing up a parallel one.

A collision register written early in the effort classified #1225 as *"structurally a second
repo-wide sweep."* Read first-hand, that classification is too coarse in exactly one way, and
correcting it is what makes the boundary clean. This ADR is the D-11 reconciliation.

Populations, enumerated in this checkout rather than estimated:

| Surface | Count | Where |
|---|---|---|
| Plugins | 60 | `plugins/*` (matches `.claude-plugin/marketplace.json`) |
| Agent definitions | 7 | `plugins/plugin-quality/agents/auditor.md`; `plugins/review/agents/` (6) |
| Plugins shipping any `agents/` directory | 2 | `plugin-quality`, `review` |
| Shipped skills | 181 | `plugins/*/skills/*/SKILL.md` |

The skill count is decomposed because it was miscounted twice. The stated pattern
`plugins/*/skills/*/SKILL.md` — one file per skill directory — yields **181**. A recursive
`find plugins -name SKILL.md` yields **187**; the difference is exactly **6** upstream `vendor/`
materializations nested inside skill directories (`context7/lookup/vendor/cli`,
`context7/lookup/vendor/find-docs`, `dometrain/sync/vendor`, `playbooks/boris/vendor`,
`playbooks/skill-authoring/vendor`, `playwright/playwright/vendor`). Those are upstream copies this
repository never hand-edits. **181 is the shipped population, and it is the one any downstream
inventory uses**; 187 counts vendored copies and would point remediation at uneditable files.

## Decision

### 1. The discriminator is the question, not the population

The file populations genuinely overlap. #1225's *conforming* population is 7 files in 2 of 60
plugins, but Part 2's "would this plugin benefit from one" half reaches all 60 and means reading
each plugin's skills and instructions. L2 and L3 operate on 181 skill bodies plus `CLAUDE.md`,
`.claude/rules/`, prompt-type hook text, agent definitions and output styles. **So the population
is not the discriminator.**

The question is. #1225 asks *does this sub-agent earn its existence, and is its frontmatter
conformant*. L2 asks *do two instruction surfaces contradict each other*. L3 asks *is this criterion
backed by official documentation, and at what evidence tier*. Three different observables.

D-11's stated concern is infrastructural — two sweeps becoming two routers. Two passes reading the
same files to answer orthogonal questions need no shared traversal to stay correct, and D-3 forbids
either of them from standing one up regardless. What the shared population does create is ordinary
scheduling overlap between #1225 Part 2 and L2/L3: a coordination note, not a mechanism.

The one genuine intersection is that `claude-config:audit-instructions` inventories agent-definition
markdown as one of its surfaces (`plugins/claude-config/skills/audit-instructions/SKILL.md:78`,
`:82`, with `agents` as a scope argument at `:67`), so both efforts read `agents/*.md` —
`audit-instructions` for instruction content versus current model capability, #1225 Part 2 for
existence qualification and frontmatter conformance. Same files, orthogonal questions. Neither
effort waits on the other, and neither needs a router to reach those 7 files.

### 2. L2's novel scope is every contradiction pair C6 does not operationally cover

**A partial incumbent exists, and the earlier "no incumbent" finding was wrong.**
`claude-memory:audit` ships check **C6 Consistency [FAIL]** — *"Do any instructions contradict each
other across CLAUDE.md, CLAUDE.local.md, and rules files?"*, grading contradiction FAIL and
redundancy WARN (`plugins/claude-memory/skills/audit/reference/criteria.md:107-119`), grounded in the
official-docs line *"If two rules contradict each other, Claude may pick one arbitrarily"*. It is
wired live, not a stray reference: the workflow carries a dedicated **"Step 3: Cross-file consistency
check (C6)"** (`context/audit.md:61-67`) and the determinism contract places C6 in the judgment tier
(`SKILL.md:59-63`).

**What C6 operationally covers is narrower than its own description implies**, and the gap is what
L2 must be scoped against:

- Its discovery step is `find . -maxdepth 1` over `CLAUDE.md` / `CLAUDE.local.md` plus
  `find .claude/rules -name "*.md"` (`context/audit.md:8-21`) — both CWD-relative, so
  **nested `CLAUDE.md` files never enter its population**, and `~/.claude/rules/` appears nowhere in
  it.
- Its cross-file step compares `CLAUDE.md` against `.claude/rules/` **for contradictions** but
  `CLAUDE.md` against `CLAUDE.local.md` **only for redundancy** (`context/audit.md:61-67`), and the
  per-file pass preceding it cannot see a disagreement between two files.

**The only pair C6 operationally covers for contradiction is root project `CLAUDE.md` versus project
`.claude/rules/`.**

**Therefore L2's novel scope is every contradiction pair C6 does not operationally cover** — stated
this way deliberately, because "cross-layer" is the wrong frame and would silently drop same-layer
pairs that are genuinely uncovered:

- root `CLAUDE.md` versus a **nested** `CLAUDE.md` — same layer, uncovered;
- `CLAUDE.md` versus `CLAUDE.local.md` **for contradiction** — same layer, uncovered;
- a **user-global** rule versus a **project** rule — same layer, uncovered;
- repo `CLAUDE.md` versus a **skill body**; a skill's stated default versus its own `description`;
  agent definitions, prompt-type hook text, output styles — cross-layer, uncovered.

**One pair in that set is drift rather than conflict, and separating them matters.** A plugin README
is never auto-loaded, so a skill body that disagrees with its README is never co-resident with it and
fails the co-residency gate by construction — the same structure that makes split-brain a separate
check rather than a fourth conflict type. It is still worth detecting and its remediation is
different (reconcile the two texts, or delete the stale one), so it belongs to the drift check, not
to the conflict set. A skill's `description` is the opposite case: it is resident in the skill
listing whenever the budget admits it, so `description`-versus-body **is** a co-residency pair.

Under this repository's reuse-or-replace posture, L2 **reuses or explicitly extends C6 for the one
pair C6 covers, and never re-implements it**. A routing rule that hands *all* memory-layer
contradictions to C6 is wrong for the same reason the "cross-layer" framing is: C6 does not detect
most of them. The routing predicate is *operationally covered by C6*, not *inside the memory layer*.

**The reuse rule is presence-gated, because the incumbent is separately installable.** `claude-config`
and `claude-memory` are independent plugins, so a consumer can install the first without the second.
Deferring the one covered pair unconditionally would then drop it on the floor in a supported
configuration — the detector would silently omit root `CLAUDE.md` versus project `.claude/rules/`,
which is the most common contradiction there is. **Route out only when `claude-memory` is installed;
when it is not, cover that pair here and say so in the report.**

**Routing out is never dropping, and a mention is not a verdict.** A route is a pointer, not an
execution: invoking `audit-instructions` alone does not run `claude-memory:audit`, so a pair handed
to C6 and then forgotten produces no verdict from anyone. Naming the pair without grading it is
better than silence and still leaves the question open, which is not what a conflict report claims to
deliver.

**So the rule is on the verdict, not on the plugin: whoever holds a result owns the pair, and absent
a result the pass grades it.** When C6's verdict for that pair is in hand — because
`claude-memory:audit` ran and its output is available — the pass reports that verdict and attributes
it. When it is not, the pass **grades the pair itself** and labels the finding as C6's to own on any
subsequent remediation. Reuse-or-replace forbids re-implementing a shipped check; it does not require
withholding a verdict nobody else produced. That keeps the coverage claim true under every
combination of installed plugins and invocations, which neither a bare route nor a bare mention
does.

`audit-instructions` already presence-gates a route to the same plugin — the I1–I5 hygiene checks at
`SKILL.md:42-52` — so the *gate* is an existing shape rather than a new one. The *fallback* is
deliberately different: there the skill emits a one-line pointer and still declines to run the check,
because I1–I5 is a hygiene layer it disclaims owning. Here the pair sits inside the conflict
observable this pass does own, so declining would leave the finding with no owner at all.
**Reuse-or-replace forbids duplicating a check whose result is in hand; it does not license a hole
when nobody produced one.**

### 3. L2 lands as a new phase in `claude-config:audit-instructions` (Option A)

Three structural placements were live, and this ADR rules on them rather than leaving the call open:

- **Option A — a new phase in `audit-instructions`.** Reuses Phase A's surface enumeration
  (`SKILL.md:71-88`) and keeps one report. Cost: it changes a shipped skill's phase model, since
  Phase B's per-surface fan-out (`SKILL.md:92`) is structurally blind to a pair, so the comparison
  runs after those lanes and reads across them; and it widens the skill's advertised scope beyond the
  per-surface content audit its `description` (`:3`) and ownership line (`:33`) describe.
- **Option B — a new sibling skill in `claude-config`.** Leaves `audit-instructions`' phase model and
  advertised scope intact. Cost: it re-derives the surface list unless that enumeration is first
  extracted, and it adds a fifth skill to a listing budget already under pressure.
- **Option C — extend C6 in `claude-memory:audit`.** Reuses the only shipped contradiction check.

**Option A is chosen.** The deciding datum is that **Option C does not satisfy D-3 for any
non-memory surface**: `claude-memory`'s own scope table routes settings, hooks, MCP, agents and
skills to `claude-config` (`plugins/claude-memory/skills/audit/SKILL.md:34`), so applying C to skill
bodies, agent definitions, hook text, READMEs or output styles would place the check in a plugin that
explicitly disclaims the surface. **Option C is therefore not an independently valid whole-scope
choice and must not be presented as one** — it is live only as a *memory-slice* placement, and taking
it for L2's whole scope means splitting the placement in two. Between A and B, A wins on the listing
budget and on keeping one report; B's advantage — leaving the advertised scope untouched — is the
smaller cost, because a conflict finding is an instruction-audit finding by construction.

**Option A carries a precondition that is part of its cost, not a free inheritance.** Phase A
enumerates two roots only — user `${CLAUDE_CONFIG_DIR:-~/.claude}` and project `.claude/**`
(`SKILL.md:76-82`) — so it never reaches the marketplace tree. The **181** shipped
`plugins/*/skills/*/SKILL.md` files and the plugin READMEs L2's comparison needs are tracked source
here, distinct from the installed plugin-cache content `:85-88` excludes, yet no enumerated surface
names them. **Option A must first extend Phase A with a plugin-source surface covering every
plugin-owned instruction type Phase A already recognizes under the user and project roots** — the
same surface kinds, rooted at `plugins/` instead. Concretely, as enumerated in this tree:

| Plugin-source surface | Count | Glob |
|---|---|---|
| Skill bodies | 181 | `plugins/*/skills/*/SKILL.md` |
| Skill supporting files | 409 | every `*.md` under a skill directory except `SKILL.md`, **recursively**, minus `vendor/` |
| Plugin READMEs | 60 | `plugins/*/README.md` |
| Agent definitions | 7 | `plugins/*/agents/*.md` |

The supporting-file row is not padding: the existing `skills` scope is defined as "skill bodies **and
their context/reference files**" (`SKILL.md:65`), those files carry instructions their parent skill
loads, and there are more than twice as many of them as there are skill bodies. Enumerating
entrypoints alone would put the majority of plugin-owned instruction text outside the pass.

**That row is stated as a rule rather than a two-directory glob, because a bounded glob misses real
files.** `plugins/knowledge/skills/course-digest/reference/adapters/` holds three adapter documents
linked directly from that skill's `SKILL.md`, one level below `reference/`; a `reference/*.md`
pattern does not see them. Discovery is recursive under each skill directory, and it excludes
`vendor/` for the same reason the skill count does — those are upstream copies this repository never
hand-edits.

The rule is stated by surface kind rather than by that list, because the list goes stale: Phase A's
existing entries reach `rules/`, `skills/`, `agents/` and `output-styles/` under the user and project
roots, and any plugin-owned instruction type this repository later ships joins the plugin-source
surface on the same basis. **Enumerating only skills would break two comparisons the decision above
puts in scope** — a skill's stated default against its plugin README (the drift check), and agent
definitions against the memory layer (the conflict check), whose seven files live under
`plugins/plugin-quality/agents/` and `plugins/review/agents/` and are reachable from neither existing
Phase A root. The skill half is the **181** direct matches, not the 187 recursive ones, which would
pull upstream `vendor/` materializations into a remediation set this repository does not own.

**A narrowed scope filters what is reported, never what is read.** `audit-instructions` takes an
explicit scope argument that narrows Phase A's inventory (`SKILL.md:61-69`), and a pairwise
observable is undefined on one side — under `skills`, the `CLAUDE.md` half of every cross-layer pair
would simply be absent, and the pass would report nothing while appearing to have run. So the
comparison phase **enumerates counterpart surfaces regardless of scope, read-only, and applies the
scope to the finding instead**: a pair is reported when at least one of its anchors is in scope. That
keeps a scoped invocation honest without turning the conflict pass into an `all`-only feature.

Note what Option A does *not* buy: Phase A enumerates surface *paths*, not their contents — the reads
happen inside the Phase B lanes (`SKILL.md:90-108`). Sharing Phase A saves the enumeration, not the
reading.

### 4. L3 folds into the incumbent catalog rather than building a new one

`plugins/claude-config/skills/audit-instructions/reference/criteria.md` is already an evidence-tiered
criteria catalog, versioned `1.0.0` (`:1-4`), carrying **exactly the axes D-2 requires** (`:16-23`):
evidence tier (`mechanical` / `behavioral`), authority (`ANTHROPIC-DOCS` / `TALK` / `OPINION`), and
severity (`error` / `warning` / `info`). It ships eleven seeded checks I1–I11 (`:46-160`), a
per-surface applicability partition (`:25-30`), a Sources block of six official URLs (`:32-42`), and
explicit recheck triggers (`:11-14`). Its consuming skill is report-only with no `--fix`
(`SKILL.md:25-29`), which satisfies D-2's "report-only, never auto-applied" at the contract level.

**L3 extends this catalog with I12+ rows** — a `reference/criteria.md` edit plus a `CHANGELOG.md`
entry and a version bump. Not a new catalog, not a new skill, not a new plugin.

**D-2's claims map onto the existing `OPINION` tag** rather than adding a fourth authority value,
with "disabled by default" expressed as a severity ceiling of `info` plus an explicit default-off
marker, so the authority axis stays a three-value closed set.

**The mapping is a provenance judgment, not a synonym for "unbacked", and it must not be read as
one.** `OPINION` means *a practitioner's stated practice*, and that is precisely what D-2's claims
are: they come from a named, dated, linkable article, so the tag reports their provenance accurately
and the row carries that source like every other row. Authority is an evidence axis — a default-off
marker and an `info` ceiling describe enablement and impact, and neither can stand in for it.

**A criterion with no identifiable source at all therefore gets no tag, because it does not enter the
catalog.** Every row owes "one decisive source line" (`reference/criteria.md:6-9`); a candidate that
cannot name one fails that contract rather than being labelled `OPINION` to get past it. That is what
keeps the three-value axis honest: it stays closed because nothing sourceless is admitted, not
because the sourceless case was folded into a value that misdescribes it.

**The fold still widens the consumer's advertised handling.** The skill publishes that it *"cites
each finding to current official prompting doctrine"* (`SKILL.md:15-16`) and the catalog repeats the
guarantee for itself. A row cited to a practitioner article rather than to official doctrine is
inside the catalog's authority model and outside that sentence, so the sentence changes alongside the
catalog edit.

### 5. Deterministic findings follow #445's lane shape; report-only is a ceiling, not a gate

`claude-config` and `claude-memory` are model-invoked, report-only skills — `audit-instructions`
states *"There is no `--fix`"* (`SKILL.md:25-29`) and `claude-memory:audit` gates its `fix` action
behind a prior audit and approval (`SKILL.md:50-55`). **A finding that lands in either plugin is a
report, never an enforced gate**, and nothing in this repository blocks a merge on it.

Anything that must actually fail CI follows the lane shape documented on
[#445](https://github.com/melodic-software/claude-code-plugins/issues/445) — `scripts/check-*.sh` +
`.test.sh` + a `ci.yml` lane wired into the `ci-status` needs graph. The split is
deterministic-versus-judgment and applies **per criterion**, not per lane: either lane may produce
findings on both sides of it. #445 is a close-out backlog of eight enumerated checks from the #313
fleet audit, so what it supplies is the **shape** to copy; whether a new check belongs on that ticket
or on a new one following the same shape is not something #445 settles.

### 6. The instruction plane is durable pre-session instruction text, not committed files

This effort operates on the **instruction surface**: the durable text that shapes model behavior
before any session starts — `CLAUDE.md` (root and nested), `CLAUDE.local.md`, `.claude/rules/` and
`~/.claude/rules/`, skill bodies and their frontmatter, agent definitions, prompt-type hook text,
output styles. **Plugin READMEs sit just outside that line and inside the pass's population anyway**:
they are never loaded, so they can shape no behavior directly, but a README that disagrees with the
skill it documents is exactly the drift the separate check exists for. They are read as comparison
surfaces, never graded as resident instructions — which is why decision 3 mandates inventorying all
60 of them. **The boundary is durability and pre-session residency, not git status.** Several
in-scope surfaces are deliberately machine- or user-local and are never committed — user-global
rules and `CLAUDE.local.md` among them — and defining the plane by commit status would push exactly
the local-versus-project contradictions L2 exists to find outside its own boundary.

Issues #496 and #551 operate at **runtime** — the context economy of a session already in flight.
Issue #496 governs what a subagent returns into an orchestrator's context; #551 is the finding that
`/loop` re-invokes in the same session, so "restart at ~50% context" is an admonition with no
enforcement mechanism. Their unit of work is a live context window; their remediation is a mechanism.
Trimming an instruction surface does not reset a loop's context, and a payload contract does not
shorten a `CLAUDE.md`. **Neither L2 nor L3 may claim work on the runtime plane, and neither of those
two issues is a blocker, a dependency, or a fold target.**

One asymmetry is worth keeping: #551's observation — that an admonition without a mechanism is not
enforcement — is *methodologically* relevant here, because a criteria catalog is itself an admonition
surface. It argues for preferring a deterministic check wherever one is expressible. A shared lesson,
not a shared scope.

### 7. Collision assessment

Every ticket in the lane brief plus the sweep-shaped items found by search. "Overlaps" means the
ticket claims part of a lane's deliverable, not that it is adjacent. **This is a point-in-time
assessment**: the open-issue total moved materially during the drafting of the analysis behind it, so
re-run the sweep rather than treating the row set as complete.

| Ticket | Overlaps L2 / L3 | Reason |
|---|---|---|
| **#1225** sub-agent conventions + all-plugin audit | No / No — **coordinate** | Orthogonal observable over a largely shared file population; a scheduling overlap, not a claim |
| **#253** docs-hygiene proactive repo-scan | No / No | Its three shapes are intra-document drift against a source of truth outside the document; L2 needs a *pair* of surfaces, and `docs-hygiene` routes content-versus-capability away (`audit-instructions/SKILL.md:37`) |
| **#1245** `code-tidying:self-document` | No / **Partial — coordinate** | Moves comment criteria out of the user-global `CLAUDE.md` into `melodic-software/standards`. Not a claim on the catalog, but **a writer on the same file** — L3 must not assume that content is present |
| **#1219** standing hygiene-sweep routine | No / No — **and it is the consumer** | A scheduler/composer of existing hygiene skills that never mutates the repo. It owns no detection surface, so it competes with nothing and is the natural downstream consumer of whatever L2/L3 ship. **A new router would break it** |
| **#445** CI-gate backlog | No / No — **its lane shape is the fold target if deterministic** | See decision 5 |
| **#304** fresh-eyes checkpoint audit program | No / No | Tags skill *actions* for same-context bias; the observable is a single-file property. Its conformance mechanism is check 21, claimed by PR #1096 |
| **#289** wave-2 standards grounding rollout | No / No | **Opposing pressure, flagged not blocking.** Adds instruction surface while this effort trims; no shared file or mechanism — the tension is directional and belongs to the operator |
| **#1227** cheat sheet + README split | No / No | Docs IA auto-derived from skill frontmatter; reads `description` as data to render |
| **#406** TDD-by-default when consumer `CLAUDE.md` is silent | No / No | A single-surface default with its own seam decision, not a contradiction between two surfaces |
| **#1258** fork subagents do not inherit conversation | No / No | A dependency, not a scope claim — and the incumbent already dodges it: `audit-instructions` Phase C specifies fresh-context, non-fork subagents and says why (`SKILL.md:112-114`) |
| **#307** backlog-conformance sweep | No / No | Sweeps *tracker items* — a tracker-API population, not an instruction surface |
| **#988** fleet conformance: setup skills | No / No | Setup-skill presence against the philosophy's setup contract; a per-plugin structural property |
| **#1224** auto-mode-migration audit | No / No | Permission blocks — the permission plane, owned by `claude-config:audit-permission-grants` |
| **#912** guardrails + source-control hardening audit | No / No | Hook bypass gaps and convention-enforcement SSOT |
| **#1271** skill metadata / listing budget | No / No | Already folded per D-7 — corroborating evidence goes onto the existing ticket |
| **#496**, **#551** runtime context economy | No / No | Runtime plane — see decision 6 |
| **#1268** false `context: fork` rationale | No / No — **title-filter false positive** | Matched only on the literal `audit` inside the path `docs/topics/plugin-audit-port/`. It corrects one rationale inside another topic's design record, explicitly says "Do not change the decision", and has since closed. Recorded so a reader can see it was assessed rather than silently dropped |

Per D-8, anything touching `plugins/skill-quality/scripts/check-skill.sh` or
`docs/PLUGIN-PHILOSOPHY.md` sequences behind PR #1096, which claims **check 21**. The next free check
number is **22**. Neither L2 nor L3 needs a `check-skill.sh` slot — L2 lands in `claude-config`, L3 is
a catalog edit — so #1096 is a constraint to respect, not a blocker either lane waits on.

### 8. One recommendation handed to #1225's owner, not a ruling by this effort

Part 1 of #1225 defines an existence qualifier, and that qualifier has a partial incumbent.
`claude-config:audit-automation-gaps` already treats subagents as an audited automation category
(`SKILL.md:3`, `:43`) and already asks the existence question — *"Would a subagent provide value over
a hook or skill? Does context isolation actually help? Is there a plugin that already provides
this?"* (`context/gap-analysis.md:21-25`). That qualifier should be reconciled against this incumbent
before it is written fresh. Surfaced for #1225's owner; outside this effort's scope to decide.

## Consequences

**A shared file population no longer implies a collision.** Reconciliation is now argued on
observables, which means a future sweep-shaped ticket is reconciled by stating its question rather
than by counting the files it touches. The corresponding burden is that the argument has to be made
each time — the population test was cheap and wrong.

**L2 ships smaller than D-4 implied and lands inside a shipped skill's phase model.** Option A widens
`audit-instructions`' advertised scope and obliges it to extend Phase A with a plugin-source surface
before the comparison has its primary input. In exchange there is one report, one listing entry, and
no new router — which is what D-3 asks and what #1219 composes.

**The C6 boundary is a coverage predicate, not a layer predicate, and that is load-bearing.** Any
implementation that routes on "is this contradiction inside the memory layer" instead of "is this
pair operationally covered by C6" reintroduces a silent gap over the same-layer pairs C6 never
reaches. This is the single most likely way to get the reuse right and the behavior wrong.

**An incumbent search that stops at what skills advertise will miss what their catalogs check.**
Three independent searches reproduced the same false negative on C6 because they were scoped to
`SKILL.md` bodies or frontmatter `description` lines. Of the 199 `description:` lines under
`plugins/`, exactly three contain the words *conflict* or *contradict* and all three are unrelated
senses — git merge-conflict resolution, glossary curation, and a planning setup check. **None
advertises instruction-contradiction detection, `claude-memory:audit`'s own least of all**, which
sells an audit of the memory layer *"against a codified checklist derived from official Claude Code
documentation"* and never mentions contradiction. Future D-1 searches read `reference/`
catalogs at all depths, and this ADR treats a `SKILL.md`-scoped negative result as unproven rather
than as evidence.

**Findings that must fail CI have a home, and it is not these plugins.** Routing them to #445's lane
shape keeps the report-only ceiling honest, at the cost of splitting a single lane's output across
two delivery mechanisms decided per criterion.

## Method

**This record does assert Claude Code harness behavior, so D-16's fresh-docs mandate binds it.** The
residency rules the decisions rest on were verified against
<https://code.claude.com/docs/en/skills>, fetched 2026-07-25:

- **Skill descriptions are resident; bodies are not.** Verbatim: *"In a regular session, skill
  descriptions are loaded into context so Claude knows what's available, but full skill content only
  loads when invoked."* This is what makes `description`-versus-body a co-residency pair.
- **Supporting files load on demand.** Verbatim: skill directories let *"Claude access detailed
  reference material only when needed"*, referenced from `SKILL.md` *"so Claude knows what each file
  contains and when to load it"*. Conditional co-residency, not guaranteed.
- **The listing budget and its drop order.** Verbatim: *"The budget scales at 1% of the model's
  context window. When the listing overflows, Claude Code drops descriptions starting with the skills
  you invoke least"* — which is why a `description` is conditionally rather than guaranteed resident,
  and why the pass must not assume a description it can read on disk is in context.
- **Plugin READMEs.** The page enumerates what loads — the `CLAUDE.md` family, rules, skill
  descriptions, skill bodies on invocation, supporting files on demand — and a plugin README appears
  in none of it. **That is an enumeration argument, not a documented statement**, and it is recorded
  as such: no page says a README is never loaded. It is the basis for treating README divergence as
  drift rather than conflict, and if a future page documents README loading, that classification is
  what changes.

Non-residency claims are sourced the same way: issue #1225 and every ticket in the assessment were
read first-hand via `gh issue view`, PR #1096 via `gh pr diff`, and population counts were produced
by enumerating `plugins/*`, the globs in the table above, and `.claude-plugin/marketplace.json`. The
incumbent search covered skill bodies, frontmatter `description` lines **and** the `reference/`
catalogs inside skill directories — the last being where C6 was eventually found. The sweep-shape
search filtered the open-issue list by title for audit/sweep/scan/all-plugin/conformance/catalog/
criteria/conflict shapes; that list moves week to week and is deliberately not stated as a figure.
Counts and `path:line` citations were re-verified against the post-#1276 tree, since `main` landed a
plugin rename during the effort.
