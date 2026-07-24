# Context engineering for Claude 5 — source absorption and rightsizing runbook

## Brief

Status: **in progress** — shape decided in principle (a runbook), detector design open.

### TLDR

Absorb "The new rules of context engineering for Claude 5 models" into this marketplace and turn it
into something re-runnable against a repo or folder, starting with this repo. Most of the source is
already enforced — by `/doctor` and by `claude-config:audit-instructions`. The value is a **runbook**
that applies every relevant existing skill in a fixed order, plus detectors for the four gaps
nothing covers.

### The four documents

- [design/article-sections.md](design/article-sections.md) — the source decomposed into 15 sections,
  every paragraph and claim, nothing dropped
- [design/official-corroboration.md](design/official-corroboration.md) — each claim checked against
  documentation fetched 2026-07-24, marked confirmed / partly confirmed / `OPINION`-tier
- [design/coverage-matrix.md](design/coverage-matrix.md) — each rule against the incumbent that
  already enforces it
- [design/skill-inventory.md](design/skill-inventory.md) — 60 plugins, 178 skills: which are
  instruments of the pass, which are only targets, and the workload that inventory exposes

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
2. Which detectors extend an existing skill versus become new ones — the homing map, task #33.

### Acceptance criteria

- Pointed at this repository, the pass applies every check the inventory names in one ordered run,
  with no step silently skipped and no surface silently excluded — in-repo worktrees excepted, and
  named when dropped.
- Every source section maps to either a check that runs, an incumbent that already covers it, or an
  explicit recorded exclusion — traceable back to
  [design/article-sections.md](design/article-sections.md).
- A rerun over an unchanged tree produces the same **mechanical-tier** finding set, never a different
  one. A rerun after accepted fixes produces a strictly smaller one. Absent a change to the tree, the
  set grows again only when the anchored catalog is bumped — a skill authored between runs
  legitimately grows it, and the tree is moving under a parallel session. That is the acceptance test
  for "regular audit"; task #35 specifies it, including the finding-identity function that makes "the
  same set" diffable.
- **Behavioral-tier findings are held to a stability property, not to identity.** The existing
  catalog defines the tier as one whose "ground truth is observed model behavior, so findings ship as
  proposals verified by the delete-and-watch loop, never confident removals" — detection is a model
  judgement, so two runs over an identical tree may legitimately differ. A finding-identity function
  normalizes how a finding is *reported*; it cannot make the *detection* deterministic. Behavioral
  findings are therefore reported in a separate section, excluded from the diff-clean gate, and held
  instead to: no behavioral finding contradicts an accepted suppression, and the behavioral set does
  not grow on an unchanged tree by more than a stated tolerance. Task #35 sets the tolerance.

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
  owner doc before a second plugin adopts it. Fleet audits check conformance per row." The catalog is
  such a convention and four plugins adopt it, so the owner doc and its registry row precede adoption.
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

- **Sanity Check:** for each of the eleven page slugs (`skills`, `plugins`, `plugins-reference`,
  `hooks`, `sub-agents`, `tools-reference`, `claude-directory`, `debug-your-config`,
  `large-codebases`, `settings`, `context-window`),
  `rg -c "docs/en/<slug>" design/official-corroboration.md` returns ≥ 1. Counting `https://` lines
  does not work — a line may carry two URLs.
- **Sanity Check — the list itself is falsifiable.** The check above can only prove the slugs it
  already names were fetched; it cannot notice a page nobody listed. Before closing the phase, walk
  `https://code.claude.com/docs/llms.txt` and record every page whose subject is an instruction,
  memory, or configuration surface as fetched or explicitly out of scope with a reason.

**Outcome.** All eleven slugs are recorded in `design/official-corroboration.md` and both sanity
checks pass. The `llms.txt` walk covered all 172 listed pages and surfaced three the eleven-slug list
had missed — `features-overview`, `output-styles`, and `mcp` — which were fetched rather than
deferred. Two findings change what later phases are built against, and both are carried into
Phase 2.5 rather than resolved here:

- **`features-overview` already prescribes D7's routing.** Its "Compare similar features" section is
  official guidance on choosing between `CLAUDE.md`, `.claude/rules/`, and skills, including the
  200-line rule and the enforcement boundary between an instruction and a hook. D7 must show what it
  detects beyond restating that page.
- **Output styles are an unenumerated instruction surface.** They modify the system prompt directly,
  default to *removing* Claude Code's built-in software-engineering instructions, ship from plugins in
  an `output-styles/` directory, and can override the operator's selection via `force-for-plugin`.
  D1's surface partition is incomplete without them.

### Phase 2: Resolve the cross-plugin criteria seam [TODO]

Review: architecture

The design-resolution document names four surviving shapes: artifact contract in the consumer
project, catalog owned by one plugin and passed as an invocation argument, no shared catalog with
each plugin owning its own criteria, or a canonical repo-level source materialized per carrying
plugin by a sync script. Pick one, write down why, and state what drift risk the choice accepts.
This is the load-bearing decision — every later phase inherits it.

**Shape 4 is the starting position, not merely an option.** It is the mechanism this repository
already runs three times — `standards-contract.md`, `hook-utils.sh`, `artifact-protocol.md` — two of
which hold convention-registry rows. It keeps the catalog marketplace-owned, keeps every check
standalone-useful, and converts drift into a CI failure. A shape other than 4 must say what it buys
that is worth giving those up. The evidence and the price are in
[design/design-resolution.md](design/design-resolution.md).

Consequences the decision record must carry explicitly rather than discover later:

- Under the consumer-artifact shape, `claude-memory` and `docs-hygiene` gain a consumer-project
  configuration surface and neither has a `setup` skill (verified: `claude-config`, `skill-quality`,
  and `plugin-quality` do). A conforming `setup` skill becomes mandatory for both.
- A catalog path inside another skill's `reference/` directory is a private surface. Reaching it from
  outside is exactly what `docs-hygiene:audit-encapsulation` exists to detect. This is the
  invocation-argument shape's problem; under shape 4 each plugin reads only its own
  `${CLAUDE_PLUGIN_ROOT}/reference/`.
- Under shape 4, one catalog bump bumps every carrying plugin together, because
  `sync-standards-contract.sh --check-bump` is the precedent and it gates on the manifest version,
  the frontmatter semver, and a new CHANGELOG entry. That release coupling is the price and belongs
  in the decision record, not in a later surprise.
- Whatever the shape, a byte-identical copy landing in a second plugin trips
  `check-cross-plugin-source-drift.sh --check` as an unregistered cluster —
  `reference/criteria.md` is not in that script's skip list. Registering the cluster behind a
  dedicated sync script is the repository's sanctioned resolution.

- **Sanity Check:** `design/seam-resolution.md` exists, names the chosen shape, cites
  `PLUGIN-PHILOSOPHY.md` "Design boundary", and records why each of the other three was rejected —
  `rg -c "rejected" design/seam-resolution.md` ≥ 3.
- **Sanity Check:** `/docs-hygiene:audit-encapsulation` run against the chosen seam reports no
  encapsulation violation.

### Phase 2.5: Proportionality gate — which detectors survive [TODO]

Runs before Phase 3 and Phase 5, because it decides what those two phases are built against. A
catalog and a homing map sized for seven detectors are the wrong artifacts if three of them are
calibration inputs to incumbents.

The seven detectors are not equal-weight, and the plan's own evidence says so.
`design/coverage-matrix.md` ranks the four gaps and finds only one justifies new surface: S3,
cross-surface instruction conflict, which is `ANTHROPIC-DOCS`-backed (the memory doc prescribes the
review under "Consistency" and repeats it in troubleshooting) and which no incumbent performs. The
matrix files the other three as *"authoring guidance, not an auditable defect"*, *"plausibly a check
added to `skill-quality:check`"*, and *"calibration refinements to incumbents, not standalone
surface"*. `design/official-corroboration.md` lands independently on the same set: the interface half
of S6, the S8 placement rule, the S13 carve-out, and artifacts-as-references are all `OPINION`-tier,
unconfirmed by any fetched page.

Those two documents were produced from different inputs and agree. So D1 is a first-class new
detector; D2–D5 are the weak gaps and the `OPINION` set at once. Assign dispositions accordingly:

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

- **Sanity Check:** every D1–D7 carries one of {detector, calibration input to a named incumbent,
  deferred with a trigger} plus its reason, and no `OPINION`-tier rule is enabled on bare invocation.
- **Sanity Check:** if exactly one detector survives, the decision record states whether the operator
  approved continuing with the full machinery or re-deriving the shape.

### Phase 3: Build the anchored criteria catalog [TODO]

Task #34, shaped by Phase 2. Encode every rule from `design/article-sections.md` with its official
status from `design/official-corroboration.md`, preserving the three axes the existing catalog
already uses (evidence tier, authority, severity) and adding a recheck trigger per source page.
`OPINION`-tier rules are recorded as such, never dropped. Follows
`claude-config/skills/audit-instructions/reference/criteria.md` as the precedent — extend it, sibling
it, or (under seam shape 4) relocate it to a canonical `docs/conventions/` path and materialize
copies back into each carrying plugin. The relocation path makes the pre-flight consumer check below
a hard prerequisite rather than a courtesy, because it moves a live contract surface.

- **Pre-flight consumer check (FIRST work item):** the catalog is a contract surface. `rg` for every
  existing citation of `criteria.md` across `plugins/` and `docs/` before changing its shape; record
  each parse path and citing skill.
- **Second work item — the convention registry.** Write the owner doc and add its row to
  `docs/PLUGIN-PHILOSOPHY.md` "Convention registry" BEFORE any second plugin adopts the catalog. Four
  plugins adopt it in Phase 8; the registry row is the gate they pass through.
- **Sanity Check:** `scripts/check-catalog-coverage.sh` (new, per the repo's `check-*.sh` idiom — 16
  such gates exist) exits 0: it extracts every `S<n>` id from `design/article-sections.md` and asserts
  each appears in the catalog or in the catalog's stated exclusion list.
- **Sanity Check:** the "Convention registry" table in `docs/PLUGIN-PHILOSOPHY.md` gained one row
  whose target path exists on disk.

### Phase 4: Define the re-run contract [TODO]

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
strictly smaller one; behavioral-tier findings carry the delete-and-watch follow-through; the set grows
again only on a catalog version bump or a change to the tree.

- **Sanity Check:** `design/rerun-contract.md` states the identity tuple, the report location rule, the
  state key, the concurrency posture, the per-class suppression surface, the checkpoint property, and
  each idempotence property as a condition a test could assert — not as prose intent.

### Phase 5: Map each check to its owning plugin [TODO]

Task #33. One table: check, owning plugin, disposition, reason — where disposition is `extend`, `new`,
`calibration-input-to-<plugin>`, or `deferred-with-trigger`, per Phase 2.5's verdict. Starting
positions are recorded in task #33. The D4 carve-out is not a check — it is a suppression input every
trimming detector consults, so it needs a home reachable under Phase 2's seam.

- **Sanity Check:** one row per D1–D7 carrying the disposition Phase 2.5 assigned it; every named
  owning plugin exists under `plugins/`; every `extend` and `calibration-input-to-` row names a skill
  directory that already exists and every `new` row names one that does not; every
  `deferred-with-trigger` row names its trigger; no row reads "TBD". A non-empty string is not a
  verified owner.

### Phase 6: Design the detectors and the sweep [TODO]

Review: architecture

Tasks #19, #22–#27 (the seven detector designs) and #28 (the sweep). Each detector needs a
false-positive story before it ships. Naming resolves here via `/naming:name-it-better`, constrained
by the fixed verb meanings.

Detector designs follow Phase 2.5's dispositions: only what survives that gate as `new` or `extend`
is designed here.

**The exclusion set is derived, never hardcoded.** Three classes a fix-capable pass would corrupt,
all verified present:

- **Registered byte-identical clusters** — `scripts/cross-plugin-source-registry.txt` registers
  `hooks/hook-utils.sh` (13 live copies), `reference/artifact-protocol.md`, and
  `reference/standards-contract.md`, each guarded by a dedicated CI drift check. A trim or compress on
  any copy breaks the sync path and reds CI.
- **Vendored upstream materializations** — six `SKILL.md` files under `plugins/*/skills/*/vendor/`.
  Hand-editing an upstream copy is a standing prohibition.
- **Worktrees** — three exist under `.claude/worktrees/`, which is gitignored at `.gitignore:15`. Derive
  from `git worktree list` plus gitignore-awareness; a git-tracked enumeration excludes them for free
  where a filesystem walk does not. The earlier "doubles every count" premise was wrong and is dropped.

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
  contribute to a diff-clean gate. Keep `/doctor`'s output out of the mechanical-tier finding set.

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
surviving check has an owner, the re-run contract
is testable, and the dispatch order is fixed. If Phase 2 chose the consumer-artifact or
no-shared-catalog shape, re-evaluate whether the catalog now warrants its own `/planning:design`
pass before Phase 8.

### Phase 7: Bring the setup-skill corpus to its owner doc [TODO]

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

**Branch split happens here, before the first implementation commit.** Phase 11 requires documentation
and implementation to land as separate PRs; the fork point is the tip of
`docs/context-engineering-claude-5-topic` after Phase 7.

**Conditional work item — new `setup` skills.** If Phase 2 chose the consumer-artifact shape,
`claude-memory` and `docs-hygiene` each gain a consumer-project configuration surface and neither has
a `setup` skill today. Both become mandatory.

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
4. **Then route** the user-scope findings. Every one is a recommendation backfilled through
   `melodic-software/dotfiles` — never an in-place edit.

- **Sanity Check:** two consecutive runs over an unchanged tree emit machine-readable finding files
  whose **mechanical-tier** sections diff clean, per the Phase 4 identity function. The
  behavioral-tier section is held to Phase 4's stability tolerance instead, and any step delegating to
  `/doctor` is excluded from both — a prompt-based delegate cannot contribute to a determinism gate.
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
| The catalog is adopted by four plugins without an owner doc, violating the convention registry | Medium | High | The owner doc and its registry row are Phase 3 work items, gating Phase 8 adoption |
| Design documents are pruned at merge, dangling the catalog's traceability anchors | High | Medium | Phase 11 graduates them or relocates the anchors into the shipped catalog before the prune commit |
| A detector or the sweep self-grades its own output | Medium | High | Phase 6 requires each to name a fresh-context non-fork checkpoint; a fork inherits the parent conversation and is not independent |
| The machinery outweighs the payload: a versioned catalog, a convention-registry owner doc, a seam decision, a re-run contract, and a sweep built to carry one well-grounded detector | High | High | Phase 2.5's proportionality gate runs before the catalog and the homing map are built, demotes D2–D5 to calibration inputs unless a written reason survives the coverage matrix's own verdict, and escalates to the operator if only D1 survives |
| `OPINION`-tier rules mutate a consumer's instruction corpus under the same banner as documented doctrine | Medium | High | The tier is populated for the first time by this work, so this work defines it: disabled on bare invocation, opt-in, with a severity ceiling — Phase 6 |
| Idempotence is asserted over behavioral-tier detection, which is a model judgement and cannot be deterministic | High | High | Acceptance criteria scope the diff-clean gate to mechanical-tier findings; behavioral findings report separately under a stated stability tolerance set in Phase 4 |
| `/doctor` is absent on a consumer machine — `DISABLE_DOCTOR_COMMAND` or `skillOverrides: {"doctor": "off"}` — leaving its half of the surface with no incumbent and nothing built to replace it | Medium | High | Phase 6 treats presence as a prerequisite alongside the version floor; the sweep names the missing capability and states what goes unchecked |
| D1 is blind to the managed-policy `CLAUDE.md` tier and proposes edits to a lower surface whose conflict is with unremovable org policy | Medium | High | Phase 10 inventories three scopes; the managed tier is read-only and never remediated, and its absence degrades cleanly |
| Phase 1's page list omits a load-bearing doc and its sanity check cannot notice | Medium | Medium | Four pages added; a second check walks `llms.txt` and records every instruction/memory/configuration page as fetched or explicitly out of scope |

## Blast radius

**HIGH.** Every plugin and skill in the marketplace is in scope as a target (counts cited by command
in "Standards grounding" rather than transcribed); four plugins are modified as instruments; a new
contract surface is consumed across plugin boundaries; and a fix-capable pass can mutate the
marketplace's own instruction corpus — including, if the exclusion set is wrong, 13 registered
byte-identical cluster copies and six vendored upstream materializations.

## Open questions

- Phase 2's seam choice — the plan's load-bearing unknown. Four shapes now, with shape 4 as the
  starting position.
- Whether D2–D7 survive Phase 2.5's proportionality gate as detectors or land as calibration inputs
  to their incumbents. If most land as calibration inputs, the sweep, the versioned catalog, and the
  convention-registry owner doc are carrying one detector, and the shape of the whole deliverable is
  re-derived at that gate — which is why the gate precedes Phase 3.
- What an `OPINION`-tier finding means to a consumer — default enablement, severity ceiling, opt-in
  mechanism. Undefined today because the tier has never been populated.
- Whether the sweep's dispatch exceeds a session's ceiling and must become a dynamic workflow.
- Naming, deferred to Phase 6 under the fixed verb meanings.

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
