# Sweep boundary — issue #1225 versus this effort's two deliverables

Decision **D-11** requires reconciling with issue #1225 before anything sweep-shaped is built, on the
stated grounds that *two repo-wide sweeps become two routers*. Decision **D-3** forbids a bulk sweep
of `plugins/**` and rules that findings land as checks in the plugin that already owns each surface —
**no new router**. This document is the reconciliation. It is the boundary the two sibling lanes
build against:

- **L2** — the cross-surface instruction-conflict detector (D-4).
- **L3** — the evidence-tiered criteria catalog (D-4, D-2).

Every claim below is cited to a file in this repository or to an issue/PR read first-hand. Counts
were produced by enumeration, not estimate. Both the counts and the `path:line` citations were
re-verified against this branch as of its latest correction — **not** against the revision the branch
forked from, since `main` has landed a plugin rename in the interim.

## What #1225 owns, in its own words

Issue #1225, *"Sub-agent conventions: codify from latest official docs, then audit all plugins"*
(open, `priority: medium` + `needs-human`). Its intent statement:

> We suspect custom sub-agent features are going unleveraged because we do not have a complete
> picture of what the platform offers — preloaded/auto-loaded skills, conversation forking, per-agent
> status line (semantics currently unclear to us), and likely unknown unknowns beyond those. This
> issue closes that gap in two sequenced parts: first research and codify sub-agent conventions from
> the latest official documentation, then audit every plugin in this repo against them.

Part 1's deliverable is three codified conventions:

> 1. **Existence qualifier** — a categorization for when a custom sub-agent earns its existence
>    versus delegating to general-purpose/built-in agents.
> 2. **Frontmatter surface** — the full YAML frontmatter surface for sub-agents and its usage
>    patterns (as pointers to the upstream reference, with our conventions layered on top).
> 3. **Rationale and best practices** — why/when guidance and a catalog of available features (again
>    by pointer), including the ones prompting this issue: preloaded/auto-load skills, conversation
>    forking, per-agent status line, and anything else discovered.

Part 2 is the audit, gated on Part 1:

> Then audit the full plugin inventory in this repo against them: every existing custom sub-agent
> (does it pass the existence qualifier? does it use the frontmatter surface correctly?) and every
> plugin that *lacks* sub-agents but would benefit under the new conventions.

Its own locked decisions bind the shape:

> - **One issue, two parts; Part 2 is gated on Part 1.**
> - **Conventions home:** the existing plugin-authoring conventions surface in this repo — extend it,
>   do not stand up a parallel surface (reuse-or-replace). Verify the actual current location at
>   execution time.

## The discriminator: #1225's audit asks a different question over a partly shared population

The collision register classified #1225 as *"structurally a second repo-wide sweep."* Read
first-hand, that classification is too coarse in one specific way, and the correction is what makes
the boundary clean.

**Population.** #1225 Part 2 audits sub-agent definitions. Enumerated in this checkout:

| Surface | Count | Where |
|---|---|---|
| Plugins | 60 | `plugins/*` (matches the 60 entries in `.claude-plugin/marketplace.json`) |
| Agent definitions | 7 | `plugins/plugin-quality/agents/auditor.md`; `plugins/review/agents/` (6 files) |
| Plugins shipping any `agents/` directory | 2 | `plugin-quality`, `review` |
| `SKILL.md` files | 181 | `plugins/*/skills/*/SKILL.md` |

The skill count is decomposed here because it has been miscounted twice. The stated pattern
`plugins/*/skills/*/SKILL.md` — one file per skill directory — yields **181**. A recursive
`find plugins -name SKILL.md` yields **187**, and the difference is exactly **6** upstream `vendor/`
materializations nested inside skill directories (`context7/lookup/vendor/cli`,
`context7/lookup/vendor/find-docs`, `dometrain/sync/vendor`, `playbooks/boris/vendor`,
`playbooks/skill-authoring/vendor`, `playwright/playwright/vendor`), which are vendored upstream
copies rather than skills this repository ships. **181 is the skill population**; 187 counts the
vendored copies too.

L2 and L3 operate on instruction surfaces — 181 skill bodies plus `CLAUDE.md`, `.claude/rules/`,
prompt-type hook text, and output styles. #1225's *conforming* population is **7 files in 2 of 60
plugins**, but Part 2's second half — "every plugin that *lacks* sub-agents but would benefit under
the new conventions" — reaches **all 60**, and answering it means reading each plugin's skills and
instructions. **So the population is substantially shared, and the population is therefore not the
discriminator.** The question is. #1225 asks whether a plugin should have a sub-agent; L2 asks
whether two of a plugin's surfaces contradict each other; L3 asks whether a criterion is officially
backed and at what tier. D-11's stated concern is infrastructural — *two repo-wide sweeps become two
routers* (`:3-4`). Two passes reading the same files to answer orthogonal questions need no shared
traversal to stay correct, and D-3 forbids either of them from standing one up regardless. What the
shared population does create is ordinary scheduling overlap between #1225 Part 2 and L2/L3, which
belongs in the collision matrix as a coordination note rather than in a mechanism.

**Question.** #1225 asks *does this sub-agent earn its existence, and is its frontmatter
conformant*. L2 asks *do two instruction surfaces contradict each other*. L3 asks *is this criterion
backed by official documentation, and at what evidence tier*. These are three different observables.

**The one genuine intersection, and the line through it.** `claude-config:audit-instructions`
inventories agent definition markdown as one of its surfaces —
`plugins/claude-config/skills/audit-instructions/SKILL.md:78` (user scope) and `:82` (project
scope), with `agents` as a first-class scope argument at `:67`. So both efforts read
`agents/*.md`. They read them for orthogonal questions:

- `audit-instructions` reads an agent definition for **instruction content versus current model
  capability** — checks I6–I11 apply to all surfaces
  (`plugins/claude-config/skills/audit-instructions/reference/criteria.md:29-30`).
- **#1225 Part 2** reads the same file for **existence qualification and frontmatter conformance**.

Same files, orthogonal questions. That sentence is the reconciliation D-11 asked for. Neither effort
needs to wait on the other, and neither needs a router to reach those 7 files.

## Boundary ruling for L2 — the cross-surface instruction-conflict detector

**What L2 owns.** Detection of *inter-surface contradiction*: two instruction surfaces that both
claim authority over the same behavior and disagree — a repo `CLAUDE.md` rule contradicted by a skill
body, a user-global rule contradicted by a project rule, a skill's stated default contradicted by the
plugin's own README or its `description`. The observable is a **pair of surfaces plus a
contradiction**, never a property of one document read alone.

**Why it is not #1225.** #1225's audit reads one agent definition at a time against a conventions
doc. Its unit of judgment is a single file versus a fixed standard. L2's unit of judgment is a pair
of files versus each other; no conventions doc can supply it, because the contradiction is between
two things the repo itself asserts. Nothing in #1225's Part 1 deliverable list, its Part 2 scope, or
its locked decisions produces or consumes such a finding.

**Incumbent search (D-1): a partial incumbent exists.** An earlier revision of this document recorded
"no incumbent"; that was wrong, and the correction narrows L2 rather than dissolving it. D-4's premise
holds only for the **cross-layer** slice. Searched and read first-hand:

| Candidate | Coverage of L2's observable | Evidence |
|---|---|---|
| `claude-config:audit-instructions` | **None** — owns the cross-surface *inventory*, but judges per surface | Phase A inventories every surface (`SKILL.md:71-88`); Phase B then runs **one fresh read-only subagent per surface** (`SKILL.md:92`) — a per-surface lane is structurally blind to a contradiction spanning two surfaces |
| `claude-config:audit-automation-gaps` | **None** — reasons across mechanisms, but its observable is *coverage*, not *contradiction* | The enforcement-hierarchy walk (`SKILL.md:24-27`, Phase 2.1 at `:94`) and the "Already exists" gate (`SKILL.md:135`) look for a concern **already covered** elsewhere; redundancy, not disagreement |
| **`claude-memory:audit`** | **PARTIAL — it already detects contradiction inside the memory layer** | Check **C6 Consistency [FAIL]** asks *"Do any instructions contradict each other across CLAUDE.md, CLAUDE.local.md, and rules files?"* and grades contradiction FAIL, redundancy WARN (`plugins/claude-memory/skills/audit/reference/criteria.md:107-119`), grounded in the official-docs quote *"If two rules contradict each other, Claude may pick one arbitrarily"* (`reference/official-guidance.md:127-130`). It is wired live, not a stray reference: the audit workflow carries a dedicated **"Step 3: Cross-file consistency check (C6)"** whose first instruction is *"Compare CLAUDE.md sections against `.claude/rules/` for contradictions"* (`context/audit.md:61-67`), and the determinism contract places C6 in the judgment tier (`SKILL.md:59-63`) |
| `claude-config:audit` | **None** — config **files** correctness, not instruction prose | Self-described boundary at `SKILL.md:29-32` |
| `skill-quality:check` | **None** — per-skill-directory by construction | Usage is `bash check-skill.sh <skill-name>` (`plugins/skill-quality/scripts/check-skill.sh:12`); its twenty checks (`:28-54`) never read a second skill except check 3, which also inspects a *sibling* skill's listing text but still never compares two skill bodies |
| `docs-hygiene` (six skills) | **None** — intra-document or intra-repo duplication, not authority conflict | `extract-ssot` deduplicates repetition; `audit-encapsulation` detects citations into skill-private surfaces; neither models two surfaces disagreeing |

**What C6 covers, and what it leaves to L2.** C6's population is the memory layer only. The audit's
own discovery step globs `find . -maxdepth 1 -name "CLAUDE.md" -o -name "CLAUDE.local.md"` and
`find .claude/rules -name "*.md"` (`context/audit.md:12-21`) — both CWD-relative, so project-scoped —
plus this repository's own auto-memory directory, resolved by a bundled script and explicitly scoped
to the current repo. `~/.claude/rules/` appears nowhere in that discovery step; it is named only in
the reference material as background harness documentation
(`reference/official-guidance.md:140`). **That settles the question this document's own example
raised**: a *user-global* rule contradicted by a *project* rule falls **outside** C6, and is
therefore inside L2's novel scope. So is every cross-layer pair:

- repo `CLAUDE.md` contradicted by a **skill body** — uncovered.
- a skill's stated default contradicted by the plugin **README** or its own `description` — uncovered.
- agent definitions, prompt-type hook text, output styles — uncovered.

What C6 *does* cover is narrower than this document's original definition assumed, and the gap
matters because L2 would otherwise inherit it as a false negative. Its discovery step is
`find . -maxdepth 1` over `CLAUDE.md` / `CLAUDE.local.md`
(`plugins/claude-memory/skills/audit/context/audit.md:10-15`), so **nested `CLAUDE.md` files never
enter its population** — while `audit-instructions` Phase A walks the tree for them explicitly
(`plugins/claude-config/skills/audit-instructions/SKILL.md:79-82`). And its cross-file step compares
`CLAUDE.md` against `.claude/rules/` **for contradictions** but `CLAUDE.md` against `CLAUDE.local.md`
**only for redundancy** (`context/audit.md:61-67`); the per-file pass that precedes it cannot see a
disagreement between two files. So the only pair C6 operationally covers for contradiction is **root
project `CLAUDE.md` versus project `.claude/rules/`**. That is the slice L2 would land on top of.
Root-versus-nested `CLAUDE.md`, and `CLAUDE.md` versus `CLAUDE.local.md`, are uncovered and stay
inside L2's novel scope.

**Corrected ruling: partial incumbent; L2's novel scope is cross-layer contradiction.** Under this
repository's reuse-or-replace posture, L2 must reuse or explicitly extend C6 rather than
re-implement memory-layer contradiction detection — which is an open decision, recorded below.

**The search, re-run honestly.** An earlier revision claimed a repository-wide search for
contradiction/precedence detection over `plugins/**/*.md` returned no instruction-surface conflict
detector. That claim is withdrawn: it asserts a result the tree contradicts.
`grep -rn "contradict" --include="*.md" plugins/` returns **92 hits across 65 files**, and among them
are `plugins/claude-memory/skills/audit/reference/criteria.md:109,114,116,119` and
`reference/official-guidance.md:129` — the C6 check itself. Most of the remaining hits are unrelated
senses (merge conflicts, workshop facilitation, prosody, research-conflict handling in
`discovery:research`, settings-precedence resolution), but the negative result as originally stated
was false.

**The lesson, recorded because three independent searches reproduced the same false negative.** A
search scoped to `SKILL.md` bodies or to frontmatter `description` lines cannot find C6. Of the
**199** `description:` lines under `plugins/`, **zero** name contradiction or conflict detection —
including `claude-memory:audit`'s own, which sells "memory health … against a codified checklist" and
never mentions contradiction. C6 is a real shipped check that is invisible from the discovery
surface, reachable only by reading the skill's `reference/criteria.md` catalog. **An incumbent search
that stops at what skills advertise will miss what their catalogs actually check** — future D-1
searches on this effort must read reference catalogs, not just skill bodies and descriptions.

**Where it lands — and the one thing this document will not invent.** Per D-3 there is no new router.
The plugin that owns the cross-surface instruction *inventory* is **`claude-config`**
(`plugins/claude-config/skills/audit-instructions/SKILL.md:3`, `:71-88`); the plugin that owns the
only **shipped contradiction check** is `claude-memory`. Those are different plugins, so the option
set is three-way, not two-way, and this document does not narrow it. What L2 lands *as* is not
settled by the evidence, because all three options are structural:

- **Option A — a new phase in `audit-instructions`.** Reuses the Phase A surface enumeration
  (`SKILL.md:71-88`) and keeps one report. Cost: it changes a shipped skill's phase model. Phase B's
  per-surface fan-out (`SKILL.md:92`) cannot host a pairwise comparison, so this adds a phase that
  runs after the lanes and reads across them — and it widens the skill's advertised scope, since the
  `description` (`SKILL.md:3`) and the stated ownership line (`:33`, "instruction **content vs
  current model capability**") describe a per-surface content audit, not a conflict detector.
  **A second cost, load-bearing in this repository:** Phase A enumerates two roots only — user
  `${CLAUDE_CONFIG_DIR:-~/.claude}` and project `.claude/**` (`SKILL.md:76-82`) — so it never reaches
  the marketplace tree. The 181 `plugins/*/skills/*/SKILL.md` files counted above and the plugin
  READMEs that L2's comparison needs are tracked source here rather than the installed plugin-cache
  content `:85-88` excludes, yet no enumerated surface names them. Reusing Phase A unchanged would silently omit L2's
  primary input, so A must first extend Phase A with a plugin-source surface — part of A's cost, not
  a free inheritance.
- **Option B — a new sibling skill in `claude-config`.** Leaves `audit-instructions`' phase model and
  advertised scope intact, and keeps its report-only contract (`SKILL.md:25-29`) untouched. Cost: it
  re-derives the surface list unless that enumeration is first extracted to a surface both skills
  read, and it adds a fifth skill to the plugin's listing budget.
- **Option C — extend C6 in `claude-memory:audit`.** The contradiction check already exists there, so
  this reuses rather than parallels it, and D-3's own logic — findings land as checks in the plugin
  that already owns each surface — points at it for the memory-layer slice, since `claude-memory`
  owns both the surface and the check. Cost: C6's population is project memory files
  (`context/audit.md:12-21`), so covering skill bodies, READMEs, agent definitions, hook text and
  output styles means widening `claude-memory`'s declared scope into surfaces its own scope table
  routes to `claude-config` (`SKILL.md:34`) — pushing against that plugin's stated boundary in the
  same way Option A pushes against `audit-instructions`'.

Note what Option A does **not** buy: Phase A enumerates surface *paths*, not their contents — the
content reads happen inside the Phase B lanes (`SKILL.md:90-108`). So sharing Phase A saves the
enumeration, not the reading. No option has a decisive cost advantage on that axis.

**This is an OPEN DECISION for the operator, recorded rather than resolved, and deliberately without
a recommendation.** None of the three is a router — each lands a check inside a plugin that already
owns *some* surface in scope, which is what D-3 asks. They do not satisfy it equally, though:
**Option C does not satisfy D-3 for the non-memory surfaces at all.** `claude-memory`'s own scope
table routes settings, hooks, MCP, agents and skills to `claude-config` (`SKILL.md:34`), so applying
C to skill bodies, agent definitions, hook text, READMEs or output styles would place the check in a
plugin that does not own the surface. C is live as a **memory-layer placement**; taking it for L2's
whole scope means either splitting the placement in two or rejecting C. The choice turns on which
shipped skill's advertised scope should widen — a judgment about shipped skills' identities rather
than something the evidence settles. L2 must not pick this unilaterally.

**What L2 must not do regardless of the choice:** re-implement the slice C6 operationally covers —
root project `CLAUDE.md` versus project `.claude/rules/` contradiction. Whichever option is picked,
that slice is reused or extended, never duplicated. The pairs C6 does *not* reach — nested
`CLAUDE.md`, and `CLAUDE.md` versus `CLAUDE.local.md` contradiction — are L2's to build or to add to
C6 as an explicit extension; either way they must not be assumed already covered.

**A ceiling both lanes inherit.** `claude-config` and `claude-memory` are model-invoked, report-only
skills — `audit-instructions` states "There is no `--fix`" (`SKILL.md:25-29`) and `claude-memory:audit`
gates its `fix` action behind a prior audit and approval (`SKILL.md:50-55`). A finding that lands in
either plugin is therefore a **report**, never an enforced gate. Nothing in this repository blocks a
merge on it. Anything that must actually *fail CI* has a different home — #445's documented
`scripts/check-*.sh` + `.test.sh` + `ci.yml` lane shape — and that split is deterministic-versus-
judgment, not L2-versus-L3: each lane may produce findings on both sides of it. L2 and L3 should
decide per criterion which side a finding falls on, and route the deterministic ones into that lane
shape rather than assuming a report-only skill will enforce them.

**Verdict: L2 is cleared to build its novel scope — cross-layer contradiction — and blocked on the
Option A/B/C placement call above.** Its home is not settled: `claude-config` owns the surface
inventory, `claude-memory` owns the only shipped contradiction check, and this document does not
choose between them. No *issue* claims this surface — not #1225, not #253, nor any other open item —
but a shipped skill partly does, which is why the placement decision must be made before L2 writes
detection logic.

## Boundary ruling for L3 — the evidence-tiered criteria catalog

**L3 must fold, not build.** This is the D-1 outcome the effort's own digests kept reaching, and it
reaches it again here in the strongest form yet.

**The incumbent is a complete match.**
`plugins/claude-config/skills/audit-instructions/reference/criteria.md` is an
evidence-tiered criteria catalog, versioned `1.0.0` (`:1-4`), carrying **exactly the axes D-2
requires** (`:16-23`):

- **Evidence tier** — `mechanical` or `behavioral`, where behavioral findings "ship as proposals
  verified by the delete-and-watch loop, never confident removals" (`:18-20`).
- **Authority** — `ANTHROPIC-DOCS` / `TALK` / `OPINION`, with the note "All eleven seeds are
  `ANTHROPIC-DOCS`" (`:21-22`).
- **Severity** — `error` / `warning` / `info` (`:23`).

It already carries eleven seeded checks I1–I11 (`:46-160`), a per-surface applicability partition
(`:25-30`), a Sources block of six official URLs (`:32-42`), and explicit **recheck triggers** for
staleness (`:11-14`). Its consuming skill is report-only with no `--fix`
(`plugins/claude-config/skills/audit-instructions/SKILL.md:25-29`), which is D-2's "report-only,
never auto-applied" requirement already satisfied at the contract level.

**Consequence for L3.** L3 does not stand up a catalog. It **extends this one with I12+ rows** — a
`reference/criteria.md` edit plus a `CHANGELOG.md` entry and a `version` bump, not new machinery.
**One caveat, and it binds the open decision below:** a catalog-only edit does not suffice for a row
carrying no official backing. The consuming skill publishes that it "cites each finding to current
official prompting doctrine" (`SKILL.md:15-16`), and the catalog repeats it for itself — checks
"seeded from current official prompting doctrine", each carrying "one decisive source line"
(`reference/criteria.md:6-9`). A row whose premise is that no such line exists would put the skill's
output at odds with what its users were promised, so the fold must widen the consumer's advertised
scope as well as the catalog.

**Why it is not #1225.** #1225's Part 1 codifies conventions for *sub-agent authoring* (existence
qualifier, frontmatter surface, feature catalog) into the plugin-authoring conventions surface. L3's
catalog governs *instruction content across every surface*, and its home already exists inside a
plugin. Different artifact, different home, different consuming mechanism. The two touch only where
`audit-instructions` reads `agents/*.md` for content — the orthogonal-questions line stated above.

**Why it is not #253.** #253 proposes proactive `docs-hygiene` repo-scan detection for three shapes:
external-copy blocks, capability enumerations, and internal-name coupling. All three are
**intra-document drift against a source of truth outside the document** — a copied upstream fact, a
closed list that will go stale, a citation targeting an internal name. L3's criteria judge
**instruction content against current model capability**, which is the axis
`audit-instructions` already declares it owns (`SKILL.md:31-50`), and which `docs-hygiene` explicitly
routes away from — `audit-instructions` names `docs-hygiene:compress` as the token-brevity owner and
disclaims that role for itself (`SKILL.md:37`, `:161-162`). Different observable, different plugin,
no overlap.

**One unresolved mapping.** D-2 requires `UNBACKED` claims to ship marked and disabled by default
with a severity ceiling. The incumbent catalog has no `UNBACKED` authority value; its closest
existing tag is `OPINION` ("a practitioner's stated practice", `:21-22`), which fits the source
article's nature. Whether L3 adds `UNBACKED` as a fourth authority value or maps onto `OPINION` is a
catalog-contract choice this document does not have the evidence to settle — the tag's intended
semantics are not documented beyond that one-line gloss. **OPEN DECISION for the operator.**
Recommendation: map onto `OPINION` and express "disabled by default" as the severity ceiling
(`info`) plus an explicit default-off marker, so the authority axis stays a three-value closed set.
**Either branch carries the contract cost recorded above** — the citation guarantee at `SKILL.md:15-16`
is unconditional and no shipped row exercises `OPINION` today, so whichever mapping is chosen, the
skill's advertised handling of non-official criteria is part of the same change.

**Verdict: L3 must fold.** It is cleared to proceed as an extension of
`plugins/claude-config/skills/audit-instructions/reference/criteria.md`, not as a new catalog, and it
must resolve the `UNBACKED` mapping first.

## Runtime versus instruction-surface — the #496 / #551 boundary

The collision register's ruling is to *state the boundary rather than conflating them*. Stated
plainly:

**This effort operates on the instruction surface** — the durable text a repository or user writes
that shapes model behavior before any session starts: `CLAUDE.md`, `.claude/rules/`, skill bodies and
their frontmatter, agent definitions, prompt-type hook text, output styles. Its unit of work is a
committed file. Its remediation is an edit to that file. Its failure mode is accreted text that
costs context and constrains a capable model.

**#496 and #551 operate at runtime** — the context economy of a session already in flight. #496
governs what a subagent *returns into an orchestrator's context* ("every subagent brief specifies
exactly what comes back — identifiers + verdict + parked-payload only") and where detail lives
instead ("Detail lives on GitHub, never in orchestrator context"). #551 is the finding that `/loop`
"re-invokes in the SAME session via ScheduleWakeup," so the "restart at ~50% context" rule "is a
prompt admonition with no enforcement mechanism." Their unit of work is a live context window. Their
remediation is a mechanism — a payload contract, a fresh-session relaunch. Their failure mode is
monotonic context growth within one session.

The two planes share the vocabulary "context engineering" and share nothing else. Trimming an
instruction surface does not reset a loop's context; a payload contract does not shorten a
`CLAUDE.md`. **Neither L2 nor L3 may claim work on the runtime plane, and neither #496 nor #551 is a
blocker, a dependency, or a fold target for this effort.**

One asymmetry is worth recording: #551's core observation — that an admonition without a mechanism is
not enforcement — is *methodologically* relevant to L2 and L3, because a criteria catalog is itself
an admonition surface. It argues for preferring a deterministic check where one is expressible. That
is a shared lesson, not a shared scope.

## Collision matrix

Every ticket named in the lane brief, plus the sweep-shaped items found by search. "Overlaps"
means the ticket claims part of the lane's deliverable, not merely that it is adjacent.

| Ticket | Overlaps L2 | Overlaps L3 | Reason |
|---|---|---|---|
| **#1225** sub-agent conventions + all-plugin audit | No | No — **but coordinate** | Conforming population is 7 agent definitions in 2 of 60 plugins; Part 2's "would this plugin benefit from one" half reaches all 60 and reads their skills and instructions, so the file population is largely shared with L2/L3. The question is not: existence-qualification + frontmatter conformance, versus L2's inter-surface contradiction and L3's content-versus-model-capability. Orthogonal observables over shared files need no shared traversal (D-11's concern is routers, `:3-4`), so this is a scheduling overlap to sequence, not a claim on either deliverable |
| **#253** docs-hygiene proactive repo-scan | No | No | Its three shapes are intra-document drift against an external or internal source of truth. L2 needs a *pair* of surfaces; L3 judges content against model capability, an axis `docs-hygiene` routes away from (`audit-instructions/SKILL.md:37`) |
| **#1227** cheat sheet + README split | No | No | Docs IA, auto-derived from skill frontmatter. Reads `description` as data to render; neither judges its content nor compares surfaces |
| **#304** fresh-eyes checkpoint audit program | No | No | Tags skill *actions* for same-context bias. Its conformance mechanism is check 21, already claimed by PR #1096. Adjacent to L2 only in that both read many skills; the observable (self-judging step) is a single-file property |
| **#1245** `code-tidying:self-document` | No | **Partial — coordinate** | Moves comment criteria out of the user-global `CLAUDE.md` into `melodic-software/standards`. It removes instruction text that this effort's user-scope half also targets. Not a claim on L3's catalog, but a **writer on the same file**; L3 must not assume that content is present |
| **#289** wave-2 standards grounding rollout | No | No | **Opposing pressure, flagged not blocking per the lane brief.** It adds instruction surface to more plugins while this effort trims. No shared file, no shared mechanism; the tension is directional and belongs to the operator |
| **#496** orchestrator context economy | No | No | Runtime plane — subagent return payloads inside a live session |
| **#551** `/loop` does not reset context | No | No | Runtime plane — no mechanism triggers a `/clear` between cycles |
| **#406** TDD-by-default when consumer CLAUDE.md is silent | No | No | An instance of the over-constraint class with its own seam decision (a `userConfig` boolean). A single-surface default, not a contradiction between two surfaces. Its findings cite `plugins/implementation/skills/implement/SKILL.md:3`, `:67` |
| **#1219** standing hygiene-sweep routine | No | No — **and it is the consumer** | Found by search, not handed. A *scheduler/composer* of existing hygiene skills with a coverage-state abstraction; it explicitly names #253 as owning its copied-content scanner and states "the routine itself never mutates the repo." It owns no detection surface, so it competes with nothing — it is the natural downstream consumer of whatever L2/L3 ship as checks. **A new router would break it**; checks inside existing plugins are exactly what it composes |
| **#445** CI-gate backlog | No | No — **its lane shape is the fold target if deterministic** | Found by search. It documents the shape for an automatable conformance check in this repo: `scripts/check-*.sh` + `.test.sh` + a `ci.yml` lane wired into the `ci-status` needs graph. Any deterministic slice of L2 or L3 follows that **shape** rather than becoming a new gate. The ticket itself is a close-out backlog of eight enumerated checks from the #313 fleet audit, and does not say whether unrelated new checks belong on it |
| **#1258** fork subagents do not inherit conversation | No | No | Dependency, not a scope claim. Recorded because the incumbent already dodged it: `audit-instructions` Phase C specifies **fresh-context, non-fork** subagents and states why (`SKILL.md:112-114`). Evidence the incumbent is current, not stale |
| **#1268** false `context: fork` rationale in the plugin-audit-port record | No | No — **title-filter false positive** | Surfaced by the title sweep only because the literal `audit` appears in the path `docs/topics/plugin-audit-port/`. It is not sweep-shaped at all: it corrects one false rationale at three sites inside another topic's design record and explicitly says "Do not change the decision." Touches no plugin instruction surface, claims no detection mechanism, and has since closed. Recorded so a reader can see it was assessed rather than silently dropped |
| **#307** backlog-conformance sweep | No | No | Found by search. Sweeps *tracker items* for missing labels/axes — a tracker-API population, not an instruction surface |
| **#988** fleet conformance: setup skills | No | No | Found by search. Setup-skill presence against the philosophy's setup contract; a per-plugin structural property |
| **#1224** auto-mode-migration audit | No | No | Found by search. Permission blocks — the permission plane, owned by `claude-config:audit-permission-grants` |
| **#912** guardrails + source-control hardening audit | No | No | Found by search. Hook bypass gaps and convention-enforcement SSOT; a guardrails/source-control concern |
| **#1271** skill metadata / listing budget | No | No | Already folded per D-7 — corroborating evidence goes onto the existing ticket, no second ticket |

**Beyond the handed list**, a title sweep over the open-issue list as it stood when this document was
written surfaced eight further
audit/sweep/scan/conformance-shaped items: #1219, #445, #307, #988, #1224, #912, #1268, #1258. The
open-issue total is a moving target — it changed materially between the drafting, review and
correction of this document — so that sweep is a point-in-time snapshot, not a reproducible
enumeration; re-run it rather than trusting the list to still be complete.

Of the eight, **#1268 is a false positive of the title filter** — it matched on the literal `audit`
inside the path `docs/topics/plugin-audit-port/`, not on sweep shape, and it has since closed. Of the
remainder only **#1219** and **#445** change anything for L2/L3, and both change it in the same
direction: they *depend on* findings landing as checks inside existing plugins, which is what D-3
already mandates.

## Fold, do not build

D-7 set the precedent with #1271. Two more items fold rather than becoming new work:

1. **L3's catalog folds into**
   `plugins/claude-config/skills/audit-instructions/reference/criteria.md` as rows I12+. Not a new
   catalog, not a new skill, not a new plugin.
2. **Any deterministic slice of L2 or L3 follows #445's documented lane shape** —
   `scripts/check-*.sh` + `.test.sh` + a `ci.yml` lane wired into the `ci-status` needs graph —
   rather than becoming a standalone gate. Note the limit of this ruling: #445 is a close-out backlog
   carrying eight specifically enumerated checks out of the #313 fleet audit, so what it documents is
   the **shape** to copy. Whether a new check belongs *on that ticket* or on a new ticket following
   the same shape is not something #445 settles, and this document does not settle it either.

A third item is a **recommendation to the owner of #1225, not a ruling by this effort**: #1225's
Part 1 existence qualifier has a partial incumbent. `claude-config:audit-automation-gaps` already
treats subagents as an audited automation category
(`plugins/claude-config/skills/audit-automation-gaps/SKILL.md:3`, `:43`) and already asks the
existence question — *"Would a subagent provide value over a hook or skill? Does context isolation
actually help? Is there a plugin that already provides this?"*
(`plugins/claude-config/skills/audit-automation-gaps/context/gap-analysis.md:21-25`). #1225's
existence qualifier should be reconciled against that incumbent before it is written fresh. This is
surfaced for #1225's owner; it is outside this effort's scope to decide.

## Sequencing note — PR #1096

Per D-8, anything touching `plugins/skill-quality/scripts/check-skill.sh` or
`docs/PLUGIN-PHILOSOPHY.md` sequences behind PR #1096, and this boundary is written against that
PR's **post-merge** shape. Read first-hand, #1096 (open, not draft, branch
`feat/fresh-eyes-delegation-doctrine-gate`) adds 149 lines to `check-skill.sh`, claiming **check 21 —
fresh-eyes declaration conformance**, plus 348 test lines, a new
`plugins/skill-quality/skills/check/reference/fresh-eyes-declarations.md`, +82/-4 in
`docs/PLUGIN-PHILOSOPHY.md` (a Convention-registry row and an expanded fresh-eyes section), and a
`plugin.json` version bump.

Consequence for the sibling lanes: **the next free check number is 22**, against a post-merge
`check-skill.sh` of roughly 890 lines (741 today). Neither L2 nor L3 currently needs a
`check-skill.sh` slot — L2 lands in `claude-config` and L3 is a catalog edit — so #1096 is a
constraint to respect, not a blocker either lane waits on.

## Open decisions for the operator

Recorded, not invented. Neither lane should resolve these on its own.

1. **L2's structural home** — a new phase in `audit-instructions` (Option A) versus a new sibling
   skill in `claude-config` (Option B) versus extending `claude-memory:audit`'s existing **C6
   Consistency** check (Option C). All three satisfy D-3. The datum that makes this three-way rather
   than two-way: the only **shipped** contradiction check in this repository lives in `claude-memory`,
   not `claude-config` — `claude-config` owns the surface *inventory*, `claude-memory` owns the
   *check*. Each option widens some shipped skill's advertised scope: A and B widen `claude-config`'s,
   C widens `claude-memory`'s beyond the memory files its own scope table declares.
   **No recommendation** — see the ruling above.
2. **L3's `UNBACKED` mapping** — a fourth authority value versus mapping onto the existing `OPINION`
   tag with a severity ceiling (recommended). The existing tag's intended semantics are documented
   only as a one-line gloss.
3. **#1225's existence qualifier versus `audit-automation-gaps`** — surfaced to #1225's owner above;
   not this effort's call.

## Method

Issue #1225 and every ticket in the matrix were read first-hand via `gh issue view`; PR #1096 via
`gh pr diff`. The sweep-shape search enumerated the open-issue list as it stood at the time and
filtered titles for audit/sweep/scan/all-plugin/conformance/catalog/criteria/conflict shapes; that
total moves week to week, so it is deliberately not stated as a figure. Population counts were
produced by enumerating `plugins/*`, `plugins/*/skills/*/SKILL.md`, `plugins/*/agents/*.md`, and
`.claude-plugin/marketplace.json`. The incumbent search covered skill bodies, frontmatter
`description` lines **and** the `reference/` catalogs inside skill directories — the last of those
being where the C6 incumbent was eventually found, after three searches restricted to the first two
returned a false negative. Repository doctrine was read from `docs/PLUGIN-PHILOSOPHY.md`,
`docs/conventions/topic-docs/README.md`, and the four plugin manifests named above.

No claim about Claude Code harness behavior is asserted in this document; per D-16 the fresh-docs
mandate binds changes touching a plugin manifest, marketplace schema, hook contract, or documented
harness behavior, and this is a prose-only boundary analysis that touches none of them.
