# routine-capability-detection — PLAN

Promoted from the boris-routines-adoption plan's Phase 8 by
[#2685](https://github.com/melodic-software/claude-code-plugins/issues/2685). Tier 0 item 3 of that
effort, and the clause its originating goal names verbatim: "configurable per repo/product/app based
on the repo itself, any external context provided from CLAUDE.md, AGENTS.md, repo files, MCP
servers, CLI tools."

## Brief

### TLDR

Define how a routine discovers, per repository, whether it can actually run there — and ship it as
**routine capability resolution**: a fail-closed, declared-over-detected composition of surfaces
this marketplace already owns, resolved **per routine identity on its one bound scheduling
surface**, never as a flat repo profile. The spike's durable outcome is the resolution contract's
shape; implementation lands later as issue-filed phases extending the autonomy plugin.

Four findings inverted the original "detection" framing:

1. **Nothing resolves "which routines can run here" today — but nearly every input surface already
   has an owner.** The catalog states prerequisite *consequences* ("routes to the advisory path …
   never a silent degrade") without a resolution procedure; the autonomy setup skill discovers
   substrates, trackers, schedulers, and observability imperatively per slice; the toolchain
   resolution ladder owns ecosystem inference; the tracker seam owns tracker binding. The missing
   piece is a **composition contract with a verdict vocabulary**, not a new prober.
2. **The grain is the routine identity on a surface, not the repo.** Every artifact a resolution
   touches is keyed by full routine identity (`<class-token>` or `<class-token>/<posture-token>`),
   postures diverge exactly where prerequisites diverge (an advisory posture and a direct-change
   posture of the same class need different things), and a capability present on one execution
   surface says nothing about another — the setup contract already states per-surface detection
   for isolation substrates, and the same doctrine binds here.
3. **Detection is the proposal rung, never the authority.** The fleet's own ladders (toolchain:
   config present → infer, then offer to persist → ask → default) and the external consensus
   (Renovate onboarding, Linguist overrides, buildpacks' declared order) agree: detect → propose →
   human ratifies → declaration governs. And proposing is interactive-only — at routine runtime
   the resolution reports; it never persists.
4. **"Capability detection" is an occupied term with the opposite default.** The guard plugins use
   it for session-auth detection — fail-OPEN — and three more capability-adjacent vocabularies
   live in this fleet. The contract term is **routine capability resolution (per-repo)**, with a
   four-way disambiguation note (below).

### Goal

Lock the resolution contract's shape (this document), graduate the durable decision to an ADR,
file the implementation phases as tracker issues, and prune this slice before merge. The
implementation goal those issues carry: a repository operator — or an unattended scheduled run —
can ask "which routine identities can run against this repo, and why", and get a per-identity
verdict with per-signal provenance, produced by deterministic probes plus tracked declarations,
with agent judgment only where the question is genuinely semantic.

### Interview provenance

The user was unavailable and directed that nothing gate this effort. The interview's 16 decision
branches were answered with recommended answers, then adversarially validated by two fresh-context
agents with the authoring rationale withheld (the `/planning:audit-answers` shape). Outcomes:
12 confirmed (7 with required amendments), 4 challenged (output grain, surface qualification,
naming-collision enumeration, composition sourcing) — every challenge adopted as the validator
stated it. Four cross-cutting findings no question covered (per-class prerequisite data home,
candidate-set scoping, staleness posture, verdict-token naming) are absorbed below. **No answer is
represented as a user decision**, and one call is explicitly routed to the human rather than
settled here: the final verdict-token vocabulary (see "Open questions").

### The contract shape (the locked answers)

**Output grain.** One resolution per **routine identity** — `<class-token>` or
`<class-token>/<posture-token>` — computed for the pair (identity, its one bound scheduling
surface). Class-level axes (Access class, isolation floor, per-class prerequisites) are the
derivation *source*; the posture refines it; the identity is the emission key. A class-level
verdict cannot express that an advisory posture binds while its direct-change sibling does not,
and that is precisely where prerequisites diverge. The isolation floor and the `executor_class`
merge cap are consumed from the existing guardrail slice, never re-derived — the latter is
security-surface data and never repo-derivable.

**Candidate set.** `v1` rows only — they alone have definition leaves, and posture tokens are
leaf-owned. A `join:` row has no leaf and therefore no identities to resolve; it reports as
*deferred class*, not as a verdict. A `not-a-routine` row is outside the domain entirely — no
agent session exists to bind, so any verdict for it is a category error.

**Verdict vocabulary.** Four verdicts: provisionally `supported / supported-with-conditions /
unsupported / unknown`. `unknown` is first-class and distinct from `unsupported` — fail-closed,
both route to the advisory path. The tokens are provisional because verdict naming collides three
ways in this fleet (`binds` already means "has a ratified identity entry on the security binding";
"capability detection" is the guard plugins' fail-open term; `DET`/`AGT` are catalog judgment
verdicts, not signal labels) — the final vocabulary is a human ruling, made once, before the
contract document is written. Whatever the ruling, two constraints survive it: no token may read
as a security-binding assertion, and no token may read as health (`ok`, `available`, `healthy`,
`pass` are all barred).

**Precedence.** Declared beats detected, with detection proposing: a tracked declaration wins over
any probe result; detection fills gaps and proposes declarations, never silently overrides one.
Divergence between a declaration and a probe result is surfaced as a finding, not auto-resolved.
Proposing is **interactive-only**: non-interactive and forked contexts are barred from the
ask-and-persist rungs (the topic-docs rule, reused), so at routine runtime the resolution reports
and never persists. Per-rung ownership is part of the contract: connector entitlement for
`prod`/`product`/`org`/`ext` binds at the **org rung** of the binding seam, and a lower rung may
never assert a prerequisite a higher rung owns; security axes accept no repo-local value at all
(the autonomy plugin's ratified cascade deviation).

**Who detects.** Split per portion, in the catalog's own per-portion discipline. Presence-shaped
signals are probed by a **script with no agent session** ("prefer one wherever the judgment is
mechanical"). Semantic questions (does the test suite discriminate; which architecture rules
apply; what a CLAUDE.md convention implies) are **judgment-only**: never encoded as file-presence
heuristics — they resolve to `unknown` with a named follow-up, or to an interactive proposal pass.
The catalog's `DET`/`AGT` tokens are deliberately not reused for probes: there they are judgment
verdicts that carry "not a routine, zero agent tokens", and overloading them invites exactly that
misread.

**Probe classes.** Four, named for what they read. Every non-repo-file result is
**surface-qualified**: it is evaluated on, and carries, the surface it was probed on — a CLI on
the authoring laptop says nothing about the CI runner that fires the routine. Probe evidence is
durable per-surface (the existing isolation-binding `probe_evidence` pattern), and the two
keyspaces are distinct: isolation bindings key on execution-surface ids, while the scheduling
`surfaces` map carries `execution_surface` as a field — never collapsed.

1. **repo-file probes** — build/dependency manifests, test config, CI config, tracker binding,
   flag-system SDK presence: deterministic glob/manifest probes.
2. **harness-context probes** — `.mcp.json` server inventory, repo-declared plugins, committed
   skills: deterministic reads of structured, committed surfaces. `.mcp.json` presence is not
   availability: enablement is settings-gated (`enableAllProjectMcpServers` /
   `enabledMcpjsonServers` / `disabledMcpjsonServers`), and servers also arrive from user scope
   and plugins — the probe reports presence and the enablement gate separately.
3. **machine-context probes** — CLI availability, local substrates: deterministic, per-surface;
   a result is a claim about the probed surface only, never a repo claim.
4. **prose-context inference** — CLAUDE.md, AGENTS.md, README: judgment-only inference source for
   *proposing* declarations into non-security keys, interactively. The deterministic resolver
   never parses prose, and prose is never runtime authority. One platform fact bounds this class:
   Claude Code reads `CLAUDE.md`, not `AGENTS.md` — an `AGENTS.md` reaches a session only through
   a reference.

**Composition, not re-implementation.** Resolution composes the convention-owned **consumer
surfaces**, never a sibling plugin's bundled files; every cross-plugin reference is presence-gated
with a documented fallback per seam-phrasing:

- ecosystems: the toolchain seam (the fleet's stated SSOT for ecosystem detection and command
  resolution) where installed, reading the consumer's `.claude/ecosystems/<eco>.yaml` under the
  ecosystem-commands convention; fallback is inference from the repo's own build files, never
  another plugin's bundled defaults;
- tracker: the work-item tracker seam — `.work-item-tracker.json` plus the bound adapter's
  `capabilities.json` (declared adapter verb support);
- substrates, schedulers, observability: the autonomy setup skill's own discovery slices (same
  plugin, no gate needed);
- configured-surface enumeration: by each surface's own presence in the repo — never by reading
  the config-cascade registry table, which is a conformance ledger that deliberately lists
  non-conforming rows;
- signals with no owner (CI-config presence, flag-SDK presence): probes owned by this contract.

**Fail-closed.** A prerequisite that cannot be established does not enable the identity; it routes
to the advisory path exactly as the trigger contract already handles a missing surface or
entitlement, and absence semantics cite the philosophy's silently-skipped-feature-is-a-defect rule
rather than re-owning them. Fail-open is the guard plugins' session-auth posture, and precisely
what this contract must not inherit.

**Consumers — never admission data.** The resolution has **no binding-time consumer** and adds
**no new enforcement point**. Its two consumers are: (1) an input to the human-landed *prepared*
change to `admission.classification.temporal` on the settings-as-code home — the routine slice
prepares, never writes, the security surface; and (2) a **narrowing-only** influence on the
repo-local `routines.enabled` section — an identity may be enabled only when its verdict clears,
and an identity with no protected classification entry stays unclassified and fail-closed
human-gated regardless (already structural, cited not asserted). A repo-local input to a protected
path is the precise agent-writable bypass the classification obligation forbids.

**Configured is not working.** Presence establishes `configured`, never health. The verdict
vocabulary is non-health-asserting by construction, which is how the contract reconciles with the
liveness-assertion owner doc: it makes no success claim for a probe to be false about. A consumer
that treats `configured` as `working` is itself the false-green defect, owned by that consumer's
verification. Execution evidence (check runs, job logs) belongs to the consuming routine.

**No cached profile; recompute at every consumption.** The resolution recomputes wherever it is
consumed — a setup `check`, a pre-enablement gate, an advisory read; a persisted verdict is never
authority. A resolution computed once at setup would silently govern a routine firing weekly while
the repo gains test suites and loses connectors — the healthy-while-dead false-green shape, whose
owner doc this contract cites. The only persisted artifacts are declarations (human-ratified,
tracked) and surface-qualified probe evidence under the existing pattern. One existing nuance is
stated, not contradicted: the binding seam persists the discovered org-binding *document path* — a
pointer into the declaration layer, not a capability profile.

**Scheduled runs read committed surfaces only.** A cloud run clones from the default branch and
loads committed content; a capability claim sourced from one operator's machine is false in every
other execution context.

**Where it lands.** One new contract document in `plugins/autonomy/reference/` (the binding-seam
layout rule: each capability lands exactly one contract doc), hub-linked from `routines.md` by
pointer; **per-identity prerequisite data lives in each `v1` class's own leaf** — under the
single-home rule the contract doc owns vocabulary and derivation rules only, never per-class
facts. Implementation extends the existing autonomy setup skill as a capability slice (its own
stated extension model); declarations ride `.claude/autonomy/binding.json` as an additive section.
No new plugin, no new skill, no new catalog (ADR 0005), no new config-file family.

**Vocabulary.** Keyed to the catalog's existing axes — Access classes, join triggers, per-class
prerequisites including isolation floors — plus the four probe classes above. The disambiguation
note names four incumbent capability vocabularies this term is NOT: (i) the guard plugins'
session-auth "capability detection" (fail-open, session-scoped; consumed by the work-loop,
babysit-loop, and attend-queue skills); (ii) verification-topology's rejected model-capability
labels; (iii) loop-lane capability *tiers* (model selection); (iv) the tracker adapter's
`capabilities.json` (declared adapter verb support — a composed input here, not a synonym).

### Constraints

Binding repository rules, verified this session:

- **ADR 0005** — extend the existing catalog and plugin surfaces; never a new plugin, skill, or
  catalog.
- **ADR 0004** — nothing ships until it proves no existing skill covers it. The incumbent
  evidence is inlined in each phase issue (the `.work/` research record is gitignored and
  unreachable from any other execution context).
- **Contract-slice prune gate** — `docs/topics/routine-capability-detection/` matches no line in
  `scripts/contract-slice-baseline.txt`, and the baseline is read from the base revision, so it
  cannot be exempted. The terminal phase prunes this slice before merge.
- **Version bump + matching CHANGELOG entry in the same PR** for any plugin touched (CI-enforced;
  this spike's own PR touches no plugin — each implementation issue carries the obligation).
- **No acceptance/merge-rate metric anywhere, in any role.**
- Only `docs/topics/` is docs-only-allowlisted; the ADR this PR graduates sits outside it, so the
  full CI suite runs on this PR — expected and fine on an otherwise-clean tree.

### Captured assumptions

- The catalog's mapping rules stay the derivation authority for guardrail rows; capability
  resolution decides *whether an identity can run in a repo*, never *what class it derives* — the
  two must not be conflated.
- The autonomy setup skill's extension model ("capability slices that have not shipped yet — each
  lands with its own work package and extends this skill") remains the sanctioned implementation
  seam.
- External consensus grounding (Renovate/Linguist/buildpacks/Dependabot, agents.md, Claude Code
  docs) was verified against primary sources 2026-08-15; the detect→propose→ratify pattern and
  the no-cached-profile posture both held across every surveyed tool.

### Out of scope

- Any change to guardrail classes, the matrix, or the mapping rules — capability resolution reads
  the catalog; it never re-derives rows.
- Health/liveness verification of a configured surface (owned by the consuming routine's own
  verification per liveness-assertion).
- Org-binding authoring UX for connector entitlements (the org rung owns them; declaring them is
  org-policy work, interviewed in the setup slice, not designed here).
- The join-trigger lifecycle of catalog rows (per-catalog, not per-repo — a deferred class gains
  a leaf when its join trigger fires fleet-wide; this contract only answers per-repo, per-surface
  eligibility).
- A capability-resolution surface for non-routine consumers (loops, goals, one-shot sessions) —
  deferred with a trigger: revisit when a second consumer class asks the same per-repo question.

### Acceptance criteria (for the implementation issues)

1. Every verdict carries per-signal provenance (which probe on which surface, or which declaration
   at which rung).
2. The deterministic resolver runs with no agent session and is reproducible: same tree, same
   surface, same verdicts.
3. Fail-closed proven by fixture: an absent prerequisite yields `unknown` or `unsupported`, never
   a positive verdict.
4. Declared-beats-detected proven by fixture: a declaration contradicting a probe wins, and the
   divergence is reported.
5. Posture divergence proven by fixture: two postures of one class resolve to different verdicts
   from the same tree.
6. No verdict token reads as health or as a security-binding assertion; the contract text carries
   the liveness-assertion reconciliation clause.
7. No acceptance/merge-rate metric anywhere.

## Plan

### Standards grounding

| Surface | Sections leaned on |
|---|---|
| `plugins/autonomy/reference/routines.md` | axes, mapping rules, Access-to-prerequisites, routine identity, per-portion determinism, instruction provenance |
| `plugins/autonomy/reference/binding-seam.md` | ladder, null semantics, layout rule (one contract doc per capability) |
| `plugins/autonomy/reference/guardrails/admission-policy.md` | fail-closed seam; no agent-writable admission input |
| `plugins/autonomy/reference/trigger-dispatch.md` | advisory-path rule; classification obligation; executor classes |
| `plugins/autonomy/skills/setup/SKILL.md` | slice extension model; per-surface detection; prepared-never-written security surface; identity-keyed sections |
| `docs/conventions/config-cascade/README.md` | layer semantics; autonomy's declared deviation; provenance reporting |
| `docs/conventions/topic-docs/README.md` | contract-slice lifecycle; prose-is-inference posture; non-interactive rung bar; single-home rule |
| `docs/conventions/liveness-assertion/README.md` | healthy-while-dead class; the reconciliation clause; staleness posture |
| `docs/conventions/seam-phrasing/README.md` | presence-gate-plus-fallback shape for every composed seam |
| `docs/PLUGIN-PHILOSOPHY.md` | no sibling-plugin imports; deterministic-gate preference; configuration ownership; absence semantics |
| `plugins/toolchain/reference/resolution-ladder.md` | the canonical detect→offer-to-persist ladder |
| `plugins/work-items/tools/work-item-tracker/CONTRACT.md` | tracker binding + adapter `capabilities.json` |

### Phase spine

```text
P1 contract doc ──> P2 leaf prerequisite sections ──> P3 deterministic resolver ──> P4 setup capability slice
        (each an issue; sequential, same plugin, shared vocabulary)

P5 graduate + prune ── terminal; executed on THIS branch before THIS PR merges
```

P1→P4 are sequential by design: the leaves consume the contract's vocabulary; the resolver
implements both; the slice consumes the resolver. All four touch `plugins/autonomy/**`, so each
runs the full CI suite and carries its own version bump + CHANGELOG entry. P1 is gated on the
human verdict-vocabulary ruling (Open questions).

---

### Phase 1: The capability-resolution contract document [ISSUE]

One new document, `plugins/autonomy/reference/capability-resolution.md`, owning everything under
"The contract shape" above **except per-class facts**: identity-and-surface output grain,
candidate-set rule, verdict vocabulary (as ruled by the human gate), probe classes with
surface qualification, precedence with per-rung ownership and interactive-only proposing,
composition seams (each presence-gated), fail-closed posture, the never-admission-data consumer
rule, configured≠working with the liveness-assertion reconciliation clause, recompute-at-every-
consumption, committed-surfaces-only for scheduled runs, and the four-way disambiguation note.

- ADR-0004 incumbent evidence (inline in the issue): no contract, skill, or script answers "which
  routine identities can run against this repository"; nearest incumbents are the setup skill's
  per-slice discovery prose and the catalog's prerequisite-consequence rule, neither a resolution
  procedure.
- `routines.md` "Access to prerequisites" gains one pointer sentence; the plugin README gains one
  bullet. No other hub edit.
- Version bump + CHANGELOG (autonomy) in the same PR.
- Sanity: `ls plugins/autonomy/reference/capability-resolution.md`;
  `grep -c "capability-resolution" plugins/autonomy/reference/routines.md` ≥ 1;
  `grep -ci "fail-open" plugins/autonomy/reference/capability-resolution.md` ≥ 1 (the
  disambiguation note names the opposite posture);
  `scripts/check-changelog-parity.sh --check-bump origin/main` exits 0;
  `git diff origin/main | grep -inE "merge rate|merge-rate|acceptance rate"` yields only
  forbidding lines.

### Phase 2: Per-identity prerequisite sections in the v1 leaves [ISSUE]

Under the single-home rule, per-class facts belong to each class's own leaf. Each of the ten `v1`
leaves gains a prerequisites section deriving its identities' needs — Access class, isolation
floor, connector entitlements, per-posture divergences — through the P1 vocabulary. `join:` and
`not-a-routine` rows gain nothing (no leaves; out of domain).

- The catalog hub is untouched beyond P1's pointer; the leaves own their facts.
- Posture-divergent classes (advisory vs direct-change postures) must show different prerequisite
  sets — that divergence is the grain argument made concrete.
- Version bump + CHANGELOG (autonomy).
- Sanity: every file under `plugins/autonomy/reference/routines/` contains a prerequisites
  section (`grep -L` returns empty); at least one leaf shows per-posture divergence;
  `scripts/check-changelog-parity.sh --check-bump origin/main` exits 0.

### Phase 3: The deterministic resolver [ISSUE]

The script core (incumbent shape: Node `.mjs` beside the setup skill's existing conformance
scripts): resolves the verdict set for the `v1` identities on a named surface, with no agent
session.

- Probes: repo-file and harness-context classes, plus composition reads of
  `.claude/autonomy/binding.json` (declared sections), `.claude/ecosystems/*.yaml` (presence and
  keys per the ecosystem-commands convention), `.work-item-tracker.json` + adapter
  `capabilities.json`, `.mcp.json` (presence and enablement gate reported separately).
  Machine-context probes only behind an explicit surface argument, results surface-qualified.
- Output: per-identity verdict + per-signal provenance (probe + surface, or declaration + rung).
- Fixtures: fail-closed case, declared-beats-detected case, divergence-report case,
  posture-divergence case, and a bare-repo case (all verdicts `unknown`/`unsupported`, exit
  honest).
- Exec bit via `git update-index --chmod=+x` for any shebang file; shell-portability and
  ShellCheck gates apply if any `.sh` ships.
- Version bump + CHANGELOG (autonomy); evals if SKILL.md changes.
- Sanity: two consecutive runs on the same tree and surface emit byte-identical verdicts; the
  five fixture assertions pass; `scripts/check-changed-skills.sh origin/main` exits 0.

### Phase 4: The setup capability slice [ISSUE]

Extends the autonomy setup skill per its own extension model: `check` reports the resolved
verdict set with provenance; `apply` runs the interactive propose→ratify loop — the prose-context
pass reads CLAUDE.md/AGENTS.md/README to propose declarations into **non-security keys only**,
the human ratifies, and the slice writes the capability section of `.claude/autonomy/binding.json`
additively (absent-section tolerance holds).

- Detect-diff-reconcile: an existing declaration is authoritative input to reconcile against,
  never a blank to overwrite; divergence from probe results is surfaced as a finding.
- Narrowing-only enablement: the routines slice may enable an identity only when its verdict
  clears; `unknown`/`unsupported` routes to the advisory path. The slice **prepares** any
  security-binding change and never writes that surface.
- Org-rung entitlements are interviewed, never auto-written: the slice reports which
  prerequisites await the org rung and stops.
- Non-interactive contexts skip the ask-and-persist rungs and report assumptions (the topic-docs
  rule, cited).
- Version bump + CHANGELOG (autonomy); evals cover the new slice paths.
- Sanity: a fixture binding with a declaration contradicting a probe produces a reconcile
  finding, not a silent overwrite; `check` on a bare repo reports every identity `unknown` or
  `unsupported` with no error; `scripts/check-changed-skills.sh origin/main` exits 0.

### Phase 5: Graduate the durable outcomes and prune the contract slice [TERMINAL — this PR]

The prune gate fails on this branch until this phase runs, by design: this slice matches no
baseline line and the baseline is read from the base revision (`check-contract-slice-prune`).

- Graduate the resolution-contract decision to an ADR (per-identity-per-surface grain;
  declared-over-detected composition of owning surfaces; fail-closed; never admission data;
  configured≠working; no cached profile; the naming disambiguation) — hard to reverse once
  implemented against, surprising without context, and the product of real trade-offs with named
  rejected alternatives.
- File Phases 1-4 as tracker issues, each carrying its inlined incumbent evidence, work items,
  and sanity checks; file the reuse-or-replace follow-up (discovery's `ecosystem-discovery.md`
  duplicates the toolchain signal vocabulary) as its own issue, outside this plan.
- Paste this PLAN into the PR body inside a `<details>` block. The durable record is the
  graduated artifacts themselves — the ADR and the filed issues; the recovery pointer for the
  pruned files uses the Contents-API-by-SHA form (`ref=<pruning-commit>^`, topic-docs lifecycle
  step 5), never a `git show <branch-sha>:<path>` form — this repo squash-merges and deletes head
  branches, so branch-SHA pointers die with the branch (#2699).
- A final commit deletes `docs/topics/routine-capability-detection/`.
- Sanity: `bash scripts/check-contract-slice-prune.sh --check-diff origin/main` exits 0 after the
  prune commit; `bash scripts/check-contract-slice-prune.sh --check` exits 0 (no stale baseline
  entry — this slice never had one); `ls docs/topics/routine-capability-detection/ 2>/dev/null`
  returns non-zero; the PR body contains the pasted plan.

---

### Blast radius

**LOW for this PR** (one ADR added, one slice pruned; no plugin, contract, or CI surface
changes). **MEDIUM for the filed implementation phases**: they extend one plugin's reference and
setup surfaces behind additive schema tolerance, with no breaking change to any consumed format;
the risk concentrated in P4's binding writes is bounded by detect-diff-reconcile, narrowing-only
enablement, and the org-rung/security-axis exclusions.

### Alternatives considered

| Alternative | Why rejected |
|---|---|
| Free-standing repo profile artifact | Re-opens interpretation at every consumer; the consuming question is per-identity |
| Class-grain verdicts | Cannot express posture divergence, which is exactly where prerequisites diverge; every consuming artifact is identity-keyed |
| Flat (surface-blind) signals | A capability on one surface says nothing about another; the setup contract already states per-surface detection |
| Detected beats declared | Against fleet ladders and external consensus; staleness surfaces as divergence findings instead |
| Self-contained prober with own signal tables | Re-implements owned probes; forks the toolchain vocabulary the way discovery's `ecosystem-discovery.md` already did |
| Reading sibling-plugin bundled files | Barred: no sibling-plugin imports; the consumer surface is the seam |
| Cached capability profile with TTL | No fleet precedent; the healthy-while-dead shape; external consensus recomputes per run |
| Fail-open on missing signal | The guard plugins' session-auth posture — correct there, an unauthorized autonomous run here |
| Resolution as admission data | A repo-local input to a protected path is the agent-writable bypass the classification obligation forbids |
| New `.claude/capabilities.*` config family | Second home for admission-adjacent facts; binding.json sections are additive by design |
| Parse conventions out of CLAUDE.md/AGENTS.md at run time | Prose is never runtime authority; agent-writable prose can never satisfy an admission-adjacent input |
| Per-class facts in the contract doc | Single-home violation; leaf-owned data |
| Bare term "capability detection" | Collides with four incumbent vocabularies; "resolution" is the house noun for layer composition |
| New plugin or new skill | ADR 0005; the setup skill's slice model is the sanctioned extension seam |

### Test strategy

Docs-shaped phases carry grep-shaped sanity checks (stated per phase); the resolver phase is
fixture-first — the fail-closed, declared-beats-detected, and posture-divergence fixtures exist
before the resolver does; the slice phase asserts reconcile-not-overwrite on fixtures.
Change-set-wide on every phase: `check-changelog-parity.sh --check-bump`,
`check-changed-skills.sh`, `check-contract-slice-prune.sh --check-diff`, and the forbidden-metric
sweep over the whole diff.

### Risks and mitigations

| Risk | L | I | Mitigation |
|---|---|---|---|
| Verdict tokens drift into health or security-binding claims | Med | High | Barred-token constraints; human naming gate before P1; liveness-assertion clause |
| A repo-local declaration asserts an org-rung prerequisite | Med | High | Per-rung ownership in the contract; P4 interviews instead of writing; admission stays fail-closed regardless |
| Probe false positives (configured-but-dead surfaces) | High | Med | configured≠working is the contract's own vocabulary; consuming routines own health |
| Stale verdict governs a standing routine | Med | High | Recompute at every consumption; no persisted verdict is authority; liveness-assertion cited |
| Composition seam absent (no tracker binding, no ecosystems file) | High | Low | Presence-gate + documented fallback per seam-phrasing; absence is a verdict input, not an error |
| Surface qualification collapses into a flat answer | Med | High | Per-(identity, surface) grain in the contract; the setup skill's per-surface doctrine cited |
| Term collision confuses readers | Med | Med | Four-way disambiguation note; "resolution" noun |

### Open questions

- **ROUTED TO HUMAN — verdict-token vocabulary.** Three naming collisions surfaced in validation
  (`binds` = ratified security-binding entry; "capability detection" = the guard plugins'
  fail-open incumbent; `DET`/`AGT` = catalog judgment verdicts). The plan uses provisional tokens
  (`supported / supported-with-conditions / unsupported / unknown`) and P1 is gated on one human
  ruling covering all three names. This is a genuine open question, not an agent-settled one.
- No other question blocks this PR; the remaining human decisions are implementation-time gates,
  listed below.

### Handoff to implementation

#### User-approval gates (decisions this spike does NOT make)

- **The verdict-token vocabulary ruling** (Open questions) — before P1's contract text is
  written.
- **P1's contract-document text** — the contract fixes vocabulary future resolvers implement
  against; a human reviews before it merges.
- **P4's binding-write surface** — the slice writes a tracked team file; the propose→ratify loop
  puts a human on every declaration, and the slice ships only after that flow is reviewed.
- **Org-rung entitlement declarations** — org-policy decisions, interviewed at setup time, never
  auto-written.
- **Whether capability verdicts should ever feed the security binding mechanically** — deferred
  with a trigger: revisit if a class's admission entry wants to key on a capability verdict;
  today the resolution is never admission data.

#### Mechanical work

- Commit per phase; surgical `git add` of named paths only; commit messages via stdin heredoc.
- Each `plugins/**` phase verifies its version bump + CHANGELOG before opening its PR.
- PR bodies: native closing keyword (or `No linked issue`) + non-empty `## Related`.
