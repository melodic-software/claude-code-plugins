# Design threads — discovery-subagent-dispatch

Scope: `integration`. The deliverables of this design are contracts and schemas that cross a process
boundary — the artifact protocol, an agent-definition frontmatter contract, a subagent return
payload, a sidecar header, and a coverage-ledger record. `component-map.md` would describe a
topology that already exists; `contract-spec.md` is the artifact this design owes beyond this file.

Upstream contract: [`../PLAN.md`](../PLAN.md) — Constraints and Decisions are authoritative and are
not restated here.

## Status summary

| # | Thread | Status | Contract |
|---|--------|--------|----------|
| T1 | Artifact-protocol v2 impact of index-plus-sidecars | **resolved** — no version bump | — |
| T2 | Agent-definition frontmatter contract | **directional** — tag: `upstream/1096` | [C1](contract-spec.md#c1--agent-definition-frontmatter-contract) |
| T3 | Verification-request return shape | **resolved** | [C2](contract-spec.md#c2--return-payload-verification-request) |
| T4 | Sidecar machine-readable header schema | **resolved** | [C3](contract-spec.md#c3--sidecar-header-schema) |
| T5 | Phase 0 coverage-ledger schema | **resolved** | [C4](contract-spec.md#c4--coverage-ledger-research-checklistmd) |
| T6 | Dispatch declaration: convention vs machine-checked | **resolved** — extend check 21 | [C5](contract-spec.md#c5--execution-site-declaration) |
| T7 | Cross-branch collision management | **directional** — tag: `merge-trigger/1260` | — |
| T8 | Dispatched research reads as Tier 3 under the skill's own rule | **directional** — tag: `merge-trigger/1260` | [C2](contract-spec.md#c2--return-payload-verification-request) |
| T9 | Design defaults — configurability, extension, observability, testability | **resolved** / one tagged | — |

**Tags.**

- `upstream/1096` (T2) — the named-agent bar is not yet merged, and C1's conformance argument is
  **argued, not met**. See T2 for the fork this hands `/planning:plan`.
- `merge-trigger/1260` (T7, T8) — no external research is owed and **no substance is deferred**. For
  T8 the substantive call is made (the tier attaches to the artifact's captured primaries, never to
  the transport); only the sentence's placement waits, because that line sits inside PR #1260's edit
  surface. For T7 the blocking input is the merge itself.
- `upstream/hook-telemetry` (T9) — routed to the convention's owner, not owed here.
- `upstream/304` — the execution-site declaration extension is authored against `skill-quality`'s
  contract once PR #1096 merges.

Round-1 resolutions, ratified 2026-07-24: T1 accepted as evidenced; named agents kept with the
bar justified on the tool cage and an upstream proposal to admit `skills:` preload as a third
qualifier (#304 / #1096); check 21 extended rather than duplicated; the return payload designed as
an instance of #496's contract; sidecar headers as YAML frontmatter; the coverage gate as a script;
`explore-deep`'s fork-mechanism correction left to #1267; PR #1260 merged and rebased onto before
`plugins/discovery/` is touched; this topic linked to #1225 as its execution.

## T1 — Does index-plus-sidecars break `artifact-protocol.md` v2?

**Resolved: no version bump required**, conditional on two constraints stated below.

Evidence, gathered this session:

- **Copy inventory (hashed, not eyeballed).** Five copies exist —
  `docs/PLUGIN-ARTIFACT-PROTOCOL.md` plus `reference/artifact-protocol.md` under `discovery`,
  `implementation`, `planning`, `verification`. All five hash to `bab2c6244f43f46fa47431b1c2cf1b69`.
- **Byte-identity is machine-enforced**, not honour-system: `scripts/check-cross-plugin-source-drift.sh`
  against `scripts/cross-plugin-source-registry.txt`. A protocol bump is therefore a mechanical,
  CI-gated multi-file update rather than a coordination hazard. This reprices the risk the Brief
  recorded as "the highest-risk unknown" substantially downward.
- **The version-bump trigger is narrower than the Brief assumed.** `artifact-protocol.md:39-41`
  fires on "a breaking **artifact-name** or **producer/consumer** change". Index-plus-sidecars
  changes neither: `EXPLORE.md` and `RESEARCH.md` keep their names, and the sidecars land inside
  `<memory_dir>/<topic-slug>/`, which the same file already declares as holding "raw captures, and
  scratch". Internal document structure is not a protocol-governed surface.
- **Consumer sweep (complete, all plugins — not only the three the Brief flagged).** Every
  reference to `EXPLORE.md` / `RESEARCH.md` outside `plugins/discovery/` classifies as a
  **path-forwarder or a naming reference**, never a parser:
  - `plugins/{implementation,planning,verification}/reference/artifact-protocol.md:26` — names the
    file in a tier list.
  - `docs/conventions/topic-docs/README.md`, `examples/worked-slice.md` — naming, gitignore
    patterns, tier tables.
  - `plugins/source-control/scripts/worktree-create.test.sh`, `plugins/docs-hygiene/.../detect.test.sh`
    — path-glob test fixtures.
  - `README.md` — prose.
  - `plugins/knowledge/skills/youtube-digest/**` — the one substantive hit, and it is a **sibling
    producer, not a consumer**: youtube-digest owns a `RESEARCH.md` in its own slice and already
    ships the index-plus-sidecar shape (`RESEARCH.md` + `research/findings/*.md`). Its only
    mechanical assertion is `extraction/evals/check-research-complete.js` — an existence plus
    ≥200-character length check, which an index satisfies.

**Constraints this resolution depends on** (violate either and the thread reopens):

1. Sidecars stay inside the topic's memory slice. Introducing a sidecar root outside
   `<memory_dir>/<topic-slug>/` is a placement change, which `artifact-protocol.md:41` routes to the
   versioned topic-docs convention, not to this profile.
2. `EXPLORE.md` / `RESEARCH.md` remain the entry points. A consumer handed the declared filename must
   still get a readable document; the index is that document.

## T2 — Agent-definition frontmatter contract

Open. Decision 2 selects named plugin agents (`discovery:researcher`, `discovery:explorer`). The
fleet scan surfaced a governing spec that did not exist when Decision 2 was ratified: PR #1096
(`feat/fresh-eyes-delegation-doctrine-gate`, issue #304 Phase 1) adds a **Delegation mechanics**
section to `docs/PLUGIN-PHILOSOPHY.md` whose **named-agent bar** reads:

> the same worker with the same instructions dispatches from multiple sites (or repeats via
> description-triggered direct invocation) AND a model pin or an enforced tool restriction is
> load-bearing.

Conformance analysis for this design:

- **Multi-site**: satisfied. `discovery:researcher` dispatches from `/discovery:research` and from
  the DISPATCH-DEFAULT rows across the marketplace that delegate research.
- **Model pin or tool restriction load-bearing**: not clearly satisfied. What is load-bearing here
  is the **`skills:` preload of the discipline** — a capability available only to a named agent
  definition, and one the bar does not enumerate. This is a gap in the bar, not necessarily a
  disqualification of the design.

Field-level shape is settled in [C1](contract-spec.md#c1--agent-definition-frontmatter-contract).
What is **not** settled is bar conformance itself, and the thread stays directional for that reason:

C1 argues the second conjunct from the tool cage. That argument is weaker than it first reads. The
cage omits `Edit`, but the agent still holds `Bash` and `Write` — and the doctrine's own tool-cage
sentence says an allowlist including `Bash` is **not** read-only and must be described by what it
actually enforces. So the cage does not mechanically enforce the memory-tier invariant; it narrows
the surface. The conjunct is argued, not met.

**The fork `/planning:plan` inherits:** if PR #1096 merges with the bar as written and without
admitting `skills:` preload as a third qualifier, C1's named agents do not clear it and **Decision 2
reopens** — the fallback being the ladder's default rung, a generic fresh-context subagent carrying
rich inline instructions, which costs Decision 12's guaranteed-mandate property. This is a
sequencing input for the plan, not a footnote.

## T3 — Verification-request return shape

Open. Decision 9 has a dispatched agent return `verification: pending` plus a verification request,
with the orchestrator dispatching the verifier as a sibling. The shape of that payload is
unspecified.

Cross-link surfaced by the fleet scan: **issue #496** (`status: needs-decision`, `priority: high`,
`needs-human`) — "orchestrator context economy — subagent return-payload contracts". Its principle 1
is a general return-payload contract for every dispatching skill: identifiers plus verdict plus
parked payload only. This design's return shape is an instance of that contract, and the two should
not be designed independently.

## T4 — Sidecar machine-readable header schema

Open, unblocked by T1. Decision 4 requires a header carrying topic, claims, and confidence so a
consumer can grep-then-read one section. Undecided: serialization (YAML frontmatter vs an HTML
comment block), the claim/confidence vocabulary, and whether the header is machine-validated.

Precedent available in-repo: `plugins/knowledge/skills/youtube-digest/` already runs an
index-plus-sidecar set with a host verify script, and the research skill's own source-tier and
confidence vocabulary is the natural source for the confidence axis.

## T5 — Phase 0 coverage-ledger schema

Open. Decisions 5 and 6 require `research-checklist.md`: every corpus item enumerated with a
per-item depth criterion and a completion mark, with the outcome gate failing on any unmarked item.
Undecided: the record shape, what "depth criterion" is drawn from, and how the gate reads it —
specifically whether the gate row is a model judgment or a script, which interacts with T6.

## T6 — Is phase-level dispatch declaration a convention or a machine-checked contract?

Open, and materially reshaped by the fleet scan. PR #1096 ships the answer's *shape* already:
`plugins/skill-quality/skills/check/reference/fresh-eyes-declarations.md` defines a deterministic,
greppable declaration contract enforced by `check-skill.sh` **check 21**, in two forms — visible
delegation prose matching `fresh[- ]context` on a line that also names a worker, or an
`<!-- fresh-eyes-exempt: <class> -- <reason> -->` directive over a closed class set.

The live question is therefore no longer "invent a mechanism" but "**extend the existing one, or
stay a convention**": check 21 declares *who judges*, whereas this design needs to declare *where a
phase executes*. Those are adjacent but not identical propositions.

Also inherited here: **issue #521** — the explore family's outcome-gate self-grades are a tranche-2
fresh-eyes deferral whose stated action is "re-judge on next touch, once the delegation-mechanics
doctrine and the skill-quality check land". This work IS that next touch.

## T7 — Cross-branch collision management

Open, new — surfaced by the fleet scan the user requested, not present in the Brief.

- **PR #1260 `feat/research-primary-source-ladder`** (open, updated 2026-07-24) edits exactly the
  five files this work must edit: `plugins/discovery/skills/research/SKILL.md`,
  `skills/research/context/discipline.md`, `skills/research/evals/evals.json`,
  `.claude-plugin/plugin.json`, `CHANGELOG.md`. It adds **outcome-gate criteria 9 and 10** to the
  same gate table where Decision 5 must add a coverage row, and adds discipline recipes to the same
  file where Decision 5's recipe lands. **Issue #464** independently records that same-plugin
  version bumps plus top-inserted CHANGELOG entries serialize concurrent PRs "by construction".
- **PR #1096 `feat/fresh-eyes-delegation-doctrine-gate`** is a spec dependency (T2, T6), not a file
  collision — it touches `docs/PLUGIN-PHILOSOPHY.md` and `plugins/skill-quality/**`, which this work
  does not.
- **Issue #1225** ("Sub-agent conventions: codify from latest official docs, then audit all
  plugins") overlaps this topic's two largest completed work products. Part 1 asks for codified
  subagent conventions — this Brief's Constraints block is that research, already done. Part 2 asks
  for an audit of every plugin against those conventions — the 138-row dispatch ledger is
  substantially that audit. The issue carries a **locked decision** this Brief does not honour:
  conventions live in the existing plugin-authoring conventions surface, under a hard
  **pointer-not-copy** rule. The Brief's Constraints block restates upstream field lists and tool
  filters inline, which is the form that decision forbids for the conventions doc.
- **Issues #1267 / #1268 / #1258 / #1082** already ticket the fork-mechanism staleness that the
  Brief's Amendment 7b and handoff item 6 record as an unscoped follow-up. #1267 is
  `status: ready` / `agent-ready` and names `explore-deep/SKILL.md:3` directly — the same line
  Decision 14 touches when `explore-deep` retires.

No file-level conflict exists on this branch **today**: it has touched only
`docs/topics/discovery-subagent-dispatch/PLAN.md`. Every collision above is prospective, arriving
the moment implementation edits `plugins/discovery/`.

Sequencing agreed: **#1260 merges first, this branch rebases, then `plugins/discovery/` is touched.**
The #1225 link is a comment plus a scope statement, and #1225's pointer-not-copy rule retargets the
Brief's Constraints research at [`docs/OFFICIAL-DOCS.md`](../../../OFFICIAL-DOCS.md), which is
already the marketplace's upstream link index. #1225's locked "extend, do not stand up a parallel
surface" resolves to PR #1096's `## Delegation mechanics` section in `docs/PLUGIN-PHILOSOPHY.md` —
verified at execution time as the current subagent-mechanics home, so no new `docs/conventions/`
directory is warranted.

## T8 — Dispatched research reads as Tier 3 under the skill's own rule

Directional; surfaced during contract authoring, not present in the Brief.

`plugins/discovery/skills/research/SKILL.md:148` states: *"Subagent returns are Tier 3 (synthesis),
not corroborators, until their cited primaries are fetched this turn."* Taken literally,
dispatch-by-default demotes every research run to the tier the skill's own outcome gate refuses —
criterion 1 requires a Tier 0/1 source captured this turn, and the orchestrator's view of a
dispatched run is a subagent return.

The rule is sound against its actual target: an ad-hoc subagent handing back synthesis with no
captured primaries. It does not fit a dispatched agent that ran the full discipline and wrote every
primary URL into the artifact. **The tier belongs to the artifact and its captured sources, not to
the transport.**

Remedy agreed: a scoped exception in the rule naming the discipline-running dispatched case. Exact
wording is deferred because that line sits inside PR #1260's edit surface, and the wording should be
written against the merged text rather than against a base that is about to move.

## T9 — Design defaults for an `integration` scope

Opened per the design skill's design-default requirement; not present in the Brief.

- **Configurability** — **resolved: none added.** Dispatch-by-default with a documented inline
  escape hatch is the only knob, and it is an invocation argument rather than config. A per-plugin
  model seam does not exist (plugin `userConfig` carries no model semantics), so the one consumer
  override is the harness-level `CLAUDE_CODE_SUBAGENT_MODEL`. Adding a discovery-local knob would
  stand up a second, weaker seam beside it.
- **Extension** — **resolved: the sidecar set is open, the header schema is closed.** New sidecars
  need no schema change; a new *header field* does. This is deliberately the inverse of the
  closed-set problem issue #408 records against discovery's ecosystem table, and C3's header is
  small enough that widening it stays cheap.
- **Observability** — **tagged-deferred, tag `upstream/hook-telemetry`.** The marketplace already
  owns a hook-telemetry convention (`docs/conventions/hook-telemetry/`) and subagent tool calls
  carry `agent_id` / `agent_type` in the hook payload, so dispatch is observable without new
  machinery. Whether a dispatched discovery run should *emit* a telemetry event is a question for
  that convention's owner, not for this design.
- **Testability** — **resolved: existing seams, no new ones.** Every discovery skill already ships
  `evals/evals.json`, and C4's gate is a shell script with the repo's established
  `*.test.sh` pattern beside it (`scripts/check-*.sh` + `check-*.test.sh`). Two seams, both already
  present; the design adds no third.
