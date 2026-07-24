# Context engineering for Claude 5 — source absorption and rightsizing runbook

## Brief

Status: **in progress** — shape decided (a runbook), seam resolved, proportionality gate closed.
Phases 1, 2, 2.5, and 5 are done; design continues at Phase 3.

### TLDR

Absorb "The new rules of context engineering for Claude 5 models" into this marketplace and turn it
into something re-runnable against a repo or folder, starting with this repo. Most of the source is
already enforced — by `/doctor` and by `claude-config:audit-instructions`. The value is a **runbook**
that applies every relevant existing skill in a fixed order, plus detectors for the four gaps
nothing covers.

### The design documents

- [design/article-sections.md](design/article-sections.md) — the source decomposed into 15 sections,
  every paragraph and claim, nothing dropped
- [design/official-corroboration.md](design/official-corroboration.md) — each claim checked against
  documentation fetched 2026-07-24, marked confirmed / partly confirmed / `OPINION`-tier
- [design/coverage-matrix.md](design/coverage-matrix.md) — each rule against the incumbent that
  already enforces it
- [design/skill-inventory.md](design/skill-inventory.md) — which plugins are instruments of the pass,
  which are only targets, and the workload that inventory exposes. Counts are cited by command in
  "Standards grounding" rather than transcribed here, because they drift
- [design/proportionality-gate.md](design/proportionality-gate.md) — Phase 2.5's record: the D1–D7
  dispositions with per-row evidence, the escalation and the operator's decision, the re-derived
  deliverable shape, the homing map, the `OPINION`-tier policy, and both independent reviews
- [design/seam-resolution.md](design/seam-resolution.md) — Phase 2's record: no shared criteria
  artifact, with shape 4 reversed on four verified findings

### Goal

A repeatable pass the operator points at a repo or folder that applies the source's rules — the ones
official documentation confirms — through the skills that already own each concern, plus new
detectors where nothing does. First target: this repository.

### Settled

- **Scope: everything.** Every section of the source is in scope; no rule is dropped for being
  inconvenient. Rules with no official backing ship marked `OPINION`-tier rather than omitted.
- **Shape: a runbook**, because the concerns are already distributed across `claude-config`,
  `claude-memory`, `docs-hygiene`, `skill-quality`, and `plugin-quality`, and the operator's need is
  that *all of them get applied*, in order, repeatedly, against a named target.
- **`re-anchor:sweep-all-disciplines` is the structural precedent** — a router that fans out
  audit-only lanes and applies corrections in a fixed order. Any runbook here either extends that
  pattern or states why it does not.
- **`/doctor` is the incumbent for the CLAUDE.md half** and improves on Anthropic's cadence. The
  runbook invokes or defers to it rather than reimplementing trim and migrate.
- **Conflict review is officially prescribed but unautomated.** The memory doc tells operators to
  periodically review CLAUDE.md, nested CLAUDE.md, and `.claude/rules/` for conflicting instructions.
  Nothing does it. This is the strongest gap.
- **`@path` imports are a progressive-disclosure anti-fix.** Imported files load at launch. Only
  skills and path-scoped rules defer load. Any "split this up" remediation must name the right
  destination.
- **User-scope surfaces are routed, never edited.** `~/.claude/**` is chezmoi-managed; findings
  there become recommendations backfilled through the dotfiles repo.

### Coordination

A parallel session is revising the `playbooks:fable-5` skill and may update other skills. This work
is deliberately downstream-tolerant: the runbook is what cleans up after that session, so it must
be re-runnable against a moved target rather than assume a frozen tree.

### Constraints

- Fresh-docs mandate governs. Every claim traces to a page fetched this session or a file read this
  session; unverified claims are labeled.
- Nothing ships that `/doctor` already does.
- The plugin-acceptance gate applies: repo-agnostic, `userConfig`-configurable, plugin-form-safe, no
  PII, semver'd, security-reviewed.
- The pass follows its own doctrine — a lightweight guide with progressive disclosure, not another
  always-loaded rule wall.

### Shape — decided

**Two layers, both native to the Claude-configuration plane.**

1. **Individual checks land where their concern already lives.** Each detector extends the plugin
   that owns its surface — `claude-config`, `claude-memory`, `docs-hygiene`, `skill-quality` — and
   becomes a new skill only where no owner exists. Every rule from the source is applied piecemeal
   by whichever skill is the right home for it.
2. **A sweep skill in `claude-config` fans them all out against a named target.** Point it at a
   repository and it runs the whole body of knowledge in one ordered pass. `claude-config` is the
   native home because it already owns the Claude Code configuration plane and because
   `audit-instructions` already builds the surface inventory the sweep needs.

`re-anchor:sweep-all-disciplines` is the structural precedent, not the home: it is session-posture
scoped (what discipline is Claude operating under right now), where this is target scoped (what does
this repository's instruction surface look like). Same router mechanics, different subject.

**Fix-capable, not report-only.** The operating goal is repeated application to a repository, not a
findings report to read. `audit-instructions` stays report-only on its own; the sweep applies. The
human gate moves from per-finding to per-run.

**Re-runnable by design.** Success is hammering the same repository repeatedly and watching the
finding set shrink. That requires the knowledge the sweep applies to be anchored in one versioned
source with explicit staleness triggers — not restated across the skills that consume it.

### Open

1. Naming, once the sweep's surface is drafted (`/naming:name-it-better`).
2. ~~Which detectors extend an existing skill versus become new ones.~~ **Closed** — the homing map
   is discharged in [design/proportionality-gate.md](design/proportionality-gate.md). Two host
   plugins: `claude-config` and `claude-memory`.

### Acceptance criteria

- Pointed at this repository, the pass applies every check the inventory names in one ordered run,
  with no step silently skipped and no surface silently excluded — in-repo worktrees excepted, and
  named when dropped.
- Every source section maps to either a check that runs, an incumbent that already covers it, or an
  explicit recorded exclusion — traceable back to
  [design/article-sections.md](design/article-sections.md).
- A rerun over an unchanged tree produces the same **derived-tier** result, never a different one. A
  rerun after accepted fixes produces a strictly smaller one. Absent a change to the tree, it grows
  again only on a catalog version bump — a skill authored between runs legitimately grows it, and the
  tree is moving under a parallel session. That is the acceptance test for "regular audit";
  [design/rerun-contract.md](design/rerun-contract.md) specifies it, including the finding-identity
  function that makes "the same set" diffable.

  **The tier vocabulary changed, and this criterion changed with it.** It originally scoped the
  diff-clean gate to the `mechanical` tier. Verified against the implementations, that tier cannot
  carry it: `audit-instructions` says its deterministic pre-scan "is advisory… so the lane refines
  every candidate rather than reporting it verbatim", and its Phase C re-judges *every* proposal, so
  no dispatched check reaches the report without model judgment — including `mechanical`-tagged ones.
  And `claude-memory`'s criteria carries 17 checks with **zero** occurrences of `mechanical` or
  `behavioral`, so half the dispatched catalog was never in the vocabulary at all. The **derived**
  tier — the three-scope inventory, the exclusion set, shadowed-definition findings, and raw script
  candidate rows — is what is genuinely model-free, and it is where the exact-equality gate now sits.
- **Judged findings are held to a stability property, not to identity.** Detection there is a model
  judgement, so two runs over an identical tree may legitimately differ; a finding-identity function
  normalizes how a finding is *reported* and cannot make the *detection* deterministic. Judged
  findings are reported separately, excluded from the diff-clean gate, and held instead to: none
  contradicts an accepted suppression, and the set does not grow on an unchanged tree beyond a stated
  tolerance — **whose violation fails the run's self-check** rather than being absorbed by
  recalibrating the tolerance.
- **A surface that silently leaves the inventory fails the gate.** The inventory and exclusion set are
  *in* the derived tier, not scaffolding beneath it, so a scope regression is caught. This is the
  property the original two-tier split could not express, and it matters more than a changed finding:
  a shrinking scope looks like an improving report.

## Plan

**Scale:** large — cross-plugin, new contract surface, 60-plugin blast radius.
**Design tier:** A, sequenced into Phases 2–6 behind a gate, with a proportionality gate at Phase
2.5 that can re-derive the deliverable's shape — see
[design/design-resolution.md](design/design-resolution.md).

### Standards grounding

| Surface | Sections cited | Provenance |
|---|---|---|
| Plugin design | `docs/PLUGIN-PHILOSOPHY.md` — "Design boundary", "Naming", "Native-first", "Component stances", "Setup is explicit and repeatable", "Prerequisites and failure behavior", "Convention registry", "Cross-platform contract", "Fresh-eyes checkpoints" | Repo-owned |
| Catalog placement | `docs/CATALOG-TAXONOMY.md` — "Form rule", "Assignment principle", "Vocabulary" | Repo-owned |
| Repo operating rules | `CLAUDE.md` — fresh-docs mandate, design rules for plugins, branching and PRs | Repo-owned |
| Topic-doc lifecycle | `docs/conventions/topic-docs/` — tier placement and the prune-before-merge rule that governs these very documents | Repo-owned |
| Presence-gated fallbacks | `docs/conventions/seam-phrasing/` — the phrasing every optional cross-plugin invocation uses | Repo-owned |
| Consumer configuration | `docs/conventions/config-cascade/`, `docs/conventions/consumer-config-layering/` — load-bearing if Phase 2 chooses the consumer-artifact shape | Repo-owned, conditional |
| Acceptance gate | `docs/MIGRATION-PLAYBOOK.md` — per-plugin migration gate, plugin-acceptance security review | Repo-owned, read at Phase 11 |

Four grounding findings reshape the plan and are carried as constraints throughout:

- **Horizontal decoupling.** A plugin never imports a sibling's files and an installed plugin reaches
  only inside `${CLAUDE_PLUGIN_ROOT}` — no `../`. A shared criteria catalog cannot simply be read
  across plugin boundaries, and a repo-level doc is unreachable from an installed plugin's cache.
  Phase 2 exists to resolve that seam.
- **Fixed verb meanings.** `audit` and `scan` are read-only, mutating only behind an explicit
  override; `clean` / `tidy` / `fix` mutate. The fix-capable posture must be expressed through one of
  those two shapes, not asserted.
- **The convention registry is a gate, not a courtesy.** "A new cross-plugin convention lands in an
  owner doc before a second plugin adopts it. Fleet audits check conformance per row." This was
  carried as a constraint because a shared catalog would have been such a convention. **It no longer
  binds this work:** Phase 2 chose no shared artifact, so nothing here is a new cross-plugin
  convention and no registry row is owed. The gate itself stands — and ground-truth verification
  found it is currently unheld in practice, with 17 rows covering only 2 of the repository's 5
  materialization mechanisms, which is a finding about the repository rather than about this work.
- **Native-first is a gate on every customization surface.** `InstructionsLoaded`, `/context`, and
  `claudeMdExcludes` are already recorded in `design/official-corroboration.md` as relevant official
  mechanisms. Each is adopted, rejected with a reason, or deferred with a trigger — never bypassed by
  building a filesystem walk instead.

Counts are cited by command rather than transcribed, because they drift and the tree owns them:
`ls plugins/*/skills/*/SKILL.md | wc -l` (181 top-level skills at time of writing),
`find plugins -name SKILL.md | wc -l` (187, the extra six being vendored upstream materializations).

### Phase 1: Finish the fresh-docs sweep [DONE]

Task #18. Gates every subsequent phase: the remaining checks' premises are unverified until the
pages land. Fetch and record in `design/official-corroboration.md`, each with its URL: skills
(progressive disclosure inside a skill, subagent execution, dynamic context injection), plugins and
plugins-reference (manifest schema, `${CLAUDE_PLUGIN_ROOT}` / `${CLAUDE_PLUGIN_DATA}`, `userConfig`),
hooks (`InstructionsLoaded`, prompt-type hook text as an instruction surface), sub-agents (subagent
memory, startup loading), tools-reference (deferred tool loading via `ToolSearch` — the §S7 claim),
claude-directory (surface enumeration).

**Four further pages are load-bearing and were missing from this list.** Each governs a surface the
pass audits or a native mechanism the Phase 6 gate must rule on:

- `debug-your-config` — "diagnose why `CLAUDE.md` or settings aren't taking effect", per the memory
  doc's Related resources. A native diagnostic aimed at this exact subject, so it is a native-first
  candidate for the inventory alongside `InstructionsLoaded` and `/context`, not an optional read.
- `large-codebases` — the memory doc defers to it for "the full layout of root and per-directory
  `CLAUDE.md` files and rules", which is the surface partition D1 compares across.
- `settings` — the settings layers `claudeMdExcludes` merges across, the `claudeMd` managed key, and
  `disableBundledSkills` / `skillOverrides`, which decide whether `/doctor` is present at all.
- `context-window` — where `CLAUDE.md` sits in startup context, and what survives compaction.

- **Sanity Check:** for each of the fourteen page slugs (`skills`, `plugins`, `plugins-reference`,
  `hooks`, `sub-agents`, `tools-reference`, `claude-directory`, `debug-your-config`,
  `large-codebases`, `settings`, `context-window`, `features-overview`, `output-styles`, `mcp`),
  `rg -c "docs/en/<slug>>" design/official-corroboration.md` returns ≥ 1. Counting `https://` lines
  does not work — a line may carry two URLs. The trailing `>` closing the autolink is required: a
  bare `docs/en/plugins` also matches `docs/en/plugins-reference`, and `docs/en/mcp` also matches
  `docs/en/mcp-quickstart`, so either slug would pass without its own page ever being fetched.
- **Sanity Check — the list itself is falsifiable.** The check above can only prove the slugs it
  already names were fetched; it cannot notice a page nobody listed. Before closing the phase, walk
  `https://code.claude.com/docs/llms.txt` and record every page whose subject is an instruction,
  memory, or configuration surface as fetched or explicitly out of scope with a reason.

**Outcome.** All fourteen slugs are recorded in `design/official-corroboration.md` and both sanity
checks pass. The list started at eleven; the `llms.txt` walk covered all 172 listed pages and
surfaced three more — `features-overview`, `output-styles`, and `mcp` — which were fetched rather
than deferred, and the check was widened to the fourteen it now names. Two findings change what
later phases are built against, and both are carried into Phase 2.5 rather than resolved here:

- **`features-overview` already prescribes D7's routing.** Its "Compare similar features" section is
  official guidance on choosing between `CLAUDE.md`, `.claude/rules/`, and skills, including the
  200-line rule and the enforcement boundary between an instruction and a hook. D7 must show what it
  detects beyond restating that page.
- **Output styles are an unenumerated instruction surface.** They modify the system prompt directly,
  default to *removing* Claude Code's built-in software-engineering instructions, ship from plugins in
  an `output-styles/` directory, and can override the operator's selection via `force-for-plugin`.
  D1's surface partition is incomplete without them.

### Phase 2: Resolve the cross-plugin criteria seam [DONE]

Review: architecture — satisfied by a cross-vendor review and a blind derivation, both recorded in
[design/proportionality-gate.md](design/proportionality-gate.md).

**Ran after Phase 2.5, not before it.** [design/design-resolution.md](design/design-resolution.md)
says the Tier A classification and Phase 2's own existence rest on "a versioned criteria catalog
consumed by more than one plugin". Phase 2.5 decides whether there is one, so deciding the seam
first would have decided it against a premise the gate deletes. Information flows one way.

**Outcome: no shared criteria artifact.** Each plugin owns its criteria outright; cooperation is a
presence-gated namespaced skill invocation with a documented standalone fallback — the seam these
two plugins already run in both directions. Shape 4 was the starting position and is **reversed**;
Shapes 1 and 2 are rejected with reasons. Full record, including the drift risk the choice accepts:
[design/seam-resolution.md](design/seam-resolution.md).

Four verified findings reversed shape 4, and every one of them was unavailable when it was proposed:

- **Its cited CI guarantee never fires for this artifact.** `check-cross-plugin-source-drift.sh`
  clusters on the full path-within-plugin, and a criteria catalog lives at
  `skills/<skill-name>/reference/criteria.md` where the skill name differs by construction. Four
  `criteria.md` files exist today at four distinct paths and form zero clusters; `--check` exits 0.
  This plan's own claim that a byte-identical copy trips the check as an unregistered cluster is
  **false** — the skip-list argument was necessary but not sufficient.
- **Relocation breaks a currently-green gate**, and then stops watching: `check-skill.sh`
  existence-checks skill-internal refs, so the move emits `broken skill-internal ref`, while the
  post-move `](../../reference/criteria.md)` form escapes its extractor entirely.
- **Adoption is six to seven registration points**, not one — and one of them, the cluster registry
  entry, is unreachable because no cluster can form.
- **The catalog has no frontmatter to bump.** `Version: 1.0.0` is body prose under an H1; the
  precedent's bump machinery reads a YAML key.

The strongest argument is one no shape analysis had: **the corpus contains no instance of one plugin
reading another's `reference/criteria.md`**, and `docs-hygiene:audit-encapsulation` classifies
`reference/` as private surface. A shared catalog would be the first violation of the encapsulation
contract this repository enforces.

- **Sanity Check — passes.** `rg -c "rejected" design/seam-resolution.md` returns 6 (≥ 3), and the
  document names the chosen shape and cites `PLUGIN-PHILOSOPHY.md` "Design boundary" verbatim.
- **Sanity Check — satisfied by construction, re-asserted at Phase 8.** The design introduces no
  cross-plugin file read, so there is no surface for `/docs-hygiene:audit-encapsulation` to flag.
  Verified by inspection too: every criteria reference in the corpus is same-plugin and relative.
  Running the skill against the implemented result remains a Phase 8 gate.

### Phase 2.5: Proportionality gate — which detectors survive [DONE]

Ran first, ahead of Phase 2. Full record with per-row evidence, the escalation, the operator's
decision, the re-derived shape, the homing map, the `OPINION`-tier policy, the D1 scope answers, and
both independent reviews: [design/proportionality-gate.md](design/proportionality-gate.md).

**Outcome.** One officially-backed new check survives (D1, as I12). One further new check ships
`OPINION`-tier and default-off (D3). Everything else is an edit to a check that already exists.
The escalation condition fired and **the operator approved re-deriving the deliverable's shape**:
the cross-plugin catalog, its convention-registry owner doc, and the sync-script materialization are
dropped; the sweep, the re-run contract, and D1 survive. Two host plugins receive rules —
`claude-config` and `claude-memory` — not four. Nothing lands in `docs-hygiene` or `skill-quality`.

Three findings from the gate that later phases inherit:

- **The gate's own test had to be split in two.** "Does an incumbent already cover it" and "is it
  officially backed" are orthogonal, and the first draft demoted D2 on the second while reporting it
  as the first. Every disposition now names which test it fails.
- **`OPINION`-tier enablement inverts for suppressors.** D4 withholds findings rather than emitting
  them, so defaulting it off deletes the mitigation for this plan's own High/High "detectors flag
  correct constraint as over-constraint" risk and makes trimming strictly more aggressive.
- **D1's detection rule is narrower than "two instructions differ."** Where the official layering
  rule already picks a winner — skills, subagents, and MCP servers override by name — differing
  instructions are a resolved override, not a conflict. The comparison set is the `CLAUDE.md`
  family, hooks, and output styles.

The original phase text follows, retained because the dispositions were assigned against it.

The seven detectors are not equal-weight, and the plan's own evidence says so.
`design/coverage-matrix.md` ranks the four gaps and finds only one justifies new surface: S3,
cross-surface instruction conflict, which is `ANTHROPIC-DOCS`-backed (the memory doc prescribes the
review under "Consistency" and repeats it in troubleshooting) and which no incumbent performs. The
matrix files the other three as *"authoring guidance, not an auditable defect"*, *"plausibly a check
added to `skill-quality:check`"*, and *"calibration refinements to incumbents, not standalone
surface"*. `design/official-corroboration.md` separately finds the interface half of S6, the S8
placement rule, the S13 carve-out, and artifacts-as-references all `OPINION`-tier, unconfirmed by any
fetched page.

**Corrected — the original argument here was an axis conflation and is struck.** It read "those two
documents were produced from different inputs and agree", and used that agreement as evidence. It is
not evidence. The matrix measures *who enforces a rule*; the corroboration document measures
*whether the rule is true*. A rule can be fully confirmed and still be the largest gap — S3 is
exactly that, and S7 is the mirror image — so the two axes run in opposite directions on the rows
that matter most. Nor are they independent inputs: both descend from `design/article-sections.md`.
The dispositions survive on the per-row evidence recorded in
[design/proportionality-gate.md](design/proportionality-gate.md), not on this argument.

So D1 is a first-class new detector; D2–D5 are the weak gaps and the `OPINION` set at once. Assign
dispositions accordingly:

- **D1 is a detector**, and is the deliverable's primary payload.
- **D2–D5 are calibration inputs to their incumbents by default** — a check added to
  `skill-quality:check`, a rule fed to `docs-hygiene:extract-ssot`, a suppression input consulted by
  the trimming detectors — not standalone components. Promoting one to a detector requires a written
  reason that survives the matrix's own verdict on it.
- **D6 and D7 trace to `PARTIAL` remainders the matrix never ranked.** Give each the same
  justification test as D2–D5 before it is treated as new surface.
- **`OPINION`-tier content is disabled by default and opt-in.** The existing catalog declares the
  `OPINION` authority value but has never used it — all eleven seeds are `ANTHROPIC-DOCS` — so no
  consumer has ever had to decide what an `OPINION` finding means. This work is the first to populate
  the tier, and therefore owns defining its default enablement, its severity ceiling, and how a
  consumer turns it on. Shipping `OPINION` rules enabled would let one practitioner's unconfirmed
  preference mutate a consumer's instruction corpus under the same banner as documented doctrine.

**If only D1 survives as a detector, stop and re-derive the deliverable's shape** before Phase 3
builds a catalog. A versioned cross-plugin catalog, its convention-registry owner doc, a re-run
contract, and a sweep are machinery sized for a multi-detector program; carrying a single detector
plus a set of incumbent refinements is a different, smaller artifact. That re-derivation is a
user-approval gate, not an implementation detail.

- **Sanity Check — passes, with the vocabulary corrected.** Every D1–D7 carries a disposition and a
  reason. The three-value vocabulary proved incomplete: D4 emits nothing, so `suppression input` was
  added rather than stretching a bad fit, and the gate says so instead of leaving the up-front claim
  standing. The `OPINION` clause is amended for the same reason — no `OPINION` rule that *emits* is
  enabled on bare invocation, while a rule that *withholds* must be.
- **Sanity Check — passes.** Exactly one officially-backed detector survived; the decision record
  states that the operator approved re-deriving the shape rather than continuing with the full
  machinery, on 2026-07-24.

### Phase 3: Specify the criteria edits [SPECIFIED — execution moves to Phase 8]

Task #34, **re-derived, and then re-sequenced.** There is no new catalog, no canonical relocation,
and no per-plugin materialization — Phase 2.5 deleted the multi-plugin premise and Phase 2 found the
mechanism would not have worked here anyway. What remains is edits to two files that already exist.

**Those edits are implementation, and this phase cannot perform them.** The original Phase 3 built a
*design artifact*; the re-derived one edits `plugins/claude-config/**` and `plugins/claude-memory/**`,
which are live plugin files. Phase 8 is where the branch splits, and Phase 11 requires documentation
and implementation to land as separate PRs — so writing them here would put implementation on the
docs branch and break that rule. The re-derivation created this collision by changing what the phase
produces without changing where it sits.

**Resolution: this phase is discharged as a specification.** The exact per-file edit list below is
the deliverable, and it is executed under Phase 8 on the implementation branch. Nothing is lost and
the phase count does not change; only the commit boundary moves.

**`plugins/claude-config/skills/audit-instructions/reference/criteria.md`**

- New check **I12** — D1, cross-surface instruction conflict, scoped per the gate's narrowing
  (task #19).
- New locality check beside I3 — D3, on the definition-site axis rather than I3's load-timing axis,
  `OPINION`-tier and default-off (task #23).
- **I9's Remediate line extended** with the interface destination — D2, `OPINION`-tier, default-off
  (task #22).
- **I3's Remediate line gains a destination-qualifying test** ("a destination qualifies only if it
  defers loading — `@path` imports do not") **and a move cost** (task #26, non-memory half).
- **A stopping condition on I6 and I8** — D4, default-**on**, per the suppressor inversion
  (task #24).

**`plugins/claude-memory/skills/audit/reference/criteria.md`**

- **One consolidated C3 revision** — D7 and D6's memory half are the same rule. Adds an auto-memory
  destination row, an `@path` non-deferring row, and a per-destination move cost drawn from the
  compaction table the plugin already ships in `reference/official-guidance.md` and no check cites
  (task #27).

Every rule cites its source URL rather than restating doctrine, and carries the catalog's existing
recheck triggers so one staleness event fires all of them. The pre-flight consumer check is **done**
and its result is why the catalog stays put: three parse paths, all bare skill-relative markdown
links in `audit-instructions/SKILL.md`, no script or CI workflow reads the file, and a reverse
`[SKILL.md](../SKILL.md)` back-link in `criteria.md`'s "Output format" section constrains where it
could live at all.

The convention-registry work item is **dropped**: the registry gates a new cross-plugin convention,
and extending one plugin's own reference file is not one. Task #43 decides separately whether the
version stops being body prose and becomes assertable frontmatter.

- **Sanity Check — this phase.** Every `S<n>` id in `design/article-sections.md` maps to a named edit
  above or to a stated exclusion. That is assertable against the specification alone, and it is what
  keeps traceability — an acceptance criterion — from being the thing the smaller shape loses.
- **Sanity Check — carried to Phase 8, where the edits land.**
  `scripts/check-catalog-coverage.sh` (new, per the repo's `check-*.sh` idiom) exits 0;
  `/skill-quality:check` passes for both modified skills; and
  `scripts/check-cross-plugin-source-drift.sh --check` still exits 0, proving no edit accidentally
  created a byte-identical cluster.

### Phase 4: Define the re-run contract [DONE]

Recorded in [design/rerun-contract.md](design/rerun-contract.md). Every work item below is answered
there as a numbered assertion rather than as prose intent, which the phase's own sanity check
demands and which the gate's argument for the sweep now depends on.

The decisions that carry the most weight, because a later phase could plausibly have chosen
otherwise:

- **The anchor is content-derived, never line-derived.** A line number shifts when anything above it
  changes, so a line-anchored identity would churn the whole report on an unrelated edit and destroy
  the property the contract exists to protect.
- **A run never writes into its own scan set**, and the whole property reduces to one command:
  after a run against a clean worktree with no redirect argument, `git status --porcelain` is empty.
- **State is keyed by canonical repository identity plus a worktree discriminator**, so two
  worktrees of one repository on different branches do not share a report — and the working
  directory is never an input.
- **Read-only runs take no lock; applying runs refuse rather than queue**, because a sweep over a
  large tree runs long and a silent queue looks like a hang.
- **Inline suppression is permitted only where the pass may write.** For a file it does not own, a
  chezmoi-managed user-scope file, or a registered cluster copy, suppression is central and keyed by
  finding id — an inline marker in a cluster copy would break the sync path the exclusion set exists
  to protect.
- **The behavioral tolerance is `max(2, ceil(0.10 × |B|))`**, with the floor there so a small
  behavioral set cannot collapse the tolerance to zero and reintroduce identity by the back door.
  It is a starting calibration, and Phase 10 is what tests it.

The original work items follow.

Task #35. Idempotence is the headline acceptance criterion, so it needs a machine-comparable
definition before any detector is designed against it.

- **First work item — the finding-identity function.** "The same finding set" is undiffable while
  findings are prose judgements. Define identity as a tuple (surface path, check id, anchor,
  normalized claim) and emit findings to a machine-readable file so two runs can be diffed rather
  than compared by reading.
- **Second work item — where the run report lives relative to the scan set.** If run 1 writes its
  report into the tree, run 2's tree is not unchanged and the idempotence property is unfalsifiable.
- **Third work item — run-state keying and concurrency.** `${CLAUDE_PLUGIN_DATA}` is machine-global
  rather than per-project, and this machine has three worktrees of this repo under `.claude/worktrees/`
  plus ~96 checkouts under the ghq root. State must be keyed by canonical repository identity, not by
  working directory, and the concurrent-run posture must be stated (a lock, or documented
  last-write-wins).
- **Fourth work item — the suppression surface, per target class.** A deliberately-kept finding must
  not resurface, but "its site" differs by class: a `SKILL.md` this pass does not own; a
  chezmoi-managed `~/.claude/**` file the Brief says is routed and never edited; a registered
  byte-identical cluster copy where an edit breaks the sync path. Decide each before Phase 6 designs
  detectors that read the suppression record.
- **Fifth work item — mid-run resumability.** A run over 181 skills can be interrupted by compaction,
  a rate limit, or a crash. Findings persist incrementally as collected, and an interrupted run
  resumes from the last completed lane rather than restarting.

Then the properties themselves: unchanged tree yields an identical finding set; accepted fixes yield a
strictly smaller one; judged-tier findings carry the delete-and-watch follow-through where their host check defines one; the set grows
again only on a catalog version bump or a change to the tree.

- **Sanity Check:** `design/rerun-contract.md` states the identity tuple, the report location rule, the
  state key, the concurrency posture, the per-class suppression surface, the checkpoint property, and
  each idempotence property as a condition a test could assert — not as prose intent.

### Phase 5: Map each check to its owning plugin [DONE]

Task #33, discharged inside [design/proportionality-gate.md](design/proportionality-gate.md) rather
than as a separate artifact — it would have been a seven-row table restating that document's own.

Two corrections the mapping forced, both from reading the incumbents' bodies instead of their
listing descriptions:

- **The D4 carve-out needs no seam.** It was expected to be consulted by trimming rules in three
  plugins. Every `docs-hygiene` trimmer already owns a stopping condition shaped to its own content
  model — semantic-loss revert, always-admitted categories, fact ownership, reasoning-stays-inline —
  and `skill-quality`'s skills remove no content. The gap is `claude-config`'s I6 and I8 alone.
- **`skill-quality:check` hosts nothing.** Its contract is "NO model invocation… reproducible in CI
  or a pre-commit hook", and `argument-hint` is read by nothing in the plugin. A
  representational-equivalence judgement would be the first non-reproducible check in a gate whose
  value is that every check is reproducible.

- **Sanity Check — passes.** One row per D1–D7 with its disposition; both named owning plugins exist
  under `plugins/`; every row names a skill directory that already exists; the
  `deferred-with-trigger` row names its trigger; no row reads "TBD".

### Phase 6: Design the detectors and the sweep [TODO]

Review: architecture

Tasks #19 and #22–#27 (now two new checks plus four edits to existing ones, per Phase 2.5) and #28
(the sweep). Each check needs a false-positive story before it ships. Naming resolves here via
`/naming:name-it-better`, constrained by the fixed verb meanings.

**In progress — the design is in [design/checks-and-sweep.md](design/checks-and-sweep.md).** D1's
detection rule, its five must-not-flag cases, its remediation split by scope, the native-first
inventory ruling, the sweep's posture, its derived exclusion set, the `/doctor` prerequisite
contract, the dispatch order, and the `OPINION` discovery line are all written. Naming is dispatched
and the sweep is carried as `<sweep>` until it lands. Still open there: the report schema, the
suppression file's path and format, the lane decomposition, and whether a shadowed same-named
definition is reported at all.

**One correction that phase drafting forced back upstream.** The first statement of D1's scope
excluded skills, subagents, and MCP servers wholesale because they "override by name". That misreads
the rule — override-by-name resolves a collision between two entities *sharing a name*, where one is
simply inert. It says nothing about a skill body contradicting `CLAUDE.md`, which is the source
article's own headline example. Excluding skill bodies would have excluded the failure D1 exists to
detect. The exclusion is now narrow: a shadowed same-named definition is not a conflict; everything
else that holds instruction text is in the comparison set.

**The sweep is the phase's centre of gravity now, not the detectors.** With one new
officially-backed check, the design work that carries risk is the run contract — the derived
exclusion set, the three-scope inventory, finding identity, suppression, resumability, and the apply
posture. That is also the argument for the sweep existing at all: the checks are delegated, the run
semantics are not, and invoking the incumbents by hand yields none of them. Recorded in
[design/proportionality-gate.md](design/proportionality-gate.md).

**The exclusion set is derived, never hardcoded.** Three classes a fix-capable pass would corrupt,
all verified present:

- **Registered byte-identical clusters** — `scripts/cross-plugin-source-registry.txt` registers
  `hooks/hook-utils.sh` (13 live copies), `reference/artifact-protocol.md`, and
  `reference/standards-contract.md`, each guarded by a dedicated CI drift check. A trim or compress on
  any copy breaks the sync path and reds CI.
- **Vendored upstream materializations** — six `SKILL.md` files under `plugins/*/skills/*/vendor/`.
  Hand-editing an upstream copy is a standing prohibition.
- **Worktrees** — derive from `git worktree list` plus gitignore-awareness; a git-tracked enumeration
  excludes them for free where a filesystem walk does not.

  **The narrative claim here was wrong twice and is now checked rather than asserted.** It read
  "three exist under `.claude/worktrees/`, which is gitignored at `.gitignore:15`". On this machine
  `.claude/worktrees/` **does not exist**, and `git worktree list` reports **26** registered
  worktrees, living in a sibling directory outside the repository entirely. The derivation mechanism
  is robust to both errors — which is the point of deriving rather than transcribing — but a plan
  that audits other people's instruction files for stale unverified counts had a stale unverified
  count of its own, twice, in the paragraph arguing for derivation. Counts here are cited by command
  or not at all.

**The inventory clears the native-first gate first.** Adopt, reject with a reason, or defer with a
trigger: the `InstructionsLoaded` hook ("log exactly which instruction files are loaded, when they
load, and why"), `/context` for confirming what actually loaded, and `claudeMdExcludes` as a
remediation option. Building a filesystem walk without recording that decision fails the gate.

**`/doctor` gets a prerequisite contract, not a hand-wave.** Its trim requires Claude Code v2.1.206 or
later, and it "reports findings first and asks for confirmation before changing anything" — so it is
interactive and cannot be driven by an unattended sweep. State the version floor, classify absence
(required-for-correctness versus optional-feature), and make the handoff an operator instruction
rather than a dispatch.

**`/doctor` is a bundled skill, and a bundled skill can be absent.** The skills doc: `/doctor` is
prompt-based rather than fixed logic, and "before v2.1.205, `/doctor` was a built-in command rather
than a bundled skill." `disableBundledSkills` spares it — but the doc's own escape hatch is "to hide it, set the
`DISABLE_DOCTOR_COMMAND` environment variable or a `skillOverrides` entry of `"doctor": "off"`". Two consequences the plan has to absorb,
because it deliberately builds nothing on `/doctor`'s half of the surface:

- **Presence, not just version, is the prerequisite.** On a consumer machine where `/doctor` is
  turned off, "nothing ships that `/doctor` already does" leaves the entire `CLAUDE.md` trim and
  migrate half with no incumbent *and* no replacement. The design boundary's "report the missing
  optional capability clearly" is the floor: the sweep names `/doctor` as the missing capability and
  states what goes unchecked. Deciding whether to build a fallback beyond that is a Phase 6 call, and
  either answer is acceptable if it is recorded.
- **A prompt-based delegate is not deterministic.** Any step that delegates to `/doctor` cannot
  contribute to a diff-clean gate. Keep `/doctor`'s output in its own delegated tier, out of both the derived and judged finding sets.

**Every detector asserts non-overlap with `/doctor`.** Per detector, against a freshly fetched commands
and memory doc — and the catalog carries a `/doctor` recheck trigger alongside its per-source-page
triggers, because `/doctor` moves on Anthropic's cadence and a one-time judgement decays.

**Fresh-eyes delegation is designed into the artifacts, not left to the invoker.** The sweep's
apply-verify step and each detector's self-check are author-verifier arrangements. Each names its
fresh-context **non-fork** checkpoint — a fork inherits the parent conversation and is not independent
— with the cross-vendor advisor presence-gated per `docs/conventions/seam-phrasing/` and the
same-vendor fresh subagent as the stated fallback.

- **Sanity Check:** each of D1–D7 has a design section naming its detection rule, its remediation, and
  at least one case it must NOT flag.
- **Sanity Check:** every split remediation names a load-deferring destination (a skill or a
  path-scoped rule); no remediation anywhere proposes an `@path` import as a context saving —
  `rg -c '@path'` over the detector designs returns hits only in the stated anti-fix warning.
- **Sanity Check:** the sweep design names its derived exclusion set, its dispatch order, its
  `/doctor` version floor and absence classification, and its non-fork verification checkpoint.

### Gate — re-evaluate before implementation [TODO]

Phases 2–6 are the design. Confirm the seam is chosen, Phase 2.5's dispositions held, every
surviving check has an owner, the re-run contract is testable, and the dispatch order is fixed.

**The conditional `/planning:design` question is already answered: no.** Phase 2 chose the
no-shared-catalog shape, which fires this gate's condition, and the re-derived tier answers it —
that pass was warranted by a *new contract*, and there is no new contract. What remains is D1's
detection rule, the re-run contract, and the sweep's dispatch design, all already sequenced as
phases. Recorded in [design/proportionality-gate.md](design/proportionality-gate.md) under "The
design tier, actually re-derived", and this line closes the same question where
`design-resolution.md` also poses it.

### Phase 7: Bring the setup-skill corpus to its owner doc [AUDITED]

**The audit is done and recorded in [design/setup-corpus-audit.md](design/setup-corpus-audit.md);
the fixes are task #45.** 43 setup skills across 60 plugins: 41 conforming, 2 partial, 0 fully
non-conforming, 4 legitimately check-only with their premises settled from manifests rather than
from the skills' own prose. No setup skill reads a sibling plugin's files.

The two most useful findings are not plugin defects. `context-guard` and `rate-limit-guard` share one
configuration shape — the user's own `settings.json` plus a plugin-owned machine file — resolved two
different ways, and the owner doc sanctions neither; and "non-trivial `userConfig`", which the
requirement gate turns on, is never defined, leaving three plugins' status unanswerable from the
doc's own text. Both are owner-doc fixes that dissolve plugin-level findings.

One duplication decision remains open: a 61-line byte-identical block, about two thirds of each file,
shared by `discovery` and `verification`. It cannot ride the existing cluster registry, which takes
whole files only — extracting it to a per-plugin `reference/` file would make it registrable.

The original phase text follows.

Task #29, **reclassified.** The original framing — extract a new SSOT across the 43 `setup` skills —
is plugin-form-illegal: any single home is either a repo-level doc, unreachable from an installed
plugin's isolated cache, or a sibling-plugin file the design boundary forbids. Spot-checking confirms
the corpus is per-plugin by construction: `plugins/github/skills/setup/SKILL.md` references only
`${CLAUDE_PLUGIN_ROOT}/reference/*`. What is shared is the *shape*, and the shape already has an owner:
`docs/PLUGIN-PHILOSOPHY.md` "Setup is explicit and repeatable".

So this phase audits conformance to that owner doc rather than inventing a second source. Where a
genuinely byte-identical fragment exists, it is a candidate for the existing cross-plugin cluster
registry — the mechanism the repo already uses for `hook-utils.sh` — not for a new extraction.

Gated behind Phase 2 only if it turns out to need the same seam; otherwise file-disjoint from Phases
3–6 and parallel-safe.

- **Sanity Check:** every `plugins/*/skills/setup/SKILL.md` either conforms to the owner doc's shape or
  appears in a written exception list with a reason; any fragment promoted to a shared cluster appears
  in `scripts/cross-plugin-source-registry.txt` and its drift check passes.

### Phase 8: Implement the checks in their owning plugins [TODO]

Review: architecture

Per the Phase 5 map. Each check ships with its criteria citation (never a restatement), its
false-positive carve-out, and evals where the owning plugin's conventions require them.

**Phase 3's specified criteria edits execute here**, on the implementation branch, because they touch
live plugin files. Two further live-file corrections ride with them, both found during design and
neither belonging to the docs branch: the stale path-scoping claim in `claude-memory`'s
`reference/official-guidance.md` (task #47), and the setup-corpus fixes (task #45), whose first two
items are owner-doc changes to `docs/PLUGIN-PHILOSOPHY.md`.

**Branch split happens here, before the first implementation commit.** Phase 11 requires documentation
and implementation to land as separate PRs; the fork point is the tip of
`docs/context-engineering-claude-5-topic` after Phase 7.

**The conditional `setup`-skill work item is dropped.** It was contingent on Phase 2 choosing the
consumer-artifact shape, which it did not: no plugin gains a consumer-project configuration surface,
so neither `claude-memory` nor `docs-hygiene` needs a `setup` skill on this work's account.

**Two plugins are modified, not four** — `claude-config` and `claude-memory`. `docs-hygiene` and
`skill-quality` are targets of the pass, never instruments of it.

- **Sanity Check:** `/skill-quality:check` passes for every skill created or modified; no new skill
  restates catalog content that Phase 2's seam makes citable.
- **Sanity Check — standalone usefulness.** Every new check, invoked with no catalog supplied, runs to
  a documented reduced result and reports the missing optional capability by name. A check that only
  works when the sweep calls it violates "Every plugin remains useful alone", which the
  invocation-argument seam shape makes easy to breach silently.

### Phase 9: Implement the sweep [TODO]

Review: architecture, security

Per Phase 6's design. Cross-plugin invocations are presence-gated with documented fallbacks — a bare
unguarded cross-plugin reference is a defect per the design boundary. Mutation sits behind the
explicit override the naming convention requires.

- **Sanity Check:** every sibling-plugin invocation in the sweep body is inside a presence guard with
  a stated fallback; bare invocation performs zero mutations.

### Phase 10: Reconcile, then run against this repository [TODO]

Tasks #31, #30, #20. Order matters and is not the task order.

1. **Reconcile first.** Diff what the parallel `fable-5` session changed and re-check the affected rows
   of `design/official-corroboration.md` — that skill is both a target of the pass and the doctrine
   source its premises rest on.
2. **Inventory all three scopes before applying any side's fixes.** D1 detects cross-surface conflict;
   it cannot see a repo↔user conflict from a repo-only inventory. `design/skill-inventory.md` names
   `~/.claude/CLAUDE.md` against the 15-skill `re-anchor` plugin as the most likely conflict site, plus
   a `SessionStart` hook injecting a persistent ruleset that no incumbent inventories as an
   always-loaded surface. Inventorying only the repo would apply fixes against half the picture.

   **The managed-policy scope is the third, and no design document names it.** The memory doc places
   an organization-deployed `CLAUDE.md` at `/Library/Application Support/ClaudeCode/CLAUDE.md`,
   `/etc/claude-code/CLAUDE.md`, and `C:\Program Files\ClaudeCode\CLAUDE.md`, plus a `claudeMd` key
   honored in managed and policy settings only. It loads **before** user and project, and "managed
   policy `CLAUDE.md` files cannot be excluded" — `claudeMdExcludes` does not reach it. A conflict
   detector blind to that tier misses the highest-precedence surface, and worse, resolves a conflict
   by proposing an edit to the lower surface when the authoritative side is org policy and the lower
   side is the correct thing to keep. D1's surface partition must therefore carry a read-only,
   never-remediated managed tier whose findings are reported as "conflicts with org policy at
   `<path>`", and the sweep must degrade cleanly when that path is unreadable — the common case on a
   machine without one. This is in scope by default: the pass ships to organizations, not only to
   this machine, where no managed policy file exists today.
3. **Then apply**, repo first: `claude-code-plugins` itself, recording hit rate, false positives, and
   dispatch cost per check.

**This repository cannot exercise every rule, and the gap is measured rather than assumed.** Counted
at `cbf27e88a9`: **0** `@`-imports in the one root `CLAUDE.md` (63 lines) or in `AGENTS.md`
(28 lines); **0** nested `CLAUDE.md` files; **0** files under `.claude/rules/` — the directory does
not exist; **0** files carrying `paths:` frontmatter anywhere in the tree. So D6's two target
defects — `@path`-as-context-saving, and content in a compaction-losing destination that needs to
survive compaction — have **zero instances here**, because the destination class is empty. The repo
also already prohibits the practice in synced text: "Never `@import` (imports expand at launch,
defeating lazy load)" appears at line 211 of three files.

Two consequences. A green dogfood run is not evidence that D6 works — it is evidence the repository
is clean, and the two must not be conflated in the Phase 10 report. And D6 needs a **synthetic
fixture** to be validated at all, which is a Phase 6 design obligation rather than a Phase 10
discovery. The rules still ship: the pass targets organizations, not only this machine, and an
absent defect class here says nothing about a consumer's tree.

Two further counts that shape what the run will surface: 27 of 181 skill bodies exceed 200 lines and
the largest is 499, one line under the hard cap; and 73 of 181 already carry a `reference/` or
`context/` directory, with only 19 genuinely flat — so the progressive-disclosure surface is
narrower than the raw skill count suggests.
4. **Then route** the user-scope findings. Every one is a recommendation backfilled through
   `melodic-software/dotfiles` — never an in-place edit.

- **Sanity Check:** two consecutive runs over an unchanged tree emit machine-readable finding files
  whose **derived-tier** sections diff clean, per the Phase 4 identity function — including the
  three-scope inventory and the exclusion set, so a silent scope regression fails here. The
  **judged-tier** section is held to Phase 4's stability tolerance instead, and exceeding it fails
  the run's self-check rather than prompting a recalibration. `/doctor`'s output is the **delegated**
  tier and is excluded from both — a prompt-based delegate cannot contribute to a determinism gate.
- **Sanity Check:** after an apply, the repo's cross-plugin drift checks still pass —
  `scripts/check-cross-plugin-source-drift.sh`, `scripts/sync-hook-utils.sh --check`,
  `scripts/sync-standards-contract.sh --check` — proving no registered cluster copy or vendored file
  was mutated.

### Phase 11: Acceptance gate and PR [TODO]

Review: security

Tasks #21, #32. `docs/MIGRATION-PLAYBOOK.md`'s per-plugin migration gate and plugin-acceptance security
review; repo-agnostic, `userConfig`-configurable, plugin-form-safe, no PII, explicit semver, catalog
assignment per `docs/CATALOG-TAXONOMY.md` — `claude-code`, since the subject *is* Claude Code and the
taxonomy's assignment principle gives subject priority over activity.

**Graduate the traceability anchors before the prune.** `docs/conventions/topic-docs/` places
`docs/topics/<slug>/` in the contract tier: committed on the task branch only, pruned before merge. But
acceptance criterion 2 requires traceability back to `design/article-sections.md`, and the catalog's
recheck triggers are anchored in `design/official-corroboration.md`. After the prune every such
reference dangles, and `link-check.yml` validates markdown links. Either graduate both documents to the
durable tier through the knowledge-vault seam, or move the traceability anchor and the recheck triggers
inside the shipped catalog. Decide which, and do it before the prune commit.

- **Sanity Check — the repo's contract gate passes**, not a hand-picked subset. Sixteen `check-*.sh`
  gates exist under `scripts/`; the load-bearing ones here are `check-changelog-parity.sh` (all 60
  plugins carry a `CHANGELOG.md`), `check-skill-leaf-names.sh` against `skill-leaf-name-registry.txt`
  (a colliding leaf name must be registered as an owner set — registering a bare name is refused),
  `check-skill-portability.sh`, `check-silent-skips.sh`, `check-orphaned-fixtures.sh`, plus
  `validate-plugin-contracts.mjs` and `generate-catalog.mjs`.
- **Sanity Check:** `plugin.json` version bumped for every touched plugin; the marketplace entry carries
  a category from the documented vocabulary; PR title matches `.github/workflows/pr-title.yml`; the PR
  body carries a closing keyword and a non-empty `## Related` section per
  `.github/workflows/pr-issue-linkage.yml` and `docs/conventions/pr-body-convention/`.
- **Sanity Check:** `rg -o 'design/[a-z-]+\.md'` across shipped plugin files and `docs/` returns no
  reference to a pruned path.

## Test strategy

No runtime code — the deliverables are skills, a catalog, and their evals. Verification is therefore:

- **Catalog fidelity** — every source section maps to a catalog entry or a recorded exclusion,
  asserted by the Phase 3 sanity check against `design/article-sections.md`.
- **Detector precision** — each detector ships with at least one case it must NOT flag, drawn from
  real files in this repo. The `audit-instructions` gotchas are the model: format-steering examples
  are not scaffolding, bare-prohibition rewrites go positive before adding rationale.
- **Idempotence** — the Phase 4 contract asserted by running the sweep twice over an unchanged tree
  and diffing the reports.
- **Structural gates** — `/skill-quality:check` on every new or modified skill; `/plugin-quality:audit`
  on the resulting components.
- **Independence** — findings verified by fresh-context reviewers, never by the context that produced
  them, per `PLUGIN-PHILOSOPHY.md` "Fresh-eyes checkpoints".

## Alternatives considered

| Alternative | Why rejected |
|---|---|
| One new dedicated plugin holding every check | Duplicates the surface inventory `audit-instructions` already builds, forces a second install, and files the same subject under a second catalog entry |
| Extend `re-anchor:sweep-all-disciplines` | Session-posture scoped, not target scoped. Its correctors audit the work in flight; this audits a repository at rest |
| Reimplement the CLAUDE.md trim | `/doctor` already trims, deduplicates, and migrates, on Anthropic's release cadence. The sweep hands off to it |
| Ship every rule the source states as an enforced check | Four rules have no official backing. They ship `OPINION`-tier so a consumer can weigh them, rather than being enforced as doctrine or silently dropped |

## Risks and mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Phase 2's seam forces the catalog into a shape that reintroduces drift | Medium | High | The gate after Phase 6 re-evaluates; shape 3 accepts drift explicitly rather than silently |
| Detectors flag correct constraint as over-constraint | High | High | D4's carve-out is a suppression input every trimming detector consults, designed before any of them ship |
| A fix-capable sweep mutates 181 skills on a bad rule | Low | Critical | Naming convention forces mutation behind an explicit override; bare invocation stays read-only; Phase 10 runs against this repo first |
| The parallel `fable-5` session and this branch diverge | Medium | Medium | Phase 10 reconciles before the first full run; PRs are required and squash-merged, so divergence surfaces at merge |
| Dispatch budget blows past what a session can hold | Medium | Medium | `audit-instructions` already gates near 20 dispatches; dynamic workflows are the documented mechanism above that ceiling — decided in Phase 6 |
| The pass becomes the thing it audits | Medium | Medium | It cites the catalog rather than restating it, and the source's own doctrine applies to it |
| An apply mutates a registered byte-identical cluster copy or a vendored upstream file, breaking a sync path and reddening CI | Medium | High | Phase 6 derives the exclusion set from `cross-plugin-source-registry.txt` + a `vendor/` rule + `git worktree list`; Phase 10 asserts the drift checks still pass after an apply |
| ~~The catalog is adopted by four plugins without an owner doc, violating the convention registry~~ | — | — | **Retired.** Phase 2 chose no shared artifact, so there is no cross-plugin catalog to adopt and no registry row is owed |
| Design documents are pruned at merge, dangling the catalog's traceability anchors | High | Medium | Phase 11 graduates them or relocates the anchors into the shipped catalog before the prune commit |
| A detector or the sweep self-grades its own output | Medium | High | Phase 6 requires each to name a fresh-context non-fork checkpoint; a fork inherits the parent conversation and is not independent |
| The machinery outweighs the payload: a versioned catalog, a convention-registry owner doc, a seam decision, a re-run contract, and a sweep built to carry one well-grounded detector | High | High | **Fired, and the mitigation worked.** Exactly one detector survived, the operator approved re-deriving the shape, and the catalog, the owner doc, the registry row, and the materialization are gone. What survives is the sweep and the re-run contract, whose justification was never detector count |
| `OPINION`-tier rules mutate a consumer's instruction corpus under the same banner as documented doctrine | Medium | High | The tier is populated for the first time by this work, so this work defines it: disabled on bare invocation, opt-in, with a severity ceiling — Phase 6 |
| Idempotence is asserted over detection that is a model judgement and cannot be deterministic | High | High | **Fired, and the first mitigation was itself wrong.** Scoping the gate to the `mechanical` tier did not work: no dispatched check reaches the report without model judgment, and half the dispatched catalog has no tier axis at all. Re-derived into three tiers — derived (model-free: inventory, exclusion set, shadowing, raw candidate rows) carries exact equality; judged carries a tolerance whose violation fails the run; delegated carries neither |
| `/doctor` is absent on a consumer machine — `DISABLE_DOCTOR_COMMAND` or `skillOverrides: {"doctor": "off"}` — leaving its half of the surface with no incumbent and nothing built to replace it | Medium | High | Phase 6 treats presence as a prerequisite alongside the version floor; the sweep names the missing capability and states what goes unchecked |
| D1 is blind to the managed-policy `CLAUDE.md` tier and proposes edits to a lower surface whose conflict is with unremovable org policy | Medium | High | Phase 10 inventories three scopes; the managed tier is read-only and never remediated, and its absence degrades cleanly |
| Phase 1's page list omits a load-bearing doc and its sanity check cannot notice | Medium | Medium | Four pages added; a second check walks `llms.txt` and records every instruction/memory/configuration page as fetched or explicitly out of scope |

## Blast radius

**Still HIGH, but for fewer reasons than before the gate.** Every plugin and skill in the marketplace
remains in scope as a **target** (counts cited by command in "Standards grounding" rather than
transcribed), and a fix-capable pass can mutate the marketplace's own instruction corpus — including,
if the exclusion set is wrong, 13 registered byte-identical cluster copies and six vendored upstream
materializations. That is what keeps the rating where it is.

Two of the original four contributors are gone. **Two plugins are modified as instruments, not
four** — `claude-config` and `claude-memory`; `docs-hygiene` and `skill-quality` are targets only.
And **no new contract surface is consumed across plugin boundaries**: nothing crosses a boundary
except a presence-gated invocation. Recorded rather than silently re-rated, because a blast radius
that never moves is a blast radius nobody is reading.

## Open questions

Three of the five are closed. Kept with their answers rather than deleted, because later phases cite
them.

- ~~Phase 2's seam choice.~~ **Closed:** no shared criteria artifact —
  [design/seam-resolution.md](design/seam-resolution.md).
- ~~Whether D2–D7 survive as detectors.~~ **Closed:** they do not. One officially-backed new check
  (D1), one `OPINION`-tier new check (D3), four edits to existing checks, one deferred —
  [design/proportionality-gate.md](design/proportionality-gate.md).
- ~~What an `OPINION`-tier finding means to a consumer.~~ **Closed:** emitting rules default off with
  an `info` severity ceiling, never fix-applied, and every run reports the tier's existence and the
  argument that enables it; withholding rules default **on**.
- **Open** — whether the sweep's dispatch exceeds a session's ceiling and must become a dynamic
  workflow. Phase 6.
- **Open** — naming, under the fixed verb meanings. Phase 6.
- **Open, new** — whether `mcp-tools:audit` actually covers tool-search configuration. The gate
  defers the "deferred tool loading is unowned" remainder out of scope on that basis, which is a
  negative claim about a body nobody has read. Task #44.

## Handoff to implementation

### User-approval gates

- The Phase 6 → Phase 8 gate: no implementation begins until the design phases land and the gate is
  re-evaluated.
- Any mutation applied to a surface outside this repository, including every user-scope finding,
  which is routed through `melodic-software/dotfiles` rather than applied.
- Phase 2's seam choice, if it lands on a shape that changes what the Brief promised.

### Execution shape

Phases 1 → 2 → 2.5 → 3 → 4 → 5 → 6 are sequential: each consumes the previous phase's output. Phase 7 is
file-disjoint from Phases 3–6 (it touches `plugins/*/skills/setup/`, they touch design documents)
and can run in parallel. Phases 8–11 are sequential and gated.

| Phase | Surface | Basis |
|---|---|---|
| 1 | Main session | Doc fetches feeding a document the main thread owns |
| 2 | Main session | The load-bearing architectural decision |
| 2.5 | Main session | Scope gate with a user-approval escalation |
| 3–6 | Main session | Design work; judgment-heavy, tightly coupled |
| 7 | Sub-agent worker | Mechanical, file-disjoint, 30+ files of the same shape |
| 8 | Sub-agent workers, one per owning plugin | File-disjoint by construction once Phase 5 assigns owners |
| 9–11 | Main session | Integration, security posture, and the acceptance gate |

Phase 7's worker is fenced to `plugins/*/skills/setup/**` and is forbidden PLAN.md, every design
document, and any plugin surface outside `skills/setup/`.

### Mechanical work

Commit at each phase boundary; PLAN.md phase tags advance in the same commit as that phase's output.
PLAN.md edits stay main-session only. Sequential fallback: if a parallel worker reports it cannot
complete or violates its fence, abort that worker and fold its phase back into the main session.
