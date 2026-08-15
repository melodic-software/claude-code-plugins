# routine-capability-detection — PLAN

Promoted from the boris-routines-adoption plan's Phase 8 by
[#2685](https://github.com/melodic-software/claude-code-plugins/issues/2685); the parent plan was
carried by PR [#2686](https://github.com/melodic-software/claude-code-plugins/pull/2686) and its
slice is pruned, so #2686's body is the parent contract's followable home. Tier 0 item 3 of that
effort, and the clause its originating goal names verbatim: "configurable per repo/product/app
based on the repo itself, any external context provided from CLAUDE.md, AGENTS.md, repo files,
MCP servers, CLI tools."

## Brief

### TLDR

Define how a routine discovers, per repository, whether it can actually run there — and ship it as
**routine prerequisite resolution**: a fail-closed, declared-over-detected composition of surfaces
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
4. **Every nearby name is taken.** "Capability detection" is the guard plugins' fail-OPEN
   session-auth term; "capability" alone already means "a shipped contract area of this plugin"
   inside the autonomy plugin itself; three more capability-adjacent vocabularies live in the
   fleet. The provisional contract term is therefore **routine prerequisite resolution
   (per-repo)** — "prerequisite" is the catalog's own established noun for exactly these facts —
   with a five-way disambiguation note and a single human naming ruling gating the contract
   document (below).

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
stated it. **No answer is represented as a user decision**, and one call is explicitly routed to
the human rather than settled here: the naming ruling (see "Open questions"). "Nothing gates this
effort" applies to this spike's own PR; the filed P1 issue is deliberately marked blocked on that
human ruling at filing time — a gate on future implementation, not on this PR.

### Stress-test summary

After the interview validation, the drafted plan took two further independent fresh-context
passes: an adversarial review (assumptions, evidence, failure scenarios, operational gotchas) and
a conformance audit (the promoting issue's sanity checks plus every constraint, run empirically).
They returned 2 CRITICAL, 6 HIGH, 13 MEDIUM/LOW-class findings plus three sanity-check defects;
every finding was adopted. The CRITICALs reshaped the plan: the resolver had no machine-readable
source for identities or prerequisites (leaf prose was the only home — hence the new generated,
drift-gated emission phase), and the acceptance criteria were satisfiable by a resolver that
hardcodes `unknown` (hence the positive-verdict criterion and fixture). The HIGHs added the fifth
naming collision (autonomy's own "capability" vocabulary), real version-bump assertions in place
of a vacuously-passing gate, `path:line` incumbent evidence for every phase, the `claude-config`
seam for MCP enablement, the orphaned-fixtures gate and test-harness pair, and the
signal-envelope constraint on the new binding section.

### The contract shape (the locked answers)

**Output grain.** One resolution per **routine identity** — `<class-token>` or
`<class-token>/<posture-token>` — computed for the pair (identity, its one bound scheduling
surface). Class-level axes (Access class, isolation floor, per-class prerequisites) are the
derivation *source*; the posture refines it; the identity is the emission key. A class-level
verdict cannot express that an advisory posture is runnable while its direct-change sibling is
not, and that is precisely where prerequisites diverge. The isolation floor and the
`executor_class` merge cap are consumed from the existing guardrail slice, never re-derived — the
latter is security-surface data and never repo-derivable.

**Candidate set.** `v1` rows only — they alone have definition leaves, and posture tokens are
leaf-owned. A `join:` row has no leaf and therefore no identities to resolve; it reports under a
deferred-class marker, not as a verdict (that marker's token is part of the naming ruling below).
A `not-a-routine` row is outside the domain entirely — no agent session exists to bind, so any
verdict for it is a category error.

**Verdict vocabulary.** Four verdicts: provisionally `supported / supported-with-conditions /
unsupported / unknown`. `unknown` is first-class and distinct from `unsupported` — fail-closed,
both route to the advisory path. All output tokens — the four verdicts and the deferred-class
marker — are provisional pending the single human naming ruling (Open questions). Whatever the
ruling, two constraints survive it: no token may read as a security-binding assertion (`binds`
already means "has a ratified identity entry on the security binding"), and no token may read as
health (`ok`, `available`, `healthy`, `pass` are all barred).

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
signals are probed by a **script with no agent session** — the deterministic-probe preference is
this contract's own stated choice, consistent with the philosophy's deterministic-gate posture
that the promoting issue names as an input. Semantic questions (does the test suite discriminate;
which architecture rules apply; what a CLAUDE.md convention implies) are **judgment-only**: never
encoded as file-presence heuristics — they resolve to `unknown` with a named follow-up, or to an
interactive proposal pass. The catalog's `DET`/`AGT` tokens are deliberately not reused for
probes: there they are judgment verdicts that carry "not a routine, zero agent tokens", and
overloading them invites exactly that misread.

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
   `enabledMcpjsonServers` / `disabledMcpjsonServers` — a question the `claude-config` audit
   already owns, composed presence-gated, never re-implemented), and servers also arrive from
   user scope and plugins — the probe reports presence and the enablement gate separately.
   **Bounded limitation, stated up front:** the enablement gate is only partly resolvable from
   committed surfaces (`.claude/settings.local.json` and user scope are invisible to a clone), so
   on a scheduled run an MCP-dependent identity can resolve at best
   `supported-with-conditions` — and where enablement is undeterminable, `unknown`. That is the
   fail-closed posture working as designed, not a bug to discover later.
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
  ecosystem-commands convention — reading **resolved** state, not bare presence: an ecosystem
  present but `enabled: false` is not configured, and the user-global and `.local.yaml` layers
  are uncommitted, so a scheduled run reports them unresolvable (the same treatment as MCP
  enablement); fallback is inference from the repo's own build files, never another plugin's
  bundled defaults;
- MCP enablement conformance: the `claude-config` audit surface, presence-gated;
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

**Consumers — never admission data.** The resolution **narrows an existing enforcement input and
adds none**. Its two consumers are: (1) an input to the human-landed *prepared* change to
`admission.classification.temporal` on the settings-as-code home — the routine slice prepares,
never writes, the security surface; and (2) a **narrowing-only** influence on the repo-local
`routines.enabled` section (which the existing envelope conformance already validates claims
against) — an identity may be enabled only when its verdict clears, and an identity with no
protected classification entry stays unclassified and fail-closed human-gated regardless (already
structural, cited not asserted). A repo-local input to a protected path is the precise
agent-writable bypass the classification obligation forbids.

**Configured is not working.** Presence establishes `configured`, never health. The verdict
vocabulary is non-health-asserting by construction: it makes no success claim for a probe to be
false about. The liveness-assertion contract's on-touch rule still binds every implementing
surface — each phase that touches an engine surface (the setup `check`, the resolver) states
which taxonomy row applies and how it satisfies fail-loud or agent-readable routing, rather than
claiming exemption. A consumer that treats `configured` as `working` is itself the false-green
defect, owned by that consumer's verification. Execution evidence (check runs, job logs) belongs
to the consuming routine.

**No cached profile; recompute at every consumption.** The resolution recomputes wherever it is
consumed — a setup `check`, a pre-enablement gate, an advisory read; a persisted verdict is never
authority. A resolution computed once at setup would silently govern a routine firing weekly
while the repo gains test suites and loses connectors — the healthy-while-dead false-green shape.
The only persisted artifacts are declarations (human-ratified, tracked) and surface-qualified
probe evidence under the existing pattern. One existing nuance is stated, not contradicted: the
binding seam persists the discovered org-binding *document path* — a pointer into the declaration
layer, not a capability profile.

**Scheduled runs read committed surfaces only.** A cloud run clones from the default branch and
loads committed content; a capability claim sourced from one operator's machine is false in every
other execution context.

**Where it lands.** One new contract document in `plugins/autonomy/reference/` (the binding-seam
layout rule: each shipped contract area lands exactly one document there), provisionally
`prerequisite-resolution.md`, hub-linked from `routines.md` by pointer. **Per-identity
prerequisite data lives in each `v1` class's own leaf** — under the single-home rule the contract
doc owns vocabulary and derivation rules only, never per-class facts. Between the leaves and the
resolver sits **one generated, drift-gated machine-readable emission** derived from the leaves
(the generate-plus-`--check` pattern the catalog generator established): the leaves stay the
authored single home, and the resolver reads structure, never prose. The emission is a generated
in-plugin artifact, not consumer configuration — it creates no new config-file family.
Implementation extends the existing autonomy setup skill as a slice (its own stated extension
model); declarations ride `.claude/autonomy/binding.json` as an additive section that
**references existing scheduling-surface ids and declares no `surfaces` map of its own** (the
envelope conformance check merges every section's `surfaces` map, and duplicates are ambiguous).
No new plugin, no new skill, no new catalog, no new config-file family.

**Vocabulary.** Keyed to the catalog's existing axes — Access classes, join triggers, per-class
prerequisites including isolation floors — plus the four probe classes above. The disambiguation
note names five incumbent vocabularies this term is NOT: (i) the guard plugins' session-auth
"capability detection" (fail-open, session-scoped; consumed by the work-loop, babysit-loop, and
attend-queue skills); (ii) the autonomy plugin's own internal "capability" (a shipped contract
area: "each capability … lands exactly one contract document", "capability slices"); (iii)
verification-topology's rejected model-capability labels; (iv) loop-lane capability *tiers*
(model selection); (v) the tracker adapter's `capabilities.json` (declared adapter verb support —
a composed input here, not a synonym). This is why the provisional term drops "capability"
altogether for the catalog's own noun, "prerequisites".

### Constraints

Binding rules, each verified this session:

- **Extend, don't fragment** — no new plugin, skill, catalog, or config-file family. Carried by
  the philosophy's design boundary (a plugin "never imports files from a sibling plugin";
  `docs/PLUGIN-PHILOSOPHY.md:20-22`) and the setup skill's slice extension model
  (`plugins/autonomy/skills/setup/SKILL.md:456`); the parent Brief's resolved landing question
  and ADR 0005's question-not-population doctrine are supporting precedent, cited as such rather
  than as a general repository rule.
- **ADR 0004 D-1** — nothing ships until an incumbent search with `path:line` evidence proves no
  existing surface covers it. Each phase below carries its evidence inline, and each filed issue
  restates it — the `.work/` memory tier is gitignored and unreachable from any other execution
  context, so nothing durable may point there.
- **Contract-slice prune gate** — `docs/topics/routine-capability-detection/` matches no line in
  `scripts/contract-slice-baseline.txt`, and the baseline is read from the base revision, so it
  cannot be exempted. The terminal phase prunes this slice before merge.
- **Version bump + matching CHANGELOG entry in the same PR** for any plugin touched. The parity
  gate only fires when a manifest version *changed*, so each phase asserts the bump itself (the
  manifest version differs from `origin/main`) **and** `--check-bump` exit 0 — never the latter
  alone, which passes vacuously on a bump-less diff. This spike's own PR touches no plugin.
- **No acceptance/merge-rate metric anywhere, in any role** — a standing directive inherited from
  the parent effort's Brief (its acceptance criterion 4). Its codification into contract text is
  filed parent work, not yet on `main`; this plan binds itself to the directive regardless.
- Only `docs/topics/` is docs-only-allowlisted; the ADR this PR graduates sits outside it, so the
  full CI suite runs on this PR — expected and fine on an otherwise-clean tree.

### Captured assumptions

- The catalog's mapping rules stay the derivation authority for guardrail rows; prerequisite
  resolution decides *whether an identity can run in a repo*, never *what class it derives* — the
  two must not be conflated.
- The autonomy setup skill's extension model ("capability slices that have not shipped yet — each
  lands with its own work package and extends this skill") remains the sanctioned implementation
  seam.
- External consensus grounding (Renovate/Linguist/buildpacks/Dependabot, agents.md, Claude Code
  docs) was verified against primary sources 2026-08-15; the detect→propose→ratify pattern and
  the no-cached-profile posture both held across every surveyed tool.

### Out of scope

- Any change to guardrail classes, the matrix, or the mapping rules — prerequisite resolution
  reads the catalog; it never re-derives rows.
- Health/liveness verification of a configured surface (owned by the consuming routine's own
  verification; the on-touch obligation for surfaces this plan's phases touch is in scope and
  stated per phase).
- Org-binding authoring UX for connector entitlements (the org rung owns them; declaring them is
  org-policy work, interviewed in the setup slice, not designed here).
- The join-trigger lifecycle of catalog rows (per-catalog, not per-repo — a deferred class gains
  a leaf when its join trigger fires fleet-wide; this contract only answers per-repo, per-surface
  eligibility).
- A prerequisite-resolution surface for non-routine consumers (loops, goals, one-shot sessions) —
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
6. **A positive verdict is reachable, proven by fixture**: a fully-provisioned fixture tree
   yields the positive verdict for a named identity, with the signals that produced it in
   provenance. Without this, a resolver hardcoding `unknown` passes every other criterion and
   fail-closed ships it silently.
7. Every engine surface a phase touches states its liveness-assertion taxonomy row and how it
   satisfies fail-loud or agent-readable routing; no verdict token reads as health or as a
   security-binding assertion.
8. No acceptance/merge-rate metric anywhere.

## Plan

### Standards grounding

| Surface | Sections leaned on |
|---|---|
| `plugins/autonomy/reference/routines.md` | axes, mapping rules, Access-to-prerequisites, routine identity, per-portion determinism, instruction provenance |
| `plugins/autonomy/reference/binding-seam.md` | ladder, null semantics, layout rule (one contract doc per shipped area) |
| `plugins/autonomy/reference/guardrails/admission-policy.md` | fail-closed seam; no agent-writable admission input |
| `plugins/autonomy/reference/guardrails/isolation-ladder.md` | the per-class isolation floor P2 derives per leaf |
| `plugins/autonomy/reference/guardrails.md` | the matrix the floors come from |
| `plugins/autonomy/reference/trigger-dispatch.md` | advisory-path rule; classification obligation; executor classes |
| `plugins/autonomy/skills/setup/SKILL.md` | slice extension model; per-surface detection; prepared-never-written security surface; identity-keyed sections |
| `docs/conventions/config-cascade/README.md` | layer semantics; autonomy's declared deviation; provenance reporting |
| `docs/conventions/topic-docs/README.md` | contract-slice lifecycle; prose-is-inference posture; non-interactive rung bar; single-home rule |
| `docs/conventions/liveness-assertion/README.md` | healthy-while-dead class; the on-touch obligation |
| `docs/conventions/seam-phrasing/README.md` | presence-gate-plus-fallback shape for every composed seam |
| `docs/conventions/ecosystem-commands/README.md` | the consumer ecosystems surface the resolver reads |
| `docs/PLUGIN-PHILOSOPHY.md` | no sibling-plugin imports; absence semantics; configuration ownership |
| `plugins/toolchain/reference/resolution-ladder.md` | the canonical detect→offer-to-persist ladder; resolved-`enabled` semantics |
| `plugins/work-items/tools/work-item-tracker/CONTRACT.md` | tracker binding + adapter `capabilities.json` |

### Phase spine

```text
P1 contract doc ──> P2 leaf prerequisite sections ──> P3 generated emission ──> P4 resolver ──> P5 setup slice
        (each an issue; sequential, same plugin, shared vocabulary)

P6 graduate + prune ── terminal; executed on THIS branch before THIS PR merges
```

P1→P5 are sequential by design: the leaves consume the contract's vocabulary; the emission is
generated from the leaves; the resolver reads the emission; the slice consumes the resolver. All
five touch `plugins/autonomy/**`, so each runs the full CI suite. The four change-set-wide gates
run in **every** phase PR in addition to each phase's own checks: the bump assertion pair (the
manifest version differs from `origin/main` AND `check-changelog-parity.sh --check-bump` exits 0),
`check-changed-skills.sh`, `check-orphaned-fixtures.sh --check`, and
`check-contract-slice-prune.sh --check-diff` (must-not-regress — trivially green on a sliceless
diff, listed so a phase that reintroduces a slice is caught). The forbidden-metric sweep
(`git diff origin/main | grep -inE "(merge|acceptance)[ -]rate"` yields only forbidding lines) is
a declared reviewer check, not an exit-code gate. P1 is gated on the human naming ruling (Open
questions).

---

### Phase 1: The prerequisite-resolution contract document [ISSUE — blocked on the naming ruling]

One new document, provisionally `plugins/autonomy/reference/prerequisite-resolution.md`, owning
everything under "The contract shape" above **except per-class facts**: identity-and-surface
output grain, candidate-set rule, the ruled verdict vocabulary and deferred-class marker
(fail-closed, `unknown` first-class), the four probe classes with surface qualification and the
two bounded limitations (MCP enablement, uncommitted ecosystem layers), precedence with per-rung
ownership and interactive-only proposing, composition seams (each presence-gated, including the
`claude-config` MCP-enablement seam), the narrows-and-adds-no-enforcement consumer rule,
configured≠working with the liveness-assertion on-touch statement, recompute-at-every-
consumption, committed-surfaces-only for scheduled runs, and the five-way disambiguation note.

- ADR-0004 incumbent evidence (restate inline in the issue): no contract, skill, or script
  answers "which routine identities can run against this repository" —
  `plugins/autonomy/reference/routines.md:122-133` states prerequisite consequences only (missing
  surface → advisory path), no procedure; `plugins/autonomy/skills/setup/SKILL.md:52-59` and
  `:225-232` are imperative per-slice discovery prose (substrates "PER SURFACE"), not a reusable
  contract; repo-wide sweeps for capability-resolver vocabulary return only the five incumbent
  meanings the disambiguation note names.
- Authoring gotcha: the CI spell gate splits coined hyphenated compounds — prefer backticked
  tokens or plain words for coinages like declared-over-detected.
- One pointer sentence in `routines.md` "Access to prerequisites"; one bullet in the plugin
  README. No other hub edit.
- Version bump + matching CHANGELOG entry: assert the manifest version differs from `origin/main`
  AND `scripts/check-changelog-parity.sh --check-bump origin/main` exits 0.
- Sanity: `ls plugins/autonomy/reference/prerequisite-resolution.md` exits 0;
  `grep -c "prerequisite-resolution" plugins/autonomy/reference/routines.md` ≥ 1;
  `grep -ci "fail-open" plugins/autonomy/reference/prerequisite-resolution.md` ≥ 1 (the
  disambiguation note names the opposite posture).

### Phase 2: Per-identity prerequisite sections in the v1 leaves [ISSUE]

Under the single-home rule, per-class facts belong to each class's own leaf. Each of the ten `v1`
leaves gains a prerequisites section deriving its identities' needs — Access class, isolation
floor, connector entitlements (and which rung owns each), per-posture divergences — through the
P1 vocabulary.

- ADR-0004 incumbent evidence (restate inline in the issue): "prerequisite" in the leaves today
  means only the floor/connector consequence inherited from the catalog
  (`routines.md:122-133`); identities exist only as leaf prose (e.g.
  `plugins/autonomy/reference/routines/doc-freshness-sweep.md:75-76` names
  `doc-freshness-sweep/advisory` and `/docs-change` in a paragraph;
  `ci-health-review.md:51` likewise) — no leaf carries per-identity repo-needs data, and no
  other surface may (single-home).
- Posture-divergent classes must show different prerequisite sets — the grain argument made
  concrete.
- The isolation floor and `executor_class` merge cap are cited from the guardrail slice, never
  re-derived.
- `join:` and `not-a-routine` rows gain nothing (no leaves; out of domain).
- Version bump + CHANGELOG: the same bump assertion pair as P1.
- Sanity: `ls plugins/autonomy/reference/routines/*.md | wc -l` prints 10 (count floor — a
  zero-match glob must not pass), and `grep -L '^## Prerequisites'
  plugins/autonomy/reference/routines/*.md` prints nothing; at least one leaf shows per-posture
  divergence (two postures, two different prerequisite sets).

### Phase 3: The generated identity-and-prerequisite emission [ISSUE]

The bridge the resolver needs and the single-home rule forbids authoring twice: one
machine-readable emission (JSON, in-plugin, generated) listing every `v1` identity with its
derived prerequisite set, **generated from the leaves** with a `--check` drift gate — the same
generate-plus-check pattern the catalog generator established. The leaves stay the authored
single home; the emission is derived output, versioned in-plugin so the resolver and CI consume
it without parsing prose; drift between leaves and emission fails CI.

- ADR-0004 incumbent evidence (restate inline in the issue): no structured identity registry
  exists — `scripts/generate-catalog.mjs` builds `docs/CATALOG.md` from plugin manifests and
  never sees routine identities; the only structured posture-qualified identities in the tree
  are security-binding test fixtures. The generate-plus-`--check` drift-gate shape is the
  incumbent pattern being reused, not a new mechanism.
- The emission is a generated in-plugin artifact, not consumer configuration: no new config-file
  family, and consumers other than the resolver and CI are out of scope.
- Generator + `--check` mode ship with a co-located `*.test.sh` and manifest, per the plugin's
  existing conformance-script shape.
- Exec bit via `git update-index --chmod=+x` for any new shebang file (the exec-bit gate is
  repo-wide and ungated; on Windows `core.filemode` is false and `git add` records 100644).
- Version bump + CHANGELOG: the same bump assertion pair.
- Sanity: the `--check` mode exits non-zero on a hand-edited emission (drift fixture) and 0 on a
  regenerated one; every identity named in a leaf appears in the emission and vice versa.

### Phase 4: The deterministic resolver [ISSUE]

The script core (incumbent shape: Node `.mjs` beside the setup skill's existing conformance
scripts): resolves the verdict set for the `v1` identities on a named surface, with no agent
session, reading the P3 emission — never leaf prose.

- ADR-0004 incumbent evidence (restate inline in the issue): no repo-prerequisite probe script
  exists — the only shipped probe surfaces are the isolation-substrate probe template
  (`plugins/autonomy/skills/setup/templates/isolation-probe.md`) and tool-level flag probes
  elsewhere in the fleet; composition targets, not rivals: the toolchain seam
  (`plugins/toolchain/README.md:10` — the surface others compose "instead of baking their own
  tables"), the tracker seam (`plugins/work-items/tools/work-item-tracker/CONTRACT.md:20`
  binding; `:86,:97` adapter `capabilities.json`), the `claude-config` MCP-enablement audit, and
  the setup skill's own slices.
- Probes: repo-file and harness-context classes; composition reads of
  `.claude/autonomy/binding.json` (declared sections), `.claude/ecosystems/*.yaml` (**resolved**
  state per the ecosystem-commands convention — `enabled: false` is not configured; uncommitted
  layers report unresolvable), `.work-item-tracker.json` + adapter `capabilities.json`,
  `.mcp.json` (presence and enablement gate reported separately, enablement via the
  `claude-config` seam where installed). Machine-context probes only behind an explicit surface
  argument; results surface-qualified.
- Output: per-identity verdict + per-signal provenance (probe + surface, or declaration + rung).
  The emission excludes wall-clock fields (timestamps, durations) so reproducibility is
  byte-comparable; never persists a verdict; never writes any config.
- Every cross-plugin read presence-gated with the documented fallback per seam-phrasing; absence
  is a verdict input, not an error.
- Liveness-assertion on-touch statement: the resolver is an engine surface — it names its
  taxonomy row and satisfies fail-loud (non-zero exit on internal failure, never a
  verdict-shaped fallback).
- Fixtures (before the resolver), each consumed by the co-located `*.test.sh` + manifest so the
  orphaned-fixtures gate passes: fail-closed; declared-beats-detected; divergence-report;
  posture-divergence; positive-verdict (fully-provisioned tree yields the positive verdict with
  provenance); bare-repo (all verdicts `unknown`/`unsupported`, honest non-skip assertions — the
  discriminating-skip gate polices `skip_case` in `plugins/**/*.test.sh`).
- Exec bit, shell-portability, ShellCheck as in P3.
- Version bump + CHANGELOG: the same bump assertion pair; evals if SKILL.md changes.
- Sanity: two consecutive runs on the same tree and surface emit byte-identical verdicts
  (wall-clock-free emission); the six fixture assertions pass via the co-located test harness;
  `scripts/check-changed-skills.sh origin/main` and `scripts/check-orphaned-fixtures.sh --check`
  exit 0.

### Phase 5: The setup slice [ISSUE]

Extends the autonomy setup skill per its own extension model: `check` reports the resolved
verdict set with provenance; `apply` runs the interactive propose→ratify loop — the prose-context
pass reads CLAUDE.md/AGENTS.md/README to propose declarations into **non-security keys only**,
the human ratifies, and the slice writes the new binding section additively (absent-section
tolerance holds). The section **references existing scheduling-surface ids and declares no
`surfaces` map of its own** — the envelope conformance check merges every section's `surfaces`
map and duplicates are ambiguous.

- ADR-0004 incumbent evidence (restate inline in the issue): the setup skill's five shipped
  slices (telemetry, capture, trigger/dispatch, guardrail, routine) are each discovery-first,
  detect-diff-reconcile (`plugins/autonomy/skills/setup/SKILL.md:233-240`); none resolves
  per-identity prerequisites. The routine slice's enablement section (`routines.enabled`, keyed
  by full routine identity, `SKILL.md:419`) is the narrowing target this slice feeds.
- Detect-diff-reconcile: an existing declaration is authoritative input to reconcile against;
  divergence from probe results is a finding, never a silent overwrite.
- Narrowing-only enablement: an identity may be enabled only when its verdict clears;
  `unknown`/`unsupported` routes to the advisory path. The slice **prepares** any
  security-binding change and never writes that surface.
- Org-rung entitlements are interviewed, never auto-written: report which prerequisites await
  the org rung and stop.
- Non-interactive contexts skip ask-and-persist rungs and report assumptions (topic-docs rule,
  cited).
- Liveness-assertion on-touch statement for the extended setup `check`, per that contract's
  engine-surface obligation.
- Version bump + CHANGELOG: the same bump assertion pair; evals cover the new slice paths.
- Sanity: a fixture binding with a declaration contradicting a probe produces a reconcile
  finding, not a silent overwrite (asserted in the co-located test harness); `check` on a bare
  repo reports every identity `unknown` or `unsupported` with no error;
  `scripts/check-changed-skills.sh origin/main`, `scripts/check-orphaned-fixtures.sh --check`,
  and `node plugins/autonomy/skills/setup/scripts/check-signal-envelope.mjs` (against the
  fixture binding carrying the new section) all exit 0.

### Phase 6: Graduate the durable outcomes and prune the contract slice [TERMINAL — this PR]

The prune gate fails on this branch until this phase runs, by design: this slice matches no
baseline line and the baseline is read from the base revision (`check-contract-slice-prune`).

- Graduate the resolution-contract decision to an ADR (per-identity-per-surface grain;
  declared-over-detected composition of owning surfaces; fail-closed; narrows-and-adds-no-
  enforcement; configured≠working; no cached profile; generated-emission bridge; the five-way
  naming disambiguation) — hard to reverse once implemented against, surprising without context,
  and the product of real trade-offs with named rejected alternatives. The ADR title and every
  filed issue title use "prerequisite resolution", not "capability detection" — the topic slug
  alone keeps the promoting issue's original name.
- File Phases 1-5 as tracker issues, each restating its inlined `path:line` incumbent evidence,
  work items, and sanity checks; the P1 issue is explicitly marked blocked on the naming ruling
  at filing time. File the reuse-or-replace follow-up (discovery's `ecosystem-discovery.md`
  duplicates the toolchain signal vocabulary) as its own issue, outside this plan.
- Paste this PLAN into the PR body inside a `<details>` block. The durable record is the
  graduated artifacts themselves — the ADR and the filed issues; the recovery pointer for the
  pruned files uses the Contents-API-by-SHA form (`ref=<pruning-commit>^`, topic-docs lifecycle
  step 5), never a `git show <branch-sha>:<path>` form — this repo squash-merges and deletes head
  branches, so branch-SHA pointers die with the branch (#2699).
- A final commit deletes `docs/topics/routine-capability-detection/`.
- Sanity: `bash scripts/check-contract-slice-prune.sh --check-diff origin/main` exits 0 after the
  prune commit (it fails today, naming exactly this slice's file — verified); `bash
  scripts/check-contract-slice-prune.sh --check` exits 0 (must-not-regress: it passes today too,
  since this slice never had a baseline entry — listed to catch an orphan line, not as proof of
  the prune); `ls docs/topics/routine-capability-detection/ 2>/dev/null` returns non-zero; the
  PR body contains the pasted plan.

---

### Blast radius

**LOW for this PR** (one ADR added, one slice pruned; no plugin, contract, or CI surface
changes). **MEDIUM for the filed implementation phases**: they extend one plugin's reference and
setup surfaces behind additive schema tolerance, with no breaking change to any consumed format;
the risk concentrated in P5's binding writes is bounded by detect-diff-reconcile, narrowing-only
enablement, the no-own-`surfaces`-map rule, and the org-rung/security-axis exclusions.

### Alternatives considered

| Alternative | Why rejected |
|---|---|
| Free-standing repo profile artifact | Re-opens interpretation at every consumer; the consuming question is per-identity |
| Class-grain verdicts | Cannot express posture divergence, which is exactly where prerequisites diverge; every consuming artifact is identity-keyed |
| Flat (surface-blind) signals | A capability on one surface says nothing about another; the setup contract already states per-surface detection |
| Resolver parses leaf prose | Non-reproducible and violates the prose bar; the generated drift-gated emission keeps leaves the single home |
| Hand-authored machine registry beside the leaves | Second authored home for leaf-owned facts; single-home violation the generated emission avoids |
| Detected beats declared | Against fleet ladders and external consensus; staleness surfaces as divergence findings instead |
| Self-contained prober with own signal tables | Re-implements owned probes; forks the toolchain vocabulary the way discovery's `ecosystem-discovery.md` already did |
| Reading sibling-plugin bundled files | Barred: no sibling-plugin imports; the consumer surface is the seam |
| Cached capability profile with TTL | No fleet precedent; the healthy-while-dead shape; external consensus recomputes per run |
| Fail-open on missing signal | The guard plugins' session-auth posture — correct there, an unauthorized autonomous run here |
| Resolution as admission data | A repo-local input to a protected path is the agent-writable bypass the classification obligation forbids |
| New `.claude/capabilities.*` config family | Second home for admission-adjacent facts; binding.json sections are additive by design |
| Parse conventions out of CLAUDE.md/AGENTS.md at run time | Prose is never runtime authority; agent-writable prose can never satisfy an admission-adjacent input |
| Per-class facts in the contract doc | Single-home violation; leaf-owned data |
| Keep "capability" in the contract term | Five incumbent collisions, including the autonomy plugin's own internal vocabulary |
| New plugin or new skill | The philosophy's design boundary; the setup skill's slice model is the sanctioned extension seam |

### Test strategy

Docs-shaped phases carry grep-shaped sanity checks (stated per phase, with count floors where a
zero-match glob would pass vacuously); the emission and resolver phases are fixture-first — the
drift, fail-closed, declared-beats-detected, posture-divergence, and positive-verdict fixtures
exist before the code does, each consumed by a co-located `*.test.sh` + manifest so
`check-orphaned-fixtures.sh` passes; the slice phase asserts reconcile-not-overwrite plus the
envelope check on a fixture binding. The four change-set-wide gates and the reviewer-judged
forbidden-metric sweep run in every phase PR (Phase spine). Checks that are trivially green on a
given phase's diff are labeled must-not-regress, never presented as proof.

### Risks and mitigations

| Risk | L | I | Mitigation |
|---|---|---|---|
| Output tokens drift into health or security-binding claims | Med | High | Barred-token constraints; single human naming ruling before P1 |
| A repo-local declaration asserts an org-rung prerequisite | Med | High | Per-rung ownership in the contract; P5 interviews instead of writing; admission stays fail-closed regardless |
| Probe false positives (configured-but-dead surfaces) | High | Med | configured≠working vocabulary; consuming routines own health; on-touch statements per engine surface |
| Stale verdict governs a standing routine | Med | High | Recompute at every consumption; no persisted verdict is authority |
| Leaves and emission drift apart | Med | High | Generated emission with `--check` drift gate in CI |
| Resolver ships hardcoded-`unknown` | Med | High | Positive-verdict acceptance criterion + fixture |
| Composition seam absent (no tracker binding, no ecosystems file) | High | Low | Presence-gate + documented fallback per seam-phrasing; absence is a verdict input, not an error |
| Surface qualification collapses into a flat answer | Med | High | Per-(identity, surface) grain in the contract; the setup skill's per-surface doctrine cited |
| New binding section breaks envelope conformance | Med | Med | References existing surface ids; declares no own `surfaces` map; envelope check in P5 sanity |
| Term collision confuses readers | Med | Med | Five-way disambiguation note; "prerequisite" is the catalog's own noun |

### Open questions

- **ROUTED TO HUMAN — the naming ruling.** One ruling covers: the four verdict tokens
  (provisional `supported / supported-with-conditions / unsupported / unknown`), the
  deferred-class marker, and the contract noun and artifact filename (provisional "routine
  prerequisite resolution" / `prerequisite-resolution.md`). Five incumbent collisions constrain
  it: `binds` (ratified security-binding entry), the guard plugins' fail-open "capability
  detection", autonomy's own internal "capability" vocabulary, loop-lane capability tiers, and
  the catalog's `DET`/`AGT` judgment verdicts. The P1 issue is filed blocked on this ruling.
  This is a genuine open question, not an agent-settled one.
- No other question blocks this PR; the remaining human decisions are implementation-time gates,
  listed below.

### Handoff to implementation

#### User-approval gates (decisions this spike does NOT make)

- **The naming ruling** (Open questions) — before P1's contract text is written.
- **P1's contract-document text** — the contract fixes vocabulary future resolvers implement
  against; a human reviews before it merges.
- **P5's binding-write surface** — the slice writes a tracked team file; the propose→ratify loop
  puts a human on every declaration, and the slice ships only after that flow is reviewed.
- **Org-rung entitlement declarations** — org-policy decisions, interviewed at setup time, never
  auto-written.
- **Whether prerequisite verdicts should ever feed the security binding mechanically** — deferred
  with a trigger: revisit if a class's admission entry wants to key on a verdict; today the
  resolution narrows an existing enforcement input and adds none.

#### Mechanical work

- Commit per phase; surgical `git add` of named paths only; commit messages via stdin heredoc.
- Each `plugins/**` phase verifies its version bump + CHANGELOG before opening its PR (the bump
  assertion pair, never `--check-bump` alone).
- PR bodies: native closing keyword (or `No linked issue`) + non-empty `## Related`.
