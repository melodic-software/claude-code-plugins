# Sweep boundary — issue #1225 versus this effort's two deliverables

Decision **D-11** requires reconciling with issue #1225 before anything sweep-shaped is built, on the
stated grounds that *two repo-wide sweeps become two routers*. Decision **D-3** forbids a bulk sweep
of `plugins/**` and rules that findings land as checks in the plugin that already owns each surface —
**no new router**. This document is the reconciliation. It is the boundary the two sibling lanes
build against:

- **L2** — the cross-surface instruction-conflict detector (D-4).
- **L3** — the evidence-tiered criteria catalog (D-4, D-2).

Every claim below is cited to a file in this repository at the revision this branch forked from, or
to an issue/PR read first-hand. Counts were produced by enumeration, not estimate.

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

## The discriminator: #1225's audit has a different population and a different question

The collision register classified #1225 as *"structurally a second repo-wide sweep."* Read
first-hand, that classification is too coarse in one specific way, and the correction is what makes
the boundary clean.

**Population.** #1225 Part 2 audits sub-agent definitions. Enumerated in this checkout:

| Surface | Count | Where |
|---|---|---|
| Plugins | 60 | `plugins/*` (matches the 60 entries in `.claude-plugin/marketplace.json`) |
| Agent definitions | 7 | `plugins/plugin-quality/agents/auditor.md`; `plugins/review/agents/` (6 files) |
| Plugins shipping any `agents/` directory | 2 | `plugin-quality`, `review` |
| `SKILL.md` files | 188 | `plugins/*/skills/*/SKILL.md` |

L2 and L3 operate on instruction surfaces — 188 skill bodies plus `CLAUDE.md`, `.claude/rules/`,
prompt-type hook text, and output styles. #1225's conforming population is **7 files in 2 of 60
plugins**, widening only to the "would this plugin benefit from one" question over the other 58.

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

**Incumbent search (D-1): no incumbent.** D-4's premise holds. Searched and read first-hand:

| Candidate | Why it does not cover L2 | Evidence |
|---|---|---|
| `claude-config:audit-instructions` | Owns the cross-surface *inventory*, but judges per surface | Phase A inventories every surface (`SKILL.md:71-88`); Phase B then runs **one fresh read-only subagent per surface** (`SKILL.md:92`) — a per-surface lane is structurally blind to a contradiction spanning two surfaces |
| `claude-config:audit-automation-gaps` | Reasons across mechanisms, but its observable is *coverage*, not *contradiction* | The enforcement-hierarchy walk (`SKILL.md:24-27`, Phase 2.1 at `:94`) and the "Already exists" gate (`SKILL.md:135`) look for a concern **already covered** elsewhere; redundancy, not disagreement |
| `claude-memory:audit` | Single-layer; explicitly routes content questions out | Scope table limits it to memory files (`SKILL.md:26-34`); content-fit questions route to `audit-instructions` (`SKILL.md:36-46`) |
| `claude-config:audit` | Config **files** correctness, not instruction prose | Self-described boundary at `SKILL.md:29-32` |
| `skill-quality:check` | Per-skill-directory by construction | Usage is `bash check-skill.sh <skill-name>` (`plugins/skill-quality/scripts/check-skill.sh:12`); its twenty checks (`:28-54`) never read a second skill except check 3's diff of the *same* skill against a base ref |
| `docs-hygiene` (six skills) | Intra-document or intra-repo duplication, not authority conflict | `extract-ssot` deduplicates repetition; `audit-encapsulation` detects citations into skill-private surfaces; neither models two surfaces disagreeing |

A repository-wide search for contradiction/precedence detection over `plugins/**/*.md` returned only
settings-precedence resolution (`disk-hygiene`, `claude-ops`, `guardrails`), research-conflict
handling (`discovery:research`), and domain modelling (`event-storming`). No hit is an
instruction-surface conflict detector.

**Where it lands — and the one thing this document will not invent.** Per D-3 there is no new
router, and the plugin that already owns the cross-surface instruction inventory is **`claude-config`**
(`plugins/claude-config/skills/audit-instructions/SKILL.md:3`, `:71-88`). L2 lands in `claude-config`.
What it lands *as* is not settled by the evidence, because both options are structural:

- **Option A — a new phase in `audit-instructions`.** Reuses the Phase A surface enumeration
  (`SKILL.md:71-88`) and keeps one report. Cost: it changes a shipped skill's phase model. Phase B's
  per-surface fan-out (`SKILL.md:92`) cannot host a pairwise comparison, so this adds a phase that
  runs after the lanes and reads across them — and it widens the skill's advertised scope, since the
  `description` (`SKILL.md:3`) and the stated ownership line (`:33`, "instruction **content vs
  current model capability**") describe a per-surface content audit, not a conflict detector.
- **Option B — a new sibling skill in `claude-config`.** Leaves `audit-instructions`' phase model and
  advertised scope intact, and keeps its report-only contract (`SKILL.md:25-29`) untouched. Cost: it
  re-derives the surface list unless that enumeration is first extracted to a surface both skills
  read, and it adds a fifth skill to the plugin's listing budget.

Note what Option A does **not** buy: Phase A enumerates surface *paths*, not their contents — the
content reads happen inside the Phase B lanes (`SKILL.md:90-108`). So sharing Phase A saves the
enumeration, not the reading. Neither option has a decisive cost advantage on that axis.

**This is an OPEN DECISION for the operator, recorded rather than resolved, and deliberately without
a recommendation.** Both options satisfy D-3 — a skill inside the plugin that already owns the
surface is not a router. The choice turns on whether `audit-instructions`' advertised scope should
widen to include conflict detection, which is a judgment about a shipped skill's identity rather than
something the evidence settles. L2 must not pick it unilaterally.

**A ceiling both lanes inherit.** `claude-config` and `claude-memory` are model-invoked, report-only
skills — `audit-instructions` states "There is no `--fix`" (`SKILL.md:25-29`) and `claude-memory:audit`
gates its `fix` action behind a prior audit and approval (`SKILL.md:50-55`). A finding that lands in
either plugin is therefore a **report**, never an enforced gate. Nothing in this repository blocks a
merge on it. Anything that must actually *fail CI* has a different home — #445's documented
`scripts/check-*.sh` + `.test.sh` + `ci.yml` lane shape — and that split is deterministic-versus-
judgment, not L2-versus-L3: each lane may produce findings on both sides of it. L2 and L3 should
decide per criterion which side a finding falls on, and route the deterministic ones to #445 rather
than assuming a report-only skill will enforce them.

**Verdict: L2 is cleared to build**, scoped to `claude-config`, blocked only on the
Option A/B call above. Nothing in #1225, #253, or any other open issue claims this surface.

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

**Consequence for L3.** L3 does not stand up a catalog. It **extends this one with I12+ rows**, and
the extension is a `reference/criteria.md` edit plus a `CHANGELOG.md` entry and a `version` bump —
not new machinery.

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
disclaims that role for itself (`SKILL.md:38`, `:161-162`). Different observable, different plugin,
no overlap.

**One unresolved mapping.** D-2 requires `UNBACKED` claims to ship marked and disabled by default
with a severity ceiling. The incumbent catalog has no `UNBACKED` authority value; its closest
existing tag is `OPINION` ("a practitioner's stated practice", `:21-22`), which fits the source
article's nature. Whether L3 adds `UNBACKED` as a fourth authority value or maps onto `OPINION` is a
catalog-contract choice this document does not have the evidence to settle — the tag's intended
semantics are not documented beyond that one-line gloss. **OPEN DECISION for the operator.**
Recommendation: map onto `OPINION` and express "disabled by default" as the severity ceiling
(`info`) plus an explicit default-off marker, so the authority axis stays a three-value closed set.

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
| **#1225** sub-agent conventions + all-plugin audit | No | No | Population is 7 agent definitions in 2 of 60 plugins; question is existence-qualification + frontmatter conformance. L2's observable is inter-surface contradiction; L3's is instruction content versus model capability. Sole intersection is `agents/*.md` read for orthogonal questions |
| **#253** docs-hygiene proactive repo-scan | No | No | Its three shapes are intra-document drift against an external or internal source of truth. L2 needs a *pair* of surfaces; L3 judges content against model capability, an axis `docs-hygiene` routes away from (`audit-instructions/SKILL.md:38`) |
| **#1227** cheat sheet + README split | No | No | Docs IA, auto-derived from skill frontmatter. Reads `description` as data to render; neither judges its content nor compares surfaces |
| **#304** fresh-eyes checkpoint audit program | No | No | Tags skill *actions* for same-context bias. Its conformance mechanism is check 21, already claimed by PR #1096. Adjacent to L2 only in that both read many skills; the observable (self-judging step) is a single-file property |
| **#1245** `code-tidying:self-document` | No | **Partial — coordinate** | Moves comment criteria out of the user-global `CLAUDE.md` into `melodic-software/standards`. It removes instruction text that this effort's user-scope half also targets. Not a claim on L3's catalog, but a **writer on the same file**; L3 must not assume that content is present |
| **#289** wave-2 standards grounding rollout | No | No | **Opposing pressure, flagged not blocking per the lane brief.** It adds instruction surface to more plugins while this effort trims. No shared file, no shared mechanism; the tension is directional and belongs to the operator |
| **#496** orchestrator context economy | No | No | Runtime plane — subagent return payloads inside a live session |
| **#551** `/loop` does not reset context | No | No | Runtime plane — no mechanism triggers a `/clear` between cycles |
| **#406** TDD-by-default when consumer CLAUDE.md is silent | No | No | An instance of the over-constraint class with its own seam decision (a `userConfig` boolean). A single-surface default, not a contradiction between two surfaces. Its findings cite `plugins/implementation/skills/implement/SKILL.md:3`, `:67` |
| **#1219** standing hygiene-sweep routine | No | No — **and it is the consumer** | Found by search, not handed. A *scheduler/composer* of existing hygiene skills with a coverage-state abstraction; it explicitly names #253 as owning its copied-content scanner and states "the routine itself never mutates the repo." It owns no detection surface, so it competes with nothing — it is the natural downstream consumer of whatever L2/L3 ship as checks. **A new router would break it**; checks inside existing plugins are exactly what it composes |
| **#445** CI-gate backlog | No | No — **fold target if deterministic** | Found by search. The documented shape for an automatable conformance check in this repo: `scripts/check-*.sh` + `.test.sh` + a `ci.yml` lane wired into the `ci-status` needs graph. Any deterministic slice of L2 or L3 folds here rather than becoming a new gate |
| **#1258** fork subagents do not inherit conversation | No | No | Dependency, not a scope claim. Recorded because the incumbent already dodged it: `audit-instructions` Phase C specifies **fresh-context, non-fork** subagents and states why (`SKILL.md:112-114`). Evidence the incumbent is current, not stale |
| **#307** backlog-conformance sweep | No | No | Found by search. Sweeps *tracker items* for missing labels/axes — a tracker-API population, not an instruction surface |
| **#988** fleet conformance: setup skills | No | No | Found by search. Setup-skill presence against the philosophy's setup contract; a per-plugin structural property |
| **#1224** auto-mode-migration audit | No | No | Found by search. Permission blocks — the permission plane, owned by `claude-config:audit-permission-grants` |
| **#912** guardrails + source-control hardening audit | No | No | Found by search. Hook bypass gaps and convention-enforcement SSOT; a guardrails/source-control concern |
| **#1271** skill metadata / listing budget | No | No | Already folded per D-7 — corroborating evidence goes onto the existing ticket, no second ticket |

**Beyond the handed list**, the title sweep over all 256 open issues surfaced eight further
audit/sweep/scan/conformance-shaped items: #1219, #445, #307, #988, #1224, #912, #1268, #1258. Of
these only **#1219** and **#445** change anything for L2/L3, and both change it in the same
direction: they *depend on* findings landing as checks inside existing plugins, which is what D-3
already mandates.

## Fold, do not build

D-7 set the precedent with #1271. Two more items fold rather than becoming new work:

1. **L3's catalog folds into**
   `plugins/claude-config/skills/audit-instructions/reference/criteria.md` as rows I12+. Not a new
   catalog, not a new skill, not a new plugin.
2. **Any deterministic slice of L2 or L3 folds into #445**, the CI-gate backlog, in that issue's
   documented `scripts/check-*.sh` + `.test.sh` + `ci.yml` lane shape — rather than becoming a
   standalone gate.

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

1. **L2's structural home inside `claude-config`** — a new phase in `audit-instructions` (Option A,
   recommended) versus a new sibling skill (Option B). Both satisfy D-3. Option A changes a shipped
   skill's published contract.
2. **L3's `UNBACKED` mapping** — a fourth authority value versus mapping onto the existing `OPINION`
   tag with a severity ceiling (recommended). The existing tag's intended semantics are documented
   only as a one-line gloss.
3. **#1225's existence qualifier versus `audit-automation-gaps`** — surfaced to #1225's owner above;
   not this effort's call.

## Method

Issue #1225 and every ticket in the matrix were read first-hand via `gh issue view`; PR #1096 via
`gh pr diff`. The sweep-shape search enumerated all 256 open issues and filtered titles for
audit/sweep/scan/all-plugin/conformance/catalog/criteria/conflict shapes. Population counts were
produced by enumerating `plugins/*`, `plugins/*/skills/*/SKILL.md`, `plugins/*/agents/*.md`, and
`.claude-plugin/marketplace.json`. Repository doctrine was read from `docs/PLUGIN-PHILOSOPHY.md`,
`docs/conventions/topic-docs/README.md`, and the four plugin manifests named above.

No claim about Claude Code harness behavior is asserted in this document; per D-16 the fresh-docs
mandate binds changes touching a plugin manifest, marketplace schema, hook contract, or documented
harness behavior, and this is a prose-only boundary analysis that touches none of them.
