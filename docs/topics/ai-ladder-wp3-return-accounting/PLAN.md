# ai-ladder-wp3-return-accounting

## Brief

### TLDR

Return-accounting convention (T5): a lightweight, tracker-resident record captured at the task
boundary of autonomous-class work, answering Boris's two return questions (counterfactual +
manual-effort band), joined to machine cost telemetry by the WP2 work-item attribute. No new
capability, no new cost; agents prompt and aggregate but never estimate return fields.

### Goal

Any adopting org can capture return data — would-have-done-anyway plus manual-effort band — at
every autonomous-class task boundary, as a tracker-resident record joinable to its cost
telemetry by work-item ID, via guided setup, with zero paid dependencies.

### Locked decisions

| # | Decision |
|---|---|
| D1 | Package scope: WP3 ships (i) the return-accounting convention doc and (ii) the capture slice of the guided-setup capability, both in the capability-distribution home (WP1 D4). "No new capability" (T5) means no standalone estimation/reporting product — not zero setup surface; the convention answers nobody's return questions if no surface ever asks them. Fleet dogfood wiring = work-item backlog, out of package. |
| D2 | Data model imported from T5 unchanged: three layers — (1) machine/deterministic: automation cost from existing session telemetry + lifecycle metadata from tracker timestamps; (2) human-attested: counterfactual yes/no/partial + manual-effort band; (3) agent/LLM: prompts for layer 2 at the task boundary, analyzes/aggregates over 1+2, NEVER estimates return fields (revisit trigger: models proven capable at effort estimation). Capture scope: autonomous-class work only (classes per T3 matrix); interactive exempt; expansion trigger: post-aggregation spend concentrating in interactive work. |
| D3 | Record shape: the contract defines the record SCHEMA — work-item ID (WP2 D3 namespace token), counterfactual enum, effort band, timestamp, attestor role — and the tracker binding seam decides the surface: native tracker fields where the tracker supports them, structured comment as the universal floor (every tracker has comments; custom fields are entitlement/vendor-specific). Exact schema tokens and comment template at architect. *RESOLVED 2026-07-18 (architect round, interview-locked): the "work-item ID" join value is the item's canonical web URL — attribute `autonomy.work_item.url`, record field `work_item_url` — never a tracker-short ID; the Plan's Phase 1 schema governs.* |
| D4 | Effort bands: fixed contract-owned ordinal scale. ~~Five contiguous bands — `<1h`, `1–4h`, `4h–1d`, `1d–1w`, `>1w`~~ **SUPERSEDED 2026-07-18 (stress-test evidence, user-locked): six contiguous bands — `<1h`, `1-4h`, `4h-1d`, `1d-1w`, `1w-1mo`, `>1mo` — the open `>1w` top band erased the largest avoided-effort signal; the Plan's Phase 1 schema is the governing serialization.** Deliberate deviation from the T5 draft (`<1h / 1–4h / 1–2d / 1w+`), which left 4h–1d and 2d–1w unmapped. Org-custom bands rejected: breaks cross-org aggregation (same argument that rejected per-adopter reverse-DNS in WP2 D3). |
| D5 | Prompt: Boris's two thread questions near-verbatim as the canonical basis — "would you have spent engineering effort on this anyway?" (yes/no/partial) and "what would it have cost in manual eng-hours?" (band). Two fields only; non-blocking at the task boundary; a skipped prompt is recorded as unattested — missing data stays visible, never imputed or estimated. Exact template wording at architect. |
| D6 | Cost-join mechanics: join-key-only. The return record and the cost telemetry both carry the work-item ID (WP2 D3 attribute); cost values are never duplicated into the tracker record; the join happens sink-side at query time (WP2 D5 query-on-read). Aggregation/reporting transport stays WP2's sink concern. |
| D7 | Guided-setup capture slice is discovery-first per WP1 D7: detect the adopting org's tracker and close-flow; wire the prompt at the task boundary where the surface is machine-editable and reviewable (WP1 D6 — always as reviewable changes); advise with steps + cost surfaced where the surface is GUI-only or entitlement-gated. |

### Constraints

- Any fleet repo name in normative contract text is a defect (WP1 acceptance criterion).
- Zero new cost by default; no paid dependency on any capture path.
- Telemetry is never presented as return — usage measures activity, not return (T5); the
  machine layer informs the cost side of the join only.
- No agent/LLM surface estimates, imputes, or backfills the two human-attested fields.
- Band set and counterfactual enum are contract-stable: changes are reviewed contract
  migrations, never per-org variation.
- Boris-alignment is the standing acceptance criterion: two human fields = his two questions,
  convention-before-capability, no step-skipping, trust before scale.

### Acceptance criteria

- Convention doc names roles and contract vocabulary only; record schema precise enough that
  architect fills mechanics without reopening the contract.
- The record consumes the WP2 D3 work-item attribute as-is — no modification to the WP2
  contract required.
- One conforming path demonstrates: autonomous-class work item closes → tracker-resident
  return record exists → joinable to that item's cost telemetry by work-item ID at the sink.
- Prompt carries exactly two fields, non-blocking; a skip is visible as an unattested record.
- No capability in the package estimates return fields or reimplements a native tracker or
  telemetry surface.
- Guided setup takes an adopter to the capture-enabled state as reviewable changes with zero
  paid dependencies.

### Captured assumptions

- Boris's two return questions come from his X thread (post 3), not the "Step & your role"
  table; verbatim capture is durable in design-threads T5. The table doc (now on disk:
  `docs/topics/ai-adoption-ladder/design/boris-step-and-your-role.txt`, source Google Doc linked from
  wayfind issues #239–#247) carries the related "is this something an engineer would have
  done?" variant — the thread wording is canonical for the prompt.
- The claude.ai artifact endpoint is intermittently erroring; the Google Doc is the reliable
  re-anchor copy.
- ~~The five-band contiguous scale is a deliberate correction of the T5 draft's gaps, locked
  under the round's recommendation pre-authorization.~~ SUPERSEDED 2026-07-18: the contiguous
  scale is now SIX bands per the D4 supersession above; migration authority for any further
  band change is a reviewed contract migration, governed by the Plan's Phase 1 schema.
- Tracker lifecycle metadata (layer 1b) is derivable from tracker exports/timestamps without
  new instrumentation.

### Out-of-scope (deferred with triggers)

- Aggregation/reporting transport — WP2 sink concern; join is query-side.
- Interactive-work capture — trigger: post-aggregation spend concentrates in interactive work.
- Per-class precision graduation (matrix column) — trigger: aggregate proves need.
- Fleet dogfood wiring (close-flow hooks, tracker config) — work-item backlog; trigger: WP3
  build lands.
- Return-field estimation by models — trigger: models proven capable at effort estimation
  (conditional constraint, revisit then).

### Deferred questions

- Exact record schema tokens + structured-comment template — `/architect`.
- Exact prompt template wording (two questions, skip affordance) — `/architect`.
- Tracker binding-shape catalog (native-field vs comment per tracker class) — `/architect`.
- Band label spellings/serialization — `/architect`.

## Plan

Consumes the WP2 join key as-is: attribute `autonomy.work_item.url`, value = the item's
canonical web URL (interview-locked in the batched WP2 round). Live-verified tracker facts
grounding the binding catalog (2026-07-18): GitHub now ships native issue fields
(org-managed, issues-only, REST+GraphQL); Jira custom fields on all plans; GitLab work-item
custom fields since 17.11; Linear has no custom fields by design — so the structured comment
remains the universal floor, native fields are the where-supported branch (D3 confirmed, not
reopened). No external effort-band standard exists to cite; bands stay contract-defined (D4).

Prerequisites: WP1 implementation merged; the WP2 package PR merged (this convention doc cites
the telemetry contract — dead-link avoidance). Fresh branch after both.

### Phase 1: Return-accounting convention doc [TODO]

| File | Action | What changes |
|---|---|---|
| `plugins/autonomy/reference/return-accounting.md` | Create | The T5 convention as tool-agnostic normative text. Three-layer data model (D2) with the never-estimate rule and its conditional revisit trigger. Record schema (D3): `schema_version` (string, from v1 — hook-envelope precedent), `work_item_url` (the join key; value contract defined by the telemetry contract's `autonomy.work_item.url` — pointer, not restated), `attested` (boolean), `counterfactual` (`yes` \| `no` \| `partial`), `effort_band` (six contiguous ordinal tokens: `<1h`, `1-4h`, `4h-1d`, `1d-1w`, `1w-1mo`, `>1mo` — user-locked 2026-07-18 on stress-test evidence, superseding D4's five-band set: the open `>1w` top band erased the largest avoided-effort signal; serialized as those exact strings, ordinal order defined by the contract, never lexical), `attested_at` (ISO 8601 UTC), `attested_by` (the attesting human's platform identity, captured from the attestation action), `attestor_role` (`requester` \| `reviewer` \| `maintainer` \| `other`). Composition rule: `effort_band` answers the manual-cost question for the WHOLE delivered item regardless of `counterfactual` value; `partial` qualifies the counterfactual only — aggregation derives avoided cost from the pair, the attestor never prorates. Presence rules: an unattested record carries `attested: false` with `counterfactual`/`effort_band`/`attested_at`/`attested_by`/`attestor_role` ABSENT (never null-imputed); an attested record carries all fields. Record lifecycle — attestation is ASYNCHRONOUS by construction (autonomous-class work has no human at the close boundary): the machine posts the unattested record at close plus an attestation request routed to the accountable human; attestation later upserts the same record to `attested: true`. A never-attested record stays visible as unattested. Attestation routing for requester-less classes (standing routines, scheduled sweeps): the binding declares a standing attestation owner per class, or marks the class attestation-exempt with its cost reported separately — never a perpetually-unattested default. Record integrity: a conforming record is authored by the deployment's bound automation identity; consumers MUST ignore marker-matching records from any other author; attestor identity derives from the PLATFORM actor of the attestation action — on the comment floor the upsert itself is bot-authored, so the record's `attested_by` MUST be copied from, and the record MUST cite, the attestation source event (the human's reply/reaction whose platform actor answered) — the self-declared `attestor_role` field is descriptive, never the trust anchor. Aggregation guidance: report the attestation rate as a first-class health signal (a collapsed rate invalidates the dataset as promotion evidence) and separate requester-attested from independently-attested rows (self-attested counterfactual is a conflict of interest). Duplicate tolerance: the standalone capture path's find-then-create has an inherent create-create race — dedupe on read is ATTESTATION-PRESERVING: an attested bot-authored record outranks any unattested one; only among equally-attested records does the latest win. Write rule, same property: the close trigger creates the unattested record only when no marker-matching bot-authored record exists — a re-fired or retried close NEVER overwrites or downgrades an existing record's attestation fields. Capture point: task boundary (work-item close / PR merge); scope: autonomous-class work per the T3 class vocabulary. Tracker binding seam: record surface resolves per tracker class — native fields where the class supports them (org-managed issue fields, project-scheme fields, work-item fields), structured comment as the universal floor: hidden marker `<!-- autonomy:return-accounting:v1 -->` + one fenced JSON block, marker-keyed upsert (find-then-edit, else create — established in the wider bot ecosystem; NEW to this repo's seams). Prompt: Boris's two questions near-verbatim ("Would you have spent engineering effort on this anyway?" yes/no/partial; "What would it have cost in manual eng-hours?" band), exactly two fields, non-blocking, explicit skip affordance. Join is query-side by the join key only against cost telemetry (resource-scoped on agent-session signals per the telemetry contract); cost values never duplicated into the tracker record (D6). Zero vendor/fleet names; tracker-product specifics live in SKILL.md. |

**Sanity Check:**

- `grep -c 'autonomy.work_item.url' plugins/autonomy/reference/return-accounting.md` ≥ 1
- `grep -c 'return-accounting:v1' plugins/autonomy/reference/return-accounting.md` ≥ 1
- All six band tokens present: `grep -c -- '1w-1mo' plugins/autonomy/reference/return-accounting.md` ≥ 1 (spot token) and the schema block lists exactly 6 bands
- `grep -ci 'attestation rate' plugins/autonomy/reference/return-accounting.md` ≥ 1 and `grep -ci 'bound automation identity' plugins/autonomy/reference/return-accounting.md` ≥ 1 (integrity + health-signal clauses present)
- `grep -ci 'estimate' plugins/autonomy/reference/return-accounting.md` ≥ 1 (never-estimate rule stated)
- Vendor+fleet deny-list grep empty over the file; `node scripts/validate-plugin-contracts.mjs` exit 0; lychee passes

### Phase 2: Guided-setup capture slice [TODO]

First work item — fresh-docs mandate (repo CLAUDE.md): re-fetch official skills/hooks docs
before editing SKILL.md; re-verify tracker API surfaces cited in templates at implementation.

| File | Action | What changes |
|---|---|---|
| `plugins/autonomy/skills/setup/SKILL.md` | Modify | Add the capture slice to discovery + apply: detect the adopting org's tracker class and close-flow surface; WIRE where machine-editable + reviewable — a close-triggered snippet posting the UNATTESTED record + an attestation request addressed to the accountable human (the close flow never blocks; attestation is the async upsert), native-field write where entitled; ADVISE with steps + cost surfaced where GUI-only or entitlement-gated (org-gated native fields, plan-gated automation); private-repo CI-minutes cost surfaced on the wire path (metered pool — non-zero). Where the work-items plugin is present, record writes ROUTE THROUGH its comment adapter (race-safe, multi-tracker) with marker-keyed upsert added as a new layer on top of its append-only surface — never a parallel comment writer; standalone snippet only for adopters without that seam. Record surface choice + tracker class land as an ADDITIVE section of the WP1 schema-versioned binding (absent-section tolerance; no schema major bump). |
| `plugins/autonomy/skills/setup/evals/evals.json` | Modify | Add capture-slice cases: tracker-detect + comment-floor wire path, native-field advisory path (entitlement-gated), skip-produces-unattested-record, refusal case (never estimates or backfills the two human fields), upsert idempotency under a re-fired close (count stays 1), requester-less class routing (standing owner or exempt — never silent unattested default). |
| `plugins/autonomy/skills/setup/templates/` (WP2's snippet home) | Create | Close-boundary capture snippet: prompt text (the two canonical questions verbatim), marker-keyed upsert comment template with the fenced JSON record, unattested-on-skip shape. Surface-class-parameterized; fleet names banned. |
| `plugins/autonomy/README.md` | Modify | Shipped-capability list grows; roadmap row flips. |
| `plugins/autonomy/.claude-plugin/plugin.json` | Modify | Description extends; semver minor bump (repo versioning rule). |

**Sanity Check:**

- `/skill-quality:check` + `validate-evals` pass; `claude plugin validate --strict` exit 0
- `grep -rc 'return-accounting:v1' plugins/autonomy/skills/setup/templates/` ≥ 1
- `grep -rc 'engineering effort on this anyway' plugins/autonomy/skills/setup/templates/` ≥ 1 (canonical question verbatim)
- `grep -c 'attested: false' plugins/autonomy/reference/return-accounting.md` ≥ 1 (async/unattested lifecycle stated)
- Fleet-name sweep exit 0

### Phase 3: Conforming-path demonstration [TODO]

Acceptance-criterion probe, scratch consumer repo: close a demo work item → the
close-triggered capture posts the unattested marker-keyed record (comment floor) + attestation
request → attest via upsert → join to demo COST telemetry (the COMMITTED WP2 Phase 3 fixture's
agent-session cost metric — durable interface, no WP2 pipeline re-run) by
`autonomy.work_item.url` in a DuckDB query. The fixture's baked `autonomy.work_item.url` value
is SUBSTITUTED with the demo item's canonical URL as demo-input preparation before the join
query (the scratch item's URL cannot match a pre-committed value; substitution touches the
demo copy only, never the committed fixture). Zero paid dependencies.

**Sanity Check:**

- The tracker item carries exactly one comment matching `<!-- autonomy:return-accounting:v1 -->` with a parseable JSON record (re-running the capture upserts, count stays 1)
- The close-time record shows `attested: false` with the five attestation fields absent; the post-attestation upsert shows `attested: true` with all fields present, `attested_by` matching the attestation source event's platform actor
- Re-firing the close AFTER attestation leaves the attested record untouched (no downgrade to unattested)
- DuckDB join query returns ≥ 1 row pairing the record's `work_item_url` with an agent-session COST metric whose resource attribute `autonomy.work_item.url` is string-identical
- Demo transcript + query output in the PR body

### Phase 4: Gates [TODO]

Same in-repo gate roster as the WP2 package: validate-plugins, run-plugin-tests,
validate-plugin-contracts, markdown/typos/lychee, `claude plugin validate --strict`, catalog
regen check. Near-duplicate audit statement: capture composes the work-items close-flow seam,
never duplicates it; no capability estimates return fields.

**Sanity Check:**

- All gate scripts exit 0; `node scripts/generate-catalog.mjs` in-sync
- Near-duplicate + never-estimate audit statements present in the PR body

## Blast radius

MEDIUM — ~7 files in one plugin, but the record schema is a new public contract consumed by
every adopter and by the WP2 join; new-convention trigger matches. Git-revertible; automated
gates cover shared surfaces.

## Stress-test summary

Step 3 fresh-context plan review (shared with WP2): async-attestation lifecycle was
unspecified (no human exists at an autonomous close — fixed: unattested-at-close + async
upsert); marker-upsert correctly reframed as new-to-this-repo layered on the work-items
comment adapter; unattested field presence pinned; join derivation made pointer-only.
Step 4 `/devils-advocate` (shared): folded — record integrity (bot-authored records only,
platform-actor attestor identity, self-declared role never the trust anchor), attestation-rate
health signal + requester/independent split, requester-less class routing rule, standalone
create-create race stated with latest-bot-record-wins read rule, six-band set (user-locked,
supersedes D4 five bands), partial×band composition rule, committed WP2 fixture as the demo
interface. Residual accepted: comment-surface forgery is mitigated by authorship filtering,
not eliminated — native-field surfaces inherit platform ACLs and are the stronger branch where
entitled.

## Execution shape

Fully sequential 1 → 2 → 3 → 4 — Phase 2 wires what Phase 1 specifies; Phase 3 exercises
Phase 2's snippet against the committed WP2 fixture; Phase 4 gates. Parallel saving
immaterial. Cross-package: this PR merges after the WP2 PR (contract citation + fixture
dependency); both wait on WP1 implementation.

| Phase | Surface | Basis |
|---|---|---|
| 1 | main-session | normative convention authoring, coupled to T5 + WP2 contract + interview locks |
| 2 | main-session | setup-skill + template judgment, tracker-API re-verification gate |
| 3 | main-session | scratch-repo runtime probe with divergence judgment |
| 4 | main-session | gate runs |

## Open questions

- Fleet dogfood wiring (close-flow hooks, tracker config): backlog items file via the
  work-items flow after this package lands (out of package per D1).

## Decisions made (gate-passed)

| Decision | What it changes in the plan | Basis (evidence) |
|---|---|---|
| Convention doc filename `reference/return-accounting.md` | Phase 1 target path | WP1 layout convention (concern-named contract docs in `reference/`) |
| Marker token `<!-- autonomy:return-accounting:v1 -->` + fenced JSON record, marker-keyed upsert | Phase 1 schema + Phase 2 templates | Live-verified ecosystem precedent (find-comment/create-or-update-comment upsert pattern); versioned marker enables schema migration |
| Comment floor universal; native fields the where-supported branch | Phase 1 binding-seam catalog | Live verification: GitHub fields org-gated issues-only; Linear none by design; Jira all plans; GitLab 17.11+; comments universal |
| Band serialization = exact display strings, contract-ordinal order | Phase 1 schema | User-locked band set; strings are self-describing, JSON-safe |
| `attestor_role` enum `requester\|reviewer\|maintainer\|other` (descriptive, platform actor is the trust anchor) | Phase 1 schema | Stress-test HIGH #4 fold; overridable at approval |
| partial×band composition rule (band = whole-item manual cost; aggregation derives avoided cost) | Phase 1 contract clause | Stress-test MEDIUM #9; Boris Q2 asks whole manual cost |
| Record integrity: bot-authored records only, foreign-author records ignored, attestation-rate health signal, requester/independent aggregation split | Phase 1 contract clauses + Phase 2 eval | Stress-test HIGH #4 |
| Requester-less class routing (binding-declared standing owner or attestation-exempt) | Phase 1 clause + binding field | Stress-test MEDIUM #8; T7 routine classes have no requester by construction |
| Standalone-path race stated + attestation-preserving dedupe (attested outranks unattested; latest wins only among equals; close never downgrades) | Phase 1 clause + Phase 2 eval | Stress-test HIGH #5 + review fold; work-items adapter is the race-safe path where present |
| Demo joins against the committed WP2 fixture | Phase 3 input | Stress-test MEDIUM #10 |

No [FALLBACK] tags — every remaining item traces to the Brief, an interview lock, or a
verified stress-test fold.

## Handoff to implementation

### User-approval gates

- Any change to the six-band set or the counterfactual enum after this approval is a
  reviewed contract migration — re-enter `/architect review`, never inline.
- Tracker-API surfaces cited in templates re-verify at implementation (fresh-docs); a
  divergence (e.g. field entitlements changed) STOPs and re-surfaces.

### Execution shape ([EXEC-SHAPE] tagged)

Sequential 1→4, all main-session (table above). PLAN.md phase tags advance in the same commit
as each phase; scratch-repo demo per Phase 3; divergence escalation applies to every phase.

### Mechanical work

Commit per phase on the implementation branch (suggest `feat/autonomy-return-accounting`);
gates re-run in full at Phase 4; commits via the repo's commit conventions; PR body carries
the demo transcript + never-estimate/near-duplicate audit statements + this PLAN in a
`<details>` block at close-out.
