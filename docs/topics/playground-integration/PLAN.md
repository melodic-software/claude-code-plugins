# playground-integration

## Brief

Signed off by the user 2026-09-01 ("accept all" on the audited answer set: interview rounds 1-2,
blindspot/brainstorm amendments, devils-advocate findings C1/H1-H5/M1-M5/L1-L4, and the
independent per-answer validation). Ledger: `.work/playground-integration/interview-checklist.md`.

Scope change 2026-09-01 (user directive): ALL work — this vertical plus the native-design-surfaces
rides-along — is delivered in this session, on this one feature branch, as ONE pull request. The
previously planned two-PR sequencing collapses to commit ordering within that single PR (engine
extension commits precede verdict-row commits). "Leading PR" below reads as "leading commit
sequence in the single PR".

### TLDR

- Ship one thin wrapper plugin (final plugin AND skill-leaf name deferred, non-colliding with the
  upstream bare `playground` skill) that points to `playground@claude-plugins-official`: install
  uplift, routing, recipes, cloud-session delivery guidance, and consumer-guidance notes. It
  generates nothing itself.
- The wrapper declares the upstream dependency in its manifest
  (`dependencies: [{"name": "playground", "marketplace": "claude-plugins-official"}]`) and this
  repo's root marketplace gains `allowCrossMarketplaceDependenciesOn: ["claude-plugins-official"]`;
  prose install uplift is kept for the contexts where dependency resolution does not run.
- A leading commit sequence extends the audit-native-overlap engine (new first-party-marketplace-plugin native
  class with its `LANES` entry and invariant test, new `upstream-source` observation class, a
  second greppable parity token with its own parity arm, an `--upstream-sha` self-check advisory
  seam) and amends the seam-phrasing convention with a cross-marketplace install-uplift carve-out.
  Only then do the two playground verdict rows land.
- Routing lines: a new `## Boundary` section in `visualization:visualize` (its description is at
  the 1024-char cap) and a description or Boundary line in `prototype:explore-directions` (has
  headroom); presence checks verify provenance via `claude plugin list`
  (`playground@claude-plugins-official`), with any description comparison advisory only.
- A user-run pilot (upstream document-critique over this repo's SKILL.md files, local) plus one
  cloud smoke (publish one generated playground as an Artifact and press its copy button) gathers
  round-trip evidence; learnings may revise wrapper content.
- No upstream contributions of any kind; findings live in this Brief and verdict-row evidence.

### Goal

A marketplace consumer who wants the playground pattern (interactive single-file HTML explorers
whose output is a prompt pasted back into Claude Code) reaches the maintained first-party
implementation through this marketplace in one step, with working guidance for the cases the
upstream plugin does not cover (cloud/remote sessions, this repo's routing conventions, known
rough edges), and this repo's own visualization and prototyping skills know when a request is
playground-shaped and route accordingly.

### Constraints

- Do not reimplement playground generation: no templates, no generator, no competing skill. The
  wrapper points, uplifts, and routes.
- NEVER file issues or PRs to anthropics/claude-plugins-official for the findings in this topic
  (user directive, 2026-08-31). Findings are recorded here and in verdict evidence only. Shipped
  notes are consumer guidance (what to do), never an upstream defect list (what is wrong), and
  every restated upstream fact carries an upstream-drift stamp (claim/basis/as-of/recheck).
- Implementation starts only after the user signs off on the completed `## Plan` section, dated
  (Brief sign-off recorded above does not pre-authorize the Plan).
- All native/first-party-overlap verdicts go through the audit-native-overlap pipeline:
  candidate pairs in its canonical-pair seed, human-gated rows in `docs/native-surfaces/records.json`,
  phrasing per the repo's conventions. The engine extension lands BEFORE any row
  (rows fail validation on current enums), and extends `LANES` alongside `NATIVE_CLASSES` with an
  invariant test asserting every native class has a lane (a class without a lane validates and
  then silently renders nowhere).
- The seam-phrasing convention gains a cross-marketplace install-uplift carve-out (a dated
  amendment; the convention carries no version scheme) in the leading commit sequence; without
  it the wrapper's install commands violate
  "marketplace-qualified IDs never appear in reusable content" and fleet audits would flag them.
- Suggest-install lines only where a recorded verdict backs them, enforced by the new parity
  token; rollout-gated bundled surfaces are never mentioned when absent (existing house rule).
- The wrapper plugin's name AND its skill-leaf name must not collide with or shadow the upstream
  bare `playground` skill; category per `docs/CATALOG-TAXONOMY.md`'s Assignment principle.
- House conventions apply: ai-slop prose rules on all new instruction surfaces (upstream text
  quoted only under `vendor/`), no new hooks, regeneration outputs (`docs/CATALOG.md`, the
  cheatsheet, `docs/NATIVE-SURFACES.md`) regenerated in the same commits that dirty them.
- Upstream verification always uses raw fetches or pinned files, never summarizing fetches (a
  summarizing fetch misreported the upstream marketplace's contents during validation).

### Acceptance criteria

- The wrapper plugin exists in `.claude-plugin/marketplace.json` with a taxonomy-conforming
  category, a README, and one skill; `skill-quality:check` passes on the skill; the upstream
  LICENSE has been read and its terms recorded in the plugin README's provenance note.
- The wrapper's `plugin.json` declares the cross-marketplace dependency and the root
  `marketplace.json` carries `allowCrossMarketplaceDependenciesOn: ["claude-plugins-official"]`;
  implementation empirically verifies install-time resolution AND the failure path
  (`dependency-unsatisfied`, `cross-marketplace` errors) in a consumer-style session before
  merge.
- Context-conditional install behavior: where dependency resolution runs, install is automatic
  and the wrapper documents the error paths; in contexts where resolution does not run
  (synced/cloud/manual), the skill's guidance path emits the install commands with scope
  guidance. Both paths are testable and tested.
- Presence/invocation: with upstream installed, a playground-shaped request invokes the upstream
  skill via the Skill tool; the presence check is provenance-based (`claude plugin list` showing
  `playground@claude-plugins-official`), description comparison advisory only; invocation refusal
  or absence degrades to guidance, never silently.
- Cloud guidance feature-detects each delivery tier (Artifact → SendUserFile → file path) and
  degrades visibly; no tier is asserted as universally available.
- The skill carries the five article recipes plus a repo-native SKILL.md-critique recipe, and a
  `context/` spoke of commit-stamped consumer guidance (theming variance across templates;
  "sanitize any untrusted data fed to a generated explorer"; the document-critique output groups
  that are placeholders at the pinned commit).
- Routing: `visualization:visualize` gains a `## Boundary` section carrying its playground
  routing line (no description edit); `prototype:explore-directions` gains its line within its
  1024-char description headroom or its own Boundary section.
- The engine extension lands ahead of the rows in the commit sequence: new native class + `LANES` entry + class/lane invariant
  test, `upstream-source` observation class, second parity token with its own parity arm,
  `--upstream-sha` advisory in self-check, claude-ops version bump + CHANGELOG + green
  `test_overlap.py`; then the canonical-pair seed carries both playground pairs and
  `records.json` carries the human-approved verdict rows citing commit
  `ed404106fcd80ba98ecb7c851e531dcb626d13b7` and the corpus slice, dated.
- `scripts/affected-tests.sh --run` completes with exit 0 or 3; any exit-3 delegated suites
  (at minimum `test_overlap.py`) are run in their own lanes and pass; the plugin-gate checks
  (`scripts/validate-plugins.sh`, catalog/cheatsheet/NATIVE-SURFACES `--check`, changelog
  parity) pass locally.
- Nothing in the change set proposes, automates, or documents filing anything upstream.

### Captured assumptions

- Consumers can reach `claude-plugins-official`; no air-gapped/offline install path is
  documented in v1 — revisit if a consumer reports an offline or proxy-restricted need.
- Upstream facts are pinned to commit `ed404106fcd80ba98ecb7c851e531dcb626d13b7` (verified still
  HEAD of `main` on 2026-09-01): 6 templates, three output-prompt shapes, dark-only mandate vs
  light+dark diff-review vs light-only code-map, document-critique's placeholder output groups,
  data-explorer's unescaped innerHTML rendering — revisit any dependent wording when upstream
  moves past that commit; the `--upstream-sha` advisory arm makes that event observable.
- The dependency mechanism was verified empirically on 2026-09-01 (isolated HOME, CLI 2.1.251):
  installing the wrapper without the official marketplace succeeds but leaves the plugin
  "failed to load" with the exact remedy command in the error; adding the
  `claude-plugins-official` marketplace auto-installed the dependency ("+ 1 dependency:
  playground") and the wrapper flipped to enabled; the root-marketplace allowlist raised no
  cross-marketplace block. Consequence recorded: this repo's own cloud sessions have no
  official marketplace configured, so `playgrounds@melodic-software` is set `false` in
  `.claude/settings.json` (a recorded enablement decision) rather than shipping a
  perpetually failed-to-load plugin into every session here — revisit if the environment
  gains the official marketplace.
- The pilot runs on the user's local desktop with the upstream plugin as-is, plus one cloud
  smoke (artifact-published playground; copy-to-clipboard inside the artifact sandbox is
  unverified and may reorder the delivery tiers). Pilot learnings may add wrapper enrichments
  but never generation.
- `/plugin marketplace update claude-plugins-official` may be unnecessary ceremony given default
  auto-update for Anthropic marketplaces — verify during the empirical pass before baking it
  into required uplift.

### Out-of-scope

- Building or hardening playground templates, or standardizing the upstream output-prompt
  contract (noted in verdict evidence only).
- Upstream contributions of any kind.
- The design family (design-sync/consent/revoke, /design routing beyond what visualize already
  does) — the V2 vertical owns it.
- Description/listing-budget, spec-conformance, eval, and script-convention work — V3-V7
  verticals.
- A `userConfig` delivery-preference option and an artifact-tier publishing bridge for generated
  playgrounds — deferred; triggers are pilot demand and the V2 vertical respectively.

### Deferred questions

- Q8 — Final wrapper plugin name AND skill-leaf name (non-colliding with the upstream bare
  `playground` skill) — defer until implementation; **arbiter: /planning:plan** (route through
  `/naming:name-it-better`).
- Q9 — Pilot learnings intake (local document-critique run over this repo's SKILL.md files, plus
  the cloud smoke: one artifact-published playground and its copy button; what the results change
  in wrapper content and tier ordering) — defer until the user has run the pilot;
  **arbiter: USER-RESERVED**.

## Plan

Delivery: this session, branch `claude/twitter-thread-discussion-wzynta`, one PR. Commit order
within the PR follows phase order. The native-design-surfaces Brief's items are Phases 5-6 here.
Awaiting the user's dated sign-off on this section before Phase 0 begins.

- **Phase 0 — Naming (resolves Q8).** Run `/naming:name-it-better` for the wrapper plugin name
  and skill-leaf name; both must avoid the bare `playground` token, clear
  `scripts/skill-leaf-name-registry.txt`, and read naturally as `/name:leaf`.
- **Phase 1 — Engine extension (claude-ops).** In `audit-native-overlap/scripts/overlap.py`: new
  native class for first-party marketplace plugins with its `LANES` entry; `upstream-source`
  observation class; a second greppable parity token + parity arm for the new class;
  `--upstream-sha` advisory in self-check (mirrors `--cli-version`). Tests: class/lane invariant
  plus per-feature cases in `test_overlap.py`. Version bump + CHANGELOG entry.
- **Phase 2 — Convention carve-out.** `docs/conventions/seam-phrasing/README.md` gains the
  cross-marketplace install-uplift carve-out, versioned per its own rules.
- **Phase 3 — Wrapper plugin.** New `plugins/<name>/`: manifest with the cross-marketplace
  `dependencies` entry; README with provenance note (read upstream LICENSE first); one skill
  (provenance presence check via `claude plugin list`, invoke-or-degrade, five article recipes +
  SKILL.md-critique recipe, feature-detected cloud delivery ladder); `context/` consumer-guidance
  spoke (commit-stamped); `evals/evals.json`. Root `.claude-plugin/marketplace.json`: plugin
  entry (category per `docs/CATALOG-TAXONOMY.md`) + `allowCrossMarketplaceDependenciesOn`.
- **Phase 4 — Routing.** `visualization:visualize` gains a `## Boundary` section with its
  playground routing line; `prototype:explore-directions` gains its line (description headroom or
  Boundary). No visualize description edit.
- **Phase 5 — Registry + catalog data.** Seed both playground candidate pairs; add records.json
  rows: two playground verdicts (drafted `complementary`, presented to the user for the human
  gate at review), two design-canvas `complementary` rows, one design-family `defer` row —
  evidence citing pinned commit `ed404106` and the v2.1.251 extraction, dated. Refresh
  `visualize/context/decision-matrix.md` design-canvas facts to v2.1.251.
- **Phase 6 — Regeneration.** `docs/NATIVE-SURFACES.md`, `docs/CATALOG.md`, cheatsheet, options
  docs — whatever the touched sources feed — regenerated in the same commits.
- **Phase 7 — Verification.** `test_overlap.py` green; `scripts/validate-plugins.sh` green;
  `check-skill.sh` on the new skill; `scripts/affected-tests.sh --run` (exit 0 or 3 with
  delegated lanes run); ai-slop discipline on new prose; best-effort in-session empirical check
  of the dependency mechanism (documented honestly if the environment cannot exercise it); a
  fresh-context code review of the full diff before the PR opens.
- **Phase 8 — PR.** One pull request from this branch, template-conforming, findings and
  registry rows called out for the human verdict gate; upstream issue-filing nowhere.
