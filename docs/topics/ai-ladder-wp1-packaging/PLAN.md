# ai-ladder-wp1-packaging

## Brief

### TLDR

Packaging and topology for the AI-adoption-ladder machinery (T1–T7 contract set): role-vocabulary
repo topology, one new plugin as the single home composing existing plugin seams, and a
surface-based wiring-vs-advisor principle for guided setup.

### Goal

Every ladder artifact has one owning home named by ROLE in contract text; fleet repo names appear
only in the binding-seam instance doc; the new plugin ships the contract docs and capabilities and
composes existing plugins without duplicating them.

### Locked decisions

| # | Decision |
|---|---|
| D1 | Role vocabulary for repo topology: capability-distribution home, CI-orchestration home, settings-as-code home, org-policy home, runner-execution home (unborn; born only when the T4 build trigger fires). |
| D2 | Contract docs + capabilities ship in the capability-distribution home. Fleet binding: claude-code-plugins marketplace. |
| D3 | GitHub-event adapter splits by role: handler logic = CI-orchestration home (fleet: ci-workflows reusables); enabling settings incl. labels, permissions, runner-policy admission = settings-as-code home (fleet: github-iac). *The parenthesized fleet instances are binding-instance data for the Phase 6 binding doc ONLY — Phase 3's derivation of `role-topology.md` from this row copies the role sentences, never the parentheses; the Phase 5 standing gate fails any leak.* |
| D4 | One new plugin (working name `autonomy`; final name via naming pass) is the single home for: contract docs, guided-setup capability, guardrail-matrix + org-binding seam, sandbox-ladder setup, telemetry contract, return-accounting convention, routine catalog + v1 definitions. |
| D5 | The new plugin composes existing plugin seams — work-items (queue/lease/dispatch), guardrails (deterministic hooks), verification (gates), claude-ops (observability). Orchestration-composing-plugins is the sanctioned model; near-duplicate skill variants are banned. |
| D6 | Wiring-vs-advisor principle: WIRE when the target surface is machine-editable + local + reviewable (repo files, settings, workflow files, IaC code) — wiring always lands as reviewable changes, never silent mutation. ADVISE (steps + cost surfaced) when the surface is org-external, entitlement-gated, paid, or GUI-only. Paid anything = advisory + explicit opt-in first, regardless of wireability. |
| D7 | Adoption starts with discovery/exploration/interview of the adopting org's state — guided-setup owns that phase and never assumes fleet shape. Fleet = first adopting instance (dogfood). |

### Constraints

- Any fleet repo name in normative contract text is a defect; fleet names live only in the
  binding-seam instance doc.
- No new repos until the T4 build trigger fires.
- Plugin format is Claude-Code-specific; contract docs inside remain tool-agnostic markdown any
  org/tool can consume.
- Boris-alignment is the standing acceptance criterion (no step-skipping, trust before scale).
- No new cost without discussion; free defaults, paid = explicit opt-in surfaced first.

### Acceptance criteria

- Contract text names roles only; a binding-seam doc maps each role to the fleet instance.
- New plugin clears the plugin-acceptance gates (plugin validate, contract tests, security review
  per MIGRATION-PLAYBOOK).
- No near-duplicate skill of an existing plugin capability exists in the new plugin.
- Every wiring path lands as a reviewable change.

### Captured assumptions

- Split-later is cheap: renames map is append-only and many-to-one is verified legal, so the
  single-plugin decision is reversible.
- Marketplace distribution suffices for universality: any org can install from the marketplace;
  non-Claude-Code orgs consume the contract markdown directly.

### Out-of-scope (deferred with triggers)

- Runner-execution home creation — trigger: T4 build trigger fires (WP7 owns the design pack).
- Org-enablement track beyond fleet dogfood — trigger: day-job adoption becomes concrete.

### Deferred questions

- Final plugin name + category assignment (category possibly new and broader — not article-tied;
  D22 category vocabulary governs) — `/architect`.
- Contract-doc file layout inside the plugin (docs/ vs skill context/) — `/architect`.
- Per-capability wiring depth — resolved per-package in WP2–WP6 Briefs.

## Plan

Interview-locked this round: plugin name `autonomy`; NEW marketplace category `autonomy`
(singleton, justified by the taxonomy's own singleton-governance clause); WP1 materializes
topology contract docs only (per-capability contracts land with WP2–WP6); guided-setup ships
as a v0 discovery-phase skill; the fleet binding instance lands in the org-policy home
(`melodic-software/standards`) via a separate small PR that merges after the plugin PR.

### Phase 1: Category vocabulary + generator [TODO]

| File | Action | What changes |
|---|---|---|
| `docs/CATALOG-TAXONOMY.md` | Modify | Add `autonomy` to the domain-and-cross-cutting tier — gloss: governed autonomous agent operation (adoption discovery, guardrails, standing routines, autonomy telemetry/return contracts). Singleton justified via the doc's singleton-governance clause (honest distinct label; label predicts member). Trigger-register row: a broader automation plugin lands → broaden or add a sibling category then. |
| `scripts/generate-catalog.mjs` | Modify | Add `autonomy` to `CATEGORY_ORDER` (line 23), position mirroring the taxonomy doc's tier ordering. |

**Sanity Check:**

- `grep -c '\`autonomy\`' docs/CATALOG-TAXONOMY.md` ≥ 1
- `grep -n 'autonomy' scripts/generate-catalog.mjs` shows a `CATEGORY_ORDER` entry

### Phase 2: Plugin scaffold [TODO]

First work item — migration-gate step 1: re-fetch the official plugins/plugin-manifest docs
(fresh-docs mandate) before authoring. Migration-gate step 6 (PII/secrets strip) runs before
the first commit.

| File | Action | What changes |
|---|---|---|
| `plugins/autonomy/.claude-plugin/plugin.json` | Create | v0.1.0, MIT, first-party author. Description scoped to what 0.1.0 ships (topology contracts + adoption discovery) — NOT the full D4 roadmap (no-step-skipping in catalog copy). No fleet repo names. |
| `.claude-plugin/marketplace.json` | Modify | Entry: `source: ./plugins/autonomy`, `category: autonomy`. |
| `plugins/autonomy/README.md` | Create | Shipped capability; D4 seven-capability roadmap as deferred-with-WP-triggers (repo trigger-register idiom); trigger row: role vocabulary changes → update the org-policy-home binding doc. |
| `README.md` | Modify | Regenerated catalog (`node scripts/generate-catalog.mjs`). |

**Sanity Check:**

- `claude plugin validate --strict <repo-root>` exit 0
- `node scripts/generate-catalog.mjs` reports in-sync
- `grep -riE 'melodic-software|ci-workflows|github-iac' plugins/autonomy/ --exclude=plugin.json` returns empty (author metadata in plugin.json is the only allowed occurrence)

### Phase 3: Topology contract docs [TODO]

All three docs in `plugins/autonomy/reference/` are tool-agnostic contract markdown: roles and
surface classes only. Vendor and fleet names banned outright — real instances live in the
org-binding doc (Phase 6); tool-specific materialization details (e.g. the `.claude/autonomy/`
path) live in SKILL.md/README, never in `reference/`.

| File | Action | What changes |
|---|---|---|
| `plugins/autonomy/reference/role-topology.md` | Create | D1 five roles (capability-distribution, CI-orchestration, settings-as-code, org-policy, runner-execution [unborn; birth trigger = T4 build trigger]); D3 adapter split rule (handler logic → CI-orchestration home; enabling settings incl. admission policy → settings-as-code home); D5 composition stance (composes existing plugin seams — work-item queue/lease/dispatch, deterministic guardrail hooks, verification gates, session observability; near-duplicate skills banned). |
| `plugins/autonomy/reference/binding-seam.md` | Create | Binding SHAPE + resolution ladder: repo-local binding override → org binding at the org-policy home → setup interview. Must specify: (a) the org-policy-home pointer persists in repo-local/user-global config and is the prerequisite of rung 2; (b) fetch mechanism = the host CLI with the consumer's own auth; (c) no-org terminal default = repo-local binding + free-tier defaults; (d) written bindings carry a schema-version from v0; (e) known limitation: pointer staleness when an org moves its policy home. Layout convention stated as shape only — one contract doc per capability lands in `reference/` with its owning WP; no future-filename enumeration. |
| `plugins/autonomy/reference/wiring-vs-advisor.md` | Create | D6 verbatim: WIRE when the target surface is machine-editable + local + reviewable, always landing as reviewable changes, never silent mutation; ADVISE (steps + cost surfaced) when org-external, entitlement-gated, paid, or GUI-only; paid anything = advisory + explicit opt-in first, regardless of wireability. |

**Sanity Check:**

- `grep -riE 'melodic-software|ci-workflows|github-iac' plugins/autonomy/reference/` empty
- Vendor deny-list grep empty over `reference/` — `grep -riE 'github|gitlab|bitbucket|slack|anthropic|claude|openai|copilot|cursor|devin' plugins/autonomy/reference/` (surface classes replace all of these; list pairs with PR review for completeness)
- `grep -ci 'reviewable' plugins/autonomy/reference/wiring-vs-advisor.md` ≥ 1 and `grep -ci 'opt-in' …` ≥ 1
- lychee lane passes (anchors valid; no dead cross-links)

### Phase 4: guided-setup v0 skill [TODO]

| File | Action | What changes |
|---|---|---|
| `plugins/autonomy/skills/setup/SKILL.md` | Create | Setup contract (name `setup`, `disable-model-invocation: true`, `check` + `apply` actions, idempotent, non-interactive when complete arguments supplied). Scope: D7 discovery/interview of the adopting org's state (role homes present, substrate availability, budget posture); `apply` writes the discovered binding as tracked config `.claude/autonomy/` — **concern-named from day one** (concern = governed autonomous operation; a plugin split/rename leaves it valid; the versioned `docs/conventions/autonomy/` contract is deferred with trigger: second plugin consumes the config). Enumerated argument surface + pinned headless defaults (free tier everywhere per Brief cost constraint). Seam-2 obligations: `*.local.*` overlay, recommended `.gitignore` line (`.claude/autonomy/**/*.local.*`), user-global → project → local resolution, infer-and-persist convention ladder. Written binding carries `schema-version`. |
| `plugins/autonomy/skills/setup/evals/evals.json` | Create | Warranted (setup precedent: `codebase-health/setup`). Cases: trigger/routing, discovery happy path, no-org terminal default, one non-interactive argument-supplied run, one refusal/guardrail (never assumes fleet shape). |

**Sanity Check:**

- `/skill-quality:check` and `validate-evals` pass with `skills_root` = `plugins/autonomy/skills`
- `claude plugin validate` exit 0
- `grep -c 'disable-model-invocation: true' plugins/autonomy/skills/setup/SKILL.md` = 1

### Phase 5: Acceptance gates (in-repo) [TODO]

| File | Action | What changes |
|---|---|---|
| `scripts/validate-plugin-contracts.mjs` | Modify | Promote the fleet-name sweep to a standing gate scoped to `plugins/autonomy/**`: org token `melodic-software` + bare repo names (`ci-workflows`, `github-iac`), excluding plugin.json author metadata. |

Gate run: `scripts/validate-plugins.sh`; `scripts/run-plugin-tests.sh` (verified: no per-plugin
test file required); `node scripts/validate-plugin-contracts.mjs`; markdown/typos/lychee lanes;
`claude plugin validate --strict`. Migration-gate step 9: clean consumer repo (NOT this repo),
`claude --plugin-dir ./plugins/autonomy`, exercise `/autonomy:setup` on its argument-supplied
non-interactive path — must complete without prompting and write a schema-versioned
`.claude/autonomy/` binding. Near-duplicate audit: statement that no autonomy skill duplicates
an existing plugin capability. Security review: surfaces 2/5/7 untouched; surface 6
reviewed-and-accepted (first-party, MIT).

**Sanity Check:**

- All gate scripts exit 0
- Scratch consumer repo contains `.claude/autonomy/` with a `schema-version` after the non-interactive run, with zero prompts issued
- Security-review record present in the PR body

### Phase 6: Fleet binding dogfood — standards PR [TODO]

Runs AFTER the plugin PR merges (dead-cross-repo-link avoidance). First work item —
pre-flight: read `standards`' own conventions/docs layout and pick the target path per ITS
rules (no agent-operations section exists today; placement follows that repo's charter, not an
assumption).

Deliverable: the fleet binding instance doc in `melodic-software/standards` — each D1 role →
fleet instance (capability-distribution → the claude-code-plugins marketplace;
CI-orchestration → ci-workflows; settings-as-code → github-iac; org-policy → standards itself;
runner-execution → unborn, T4 birth trigger recorded). The doc records the role-vocabulary
version it binds and cites `role-topology.md`. Fleet names appear ONLY here among WP1
deliverables.

**Sanity Check:**

- Doc exists in the standards PR; one `grep` hit per D1 role name
- Doc contains the role-vocabulary version marker
- `grep -riE 'ci-workflows|github-iac' plugins/autonomy/` still empty (post-merge re-check)

## Blast radius

MEDIUM — ~12 files across 2 repos; new category + contract docs constrain WP2–WP6 (each of
which has its own architect round); fully git-revertible; automated gates (validate, contract
tests, CI lanes) cover the shared surfaces.

## Stress-test summary

Step 3 fresh-context plan review: 10 findings (1 CRITICAL — D6 dropped; fixed by
wiring-vs-advisor.md). Step 4 `/devils-advocate`: 0 CRITICAL / 3 HIGH / 5 MEDIUM / 3 LOW — all
folded into the phases above (whole-tree fleet-name sweep + standing gate; concern-named
config folder from day one; resolution-ladder pointer/fetch/terminal-default mechanics;
argument surface + headless defaults + non-interactive eval; schema-versioned binding;
description scoped to shipped capability; standards pre-flight + drift trigger + plugin-first
merge ordering). Residuals accepted: vendor deny-list completeness pairs with review;
cross-repo drift recheck is trigger-based (deferred-with-trigger: mechanical cross-repo check
when a second binding consumer exists); bare word "standards" ungrepable — org-qualified
token + review covers it.

## Execution shape

Fully sequential 1 → 2 → 3 → 4 → 5 → 6 — Phase 2's marketplace entry needs Phase 1's category;
Phase 4 cites Phase 3's binding shape; Phase 5 gates the authored tree; Phase 6 waits on the
plugin PR merge. Parallel saving immaterial (small doc volume).

| Phase | Surface | Basis |
|---|---|---|
| 1–4 | main-session | judgment-heavy contract/doc authoring, tightly coupled to design threads |
| 5 | main-session | gate runs + one shared-script edit |
| 6 | main-session | cross-repo PR with pre-flight judgment |

## Open questions

None blocking. Deferred with triggers: `docs/conventions/autonomy/` versioned config contract
(trigger: second plugin consumes `.claude/autonomy/`); mechanical cross-repo drift check
(trigger: second binding consumer); per-capability wiring depth (WP2–WP6 Briefs, per Brief).

## Handoff to implementation

### User-approval gates

- Phase 5's `validate-plugin-contracts.mjs` edit adds a standing CI gate — flagged
  [EXEC-SHAPE]; surface before landing if scope beyond `plugins/autonomy/**` is proposed.
- Phase 6 pre-flight outcome: if standards' conventions resist the binding doc (charter
  mismatch), STOP and re-surface placement rather than improvising a location.
- Any scope expansion beyond the six phases re-enters `/architect review`.

### Execution shape ([EXEC-SHAPE] tagged)

Sequential, all main-session (table above). Decisions made under the confidence gate:
reference/ as contract-doc home (10 in-repo precedents + reference-vs-context semantic split);
concern-named `.claude/autonomy/` (extensibility-contract rationale: plugin boundaries are the
volatile axis); full vendor+fleet name ban in reference/ with tool-specific details in
SKILL.md/README (Brief tool-agnostic constraint); description scoped to shipped capability
(Boris no-step-skipping); schema-versioned binding (version-pinning rules + standards-contract
precedent); two-PR split with plugin-first ordering (dead-link avoidance).

### Mechanical work

Commit per phase on the implementation branch (suggest `feat/autonomy-plugin`); PLAN.md phase
tags advance `[TODO]` → `[DOING]` → `[DONE]` in the same commit as the phase; gates re-run at
Phase 5 even if run earlier; no commits without the repo's commit conventions.
