# ci-workflows-work-loop

## Brief

**TLDR**: Drain repo issue backlogs autonomously via a 3-session-per-repo topology — worker loop
authors PRs (never merges), babysit lane owns merges at a merge-capable tier (worker minimum;
autopilot where only bot PRs are in scope), HITL decides — built as reusable org-scope plugin
lanes; ci-workflows (21 open issues) is the first instantiation. Sibling deliverable with its own
Brief: `/source-control:babysit-loop` (`babysit-PLAN.md`, same directory — succession from the
terminated babysit session).

### Goal

1. Two new skills in the `work-items` plugin (`melodic-software/claude-code-plugins`):
   `work-loop` (dynamic self-paced drain: mechanical-triage intake sweep, adaptive parallel
   dispatch, escalation, heartbeat, exit-condition evaluation) and `hitl-queue` (attended lane:
   polls escalations + untriaged intake, composes `/work-items:triage` + `/planning:interview`,
   writes answers back, flips items to agent-ready). Work-lane-specific mechanics ONLY — shared
   cross-lane concerns live in the convention doc (goal 1b), which both plugins cite.
   Interim-executor rationale cites `plugins/autonomy/reference/runner.md`.
1b. New repo-level convention `docs/conventions/loop-lane/` + registry row
   (per `docs/PLUGIN-PHILOSOPHY.md`: sibling-plugin imports are defects; a cross-plugin
   convention lands in an owner doc before a second plugin adopts it — the babysit lane in
   `source-control` is that second adopter). Owns: 3-session topology, escalation contract,
   model-routing capability tiers (IDs live-resolved), and the loop-layer invariants — stop
   shapes (standing vs drain), `#691` cycle-budget semantics (resolution (a): budget restarts the
   SESSION, never ends the LOOP), idle backoff, `#502` per-lane edited status comment,
   headless-config floor (a headless lane launch never blocks on an interview: explicit/persisted
   config or tier defaults + log), and the subagent discipline preamble. `autonomy` remains the
   governing-policy pointer (guardrail matrix), not a mechanics home.
2. New small `rate-limit-guard` plugin: statusline tee wrapper (writes `rate_limits` + timestamp to
   fixed path), reader contract (pause ≥90% of either window until later `resets_at`; Monitor
   watches tee file so account switches wake the pause early — MANDATORY, not optional: the
   statusline schema carries no account-identifier field, verified live), `StopFailure` matcher
   `"rate_limit"` reactive fallback (side-effect-only detection — hook output/exit ignored,
   payload carries no reset/quota data; resume timing comes from the tee file or parsed error
   text, verified live), capability-detect fail-open (absence/absurd values = unknown,
   reactive-only — covers enterprise/API-key auth, where limits may exist but are unobservable).
   Implementation notes: shell-run fields reject `${user_config.*}` (use exec-form args/env/config
   file); plugin `experimental.monitors` auto-start is a candidate watcher surface; babysit-loop
   and hitl sessions are consumers two and three of the shared windows.
3. ci-workflows instantiation: `.work-item-tracker.json` (github provider) via PR; initial triage
   pass over the 14 unlabeled issues (attended, this session); loop run to exit condition.
4. `standards` doc PR: record activation of the deferred assignee+lease claiming mechanism
   (`conventions/process/issue-tracker.md` status axis).

### Constraints

- Worker loop is PR-only; merging belongs to babysit worker tier; judgment belongs to HITL.
- Exit condition: every open issue closed OR has an active non-draft PR (native closing-keyword
  linkage; the seam's in-flight-PR exclusion is the drain signal).
- Label set is github-iac-owned: no ad-hoc label creation; role labels resolved via
  `.work-item-tracker.json` `config.role_labels`, never compared as literals. Worker-escalated vs
  parked discriminated by machine-marked bot comment, not a new label.
- Skill bodies are thin delta only — invoke owned mechanics (`/work-items:work`,
  `/implementation:implement-dispatch`, `/source-control:worktree`, `/work-items:triage`,
  `/planning:interview`); never restate selection/claim/lease/dispatch/triage machinery.
- Worker dispatch prompts enumerate required skills per phase; subagent authority is an open-ended
  duty ("escalate decisions that are the operator's — e.g. contract, security-posture,
  enforcement-scope, issue-goal changes"), not a closed list.
- Work-class gate, in autonomy contract terms (`reference/guardrails/work-classes.md` +
  `admission-policy.md`, read this session): `C2` mechanical → autonomous-eligible; `C3` scoped →
  autonomous for bug-fix-shaped items, human-gated for feature-shaped (operator tightening —
  permitted without justification); `C4` structural/contract and `C5` untrusted-provenance →
  human-gated / per-contract floors; unclassified → fail-closed human-gated (contract rule).
- Model routing: capability TIERS in the convention doc, defined by capability ORDER, never by
  family name (verified: family ≠ capability across generations — the advisor matrix ranks
  Sonnet 5 equal to Opus 4.6). Live resolution: model aliases (`fable`/`opus`/`sonnet`/`haiku` —
  the only live-updating handles; dateless IDs are pinned snapshots) + the Models API list
  endpoint; account for provider-dependent alias resolution and org `availableModels` overrides.
  Advisor rule as documented: "at least as capable" as main (equal pairings valid); fast-main +
  strong-advisor pairing is officially recommended (advisor docs + blog, cited in
  scratchpad model-routing-verification/RESEARCH.md). Defaults: fast-tier orchestrator +
  advisor ≥ main; strong-tier workers;
  frontier tier for complex-stamped items; fast tier for mechanical; reviewer/verifier never
  weaker than implementer; tier signal from triage briefing (issue body, not a label);
  security-surface work-class → frontier tier, ALWAYS (operator directive). Windows: 5-hour
  ROLLING + weekly FIXED-ANCHOR (not rolling — verified); the per-model weekly cap's family is
  mid-transition in official docs (Sonnet vs Opus conflict) — LINK the support article, never
  hard-code the family; Fable's 50%-of-weekly allowance on Max is documented.
- Adaptive item-level cap: start 2, +1 after 3 consecutive clean items (ceiling 3), −1 on any dirty
  item (floor 1); no ramp-up while a rate-limit warning is live; composed budget with
  implement-dispatch's per-item wave cap stated explicitly.
- Rate limits: drain-then-pause default (finish in-flight, stop claiming, ScheduleWakeup/Monitor
  until reset, report); hard stop only by user request; model downshift only as explicit opt-in.
- Org-agnostic throughout; no machine-/user-specific paths in skill bodies.
- ci-workflows `CLAUDE.md` security ground rules are inviolable by workers (escalate, never edit).
- Authoring governed by `playbooks:skill-authoring` + `skill-quality:check`; WebFetch current
  official plugin/skills docs during build (claude-code-plugins CLAUDE.md mandate); hook wiring
  (StopFailure) via `update-config`; model-routing tier tables built from a live official-docs
  fetch at build time, never recall.
- Prep before build: pull ci-workflows (behind 11) + standards (behind 19); claude-code-plugins →
  main + pull (current branch's upstream deleted).

### Acceptance criteria

- Loop runs unattended on ci-workflows until the exit condition; final report lists items closed,
  PR'd, and escalated.
- Escalated items carry `needs-human` (role-resolved) + machine-marked question comment; attend-queue
  surfaces them and untriaged intake in one attention view.
- Two parallel workers never hold the same item (seam lease race observed working).
- Guard pauses claiming at ≥90% of either window and resumes after reset without operator action
  (subscription auth); on non-subscription auth it declares reactive-only and never throttles.
- Both lanes + guard plugin pass `skill-quality:check`.
- Second-repo adoption = one binding PR + three sessions; zero plugin edits.

### Captured assumptions

- Subscription (Pro/Max) auth in loop sessions for proactive throttle; anything else fail-opens to
  reactive.
- work-items `#572` (autonomous branch/worktree provisioning seam) worked around in-template via
  explicit provisioning before dispatch; upstream fix optional follow-up.
- Statusline runs (and tees) in interactive sessions; headless `claude -p` unverified and unused.
- `/login` multi-account rotation is undocumented community practice — manual operator action
  only; the design never automates or depends on it.

### Out of scope

- The autonomy runner build (stays charter-gated; this loop is the interim executor earning its
  triggers — cited, not built).
- Routine-catalog graduation of heartbeat/triage sweeps (trigger recorded: loop proves stable).
- Babysit plugin lane (owned by the user's separate session).
- Worker-loop merging; new labels; the unofficial `api/oauth/usage` endpoint.

### Deferred questions

- Multi-repo scale-out shape (per-repo loops vs round-robin worker) — trigger: second repo adopts.
  Arbiter: USER-RESERVED.
- Upstream work-items PR for `#572` once the in-template workaround proves out. Arbiter:
  /planning:plan.
- Build-time verifications: StopFailure `rate_limit`
  matcher behavior on API-key auth; implement-dispatch per-worker model override wiring (substrate
  confirmed: agent frontmatter supports `model`, `effort`, `skills` preload, `isolation:
  worktree`); worker
  commit signing vs merge strategy against the `signing` ruleset (`required_signatures` on main —
  verified live); machine-readable surfacing of Q18's quality signals (design intent; check
  pipeline-shape.md). Arbiter: /planning:plan.

## Plan

> Scope-change note (2026-07-23, approval round): three Brief statements superseded by
> operator decision — (1) "babysit merges at worker tier minimum / autopilot for bot-only
> repos" → autonomy ladder with human-merge default (Phase 2 item 1; babysit-PLAN B3 tier =
> worker); (2) skill name `hitl-queue` → `attend-queue` (naming-grammar rule); (3) exit
> condition gains the drain-terminal state. Brief text above is historical; this Plan is
> authoritative for the deltas.

### Standards grounding

No standards index (`docs/standards/README.md` with `standards-contract` frontmatter) exists in
claude-code-plugins, ci-workflows, or standards — resolution ladder rung 4/6 (inference; assumption
surfaced). Grounding sources read this session:

| Surface | Source | Provenance |
|---|---|---|
| Plugin/skill design | claude-code-plugins `CLAUDE.md` (fresh-docs mandate L6-11, design rules L37-50); `docs/PLUGIN-PHILOSOPHY.md` (seam rules L22-33, convention registry L329-353, hook contract L326-328, Windows exec-form L128, Monitors stance "Wait" L134) | team (repo) |
| Work-items seam | `plugins/work-items/reference/tracker-seam.md`, `label-taxonomy.md`, `tools/work-item-tracker/CONTRACT.md` (lease protocol L207-231) | team (repo) |
| Autonomy contracts | `plugins/autonomy/reference/guardrails.md` (matrix, escalation L68-94), `guardrails/work-classes.md`, `admission-policy.md`, `runner.md` (interim-executor L8-51) | team (repo) |
| Source-control | `plugins/source-control/skills/babysit-prs/SKILL.md` + `reference/loop.md`, `reference/config-resolution.md` | team (repo) |
| Lane ops | `plugins/claude-ops/skills/lanes/SKILL.md` (launcher, `telemetry-upsert.sh` #502 interim, #480 prompt seam) | team (repo) |
| Security | ci-workflows `CLAUDE.md` L7-50 (inviolable ground rules) | team (repo) |
| Tracker process | standards `conventions/process/issue-tracker.md` (L37 deferred lease, L52-58 label IaC governance) | team (repo) |

### Build-technique note

No viability unknown remains (interview + research resolved design); risk is integration. Kept
tracer-bullet slice = Phase 5+7 head: bind the tracker seam and run ONE work-loop cycle
end-to-end on ci-workflows before declaring the lane operational. Phases 2–4 are the
convention/plugin substrate that slice consumes.

### Phase 1: Topic-contract move + branches [DONE]

Move both Briefs to the tracked contract slice in claude-code-plugins (operator-confirmed
placement; topic-docs convention `contract_tier: branch`):

| File | Action | What |
|---|---|---|
| `claude-code-plugins/docs/topics/ci-workflows-work-loop/PLAN.md` | Create | this file (Brief + Plan) |
| `claude-code-plugins/docs/topics/ci-workflows-work-loop/babysit-PLAN.md` | Create | babysit Brief + Plan |
| `claude-code-plugins/docs/topics/ci-workflows-work-loop/design/design-resolution.md` | Create | design gate file — a contract kind per topic-docs convention (README tier table), moves with the slice |
| `.work/ci-workflows-work-loop/*` | KEEP | working state; research + ledgers stay memory-slice |

Branch per PR-phase (`feat/loop-lane-convention`, `feat/rate-limit-guard`,
`feat/work-items-loop-lanes`, …) — topic docs ride the first build branch and each later branch
carries its own phase-status updates.

- **Sanity Check:** `git -C <claude-code-plugins> ls-files docs/topics/ci-workflows-work-loop/` lists both PLAN files + `design/design-resolution.md` (exit 0, 3 lines).

### Phase 2: `docs/conventions/loop-lane/` convention + registry row [DONE]

Owner doc for every shared cross-lane concern (PLUGIN-PHILOSOPHY L331-333: owner doc lands BEFORE
the second adopter). One PR to claude-code-plugins.

| File | Action | What |
|---|---|---|
| `docs/conventions/loop-lane/README.md` | Create | full contract (content below) |
| `docs/conventions/loop-lane/CHANGELOG.md` | Create | `## 1.0.0 — <date>` |
| `docs/PLUGIN-PHILOSOPHY.md` | Modify | one registry row: `\| Loop-lane topology, escalation, capability tiers, loop invariants \| [docs/conventions/loop-lane/](conventions/loop-lane/README.md) \|` |

README.md contract sections (pointer-not-copy — cite owners, never restate):

1. **3-session topology** — worker loop authors PRs (never merges); babysit lane owns merges
   WITHIN the autonomy guardrail matrix's merge-policy column; HITL decides. Merge authority
   (operator-resolved 2026-07-23): a configurable AUTONOMY LADDER with the safest default —
   **human merge is the shipped default for everything except gate-proven bot/C2 mechanical
   PRs** (dependabot/small/easy/safe candidates); higher rungs up to full autonomy (frontier
   subagents resolving conflicts, responding to comments, making changes, driving to merge)
   are opt-in per repo. The ratification mechanism: raising a merge rung is a config change on
   the TRACKED layered seam (reviewable, versioned) — exactly the matrix's required
   "human-ratified knob flip recorded on the governance surface" (`work-classes.md` Promotion
   L57-59), so C3 autonomous merge is reachable only through a recorded flip, never by
   default. Operator may adjust rungs on the fly; each adjustment is a tracked config edit.
2. **Escalation contract** — `needs-human` role label resolved via `.work-item-tracker.json`
   `config.role_labels` (cite `plugins/work-items/reference/label-taxonomy.md` canonical roles)
   \+ machine-marked bot comment discriminator (worker-escalated vs parked). Cites autonomy
   `reference/guardrails.md#escalation` event classes as governing policy; no second channel.
3. **Capability tiers** — order-defined tiers (never family names); RUNTIME resolution via
   aliases ONLY (the only handles guaranteed under subscription OAuth — stress-test finding:
   the Models API list endpoint needs API-key auth loop sessions may lack); Models API is the
   build/audit-time verification path; re-derivation trigger recorded in the convention
   CHANGELOG: any new model release re-audits the tier table. Advisor "at least as capable";
   security-surface class → frontier ALWAYS; weekly-cap family LINKED to the support article,
   never hard-coded. Tier tables built from live official-docs fetch at build time (fresh-docs
   mandate).
4. **Loop-layer invariants** — stop shapes (standing vs drain, PLUS the drain-terminal state
   `[FALLBACK — confirm or override]`: when every remaining open item is human-gated/escalated
   and no PR is in flight, drain reports + stops cleanly instead of idling forever — reviewer
   finding: without it an overnight drain deadlocks on the first unanswered escalation);
   #691 resolution (a): cycle budget restarts the SESSION, never ends the LOOP — restart is
   launcher/operator-initiated (a running loop cannot `/clear` itself; cite `claude-ops` lanes
   SKILL.md "A relaunch is the only context reset"), so budget-hit = emit restart-request
   telemetry + stop loop cleanly; idle backoff; #502 per-lane edited status comment — the
   convention FIXES the comment contract (machine sentinel marker, edit-in-place, one comment
   per lane, per #502) and each lane INLINES the small `gh api` upsert (operator coupling
   directive 2026-07-23 + philosophy: an installed plugin cannot invoke a sibling plugin's
   scripts; `claude-ops` `telemetry-upsert.sh` is cited as the interim #502 home and a
   compatible consumer — `morning-brief` reads the same surface — coupling stays
   one-directional);
   **durable loop state across compaction** — adaptive-cap streak counter, rate-limit-warning
   latch, and cycle count persist in a machine-readable block of the lane's #502 telemetry
   comment, re-read at each cycle start (conversation context alone is compaction-lossy);
   headless-config floor (headless launch never blocks on interview: explicit/persisted config
   or tier defaults + logged notice); subagent discipline preamble (sweep-all-disciplines +
   use-your-skills + do-your-research); seam exit 8 (provider unavailable / secondary GitHub
   limits under one credential) → backoff-and-retry, counted as a dirty signal for the adaptive
   cap; drain exit evaluated against a cycle-start snapshot — new automated intake is REPORTED,
   never chased.
5. **Consumers + launch surfaces** — work-items `work-loop`/`attend-queue`, source-control
   `babysit-loop`; launchable interactively via `/loop` (primary, dependency-free) or headless
   via `claude-ops:lanes` (`prompt_dir` seam, #480 forward dependency) — lanes is a SUPPORTING
   launcher, strictly one-directional (operator coupling directive 2026-07-23): lanes launches
   the skills; no loop skill ever references, requires, or degrades without `claude-ops`; every
   mention in skill bodies is guarded if-installed with the `/loop` fallback documented.
   `autonomy` remains governing-policy pointer.
6. **Rate-limit guard binding** — all three lanes are consumers of the shared subscription
   windows. Operability rule (reviewer finding): an installed plugin cannot read sibling-plugin
   files or this repo's `docs/` at runtime — each consuming skill body INLINES the operable
   floor (tee-file path, 90% threshold, staleness rule, drain-then-pause) and cites the guard
   reader contract for provenance only. The convention records this inline-floor rule so the
   values stay byte-identical across consumers (fleet audit checks conformance per row).
   Single-account-per-machine invariant (stress-test finding: tee file is last-writer-wins with
   no account id — a mid-drain `/login` to another account feeds healthy windows to lanes on
   the exhausted one; the guard cannot detect this, the convention says so); lane telemetry
   records guard mode (proactive/reactive/unknown) each cycle so silent degradation is visible
   in the #502 surface.

- **Sanity Check:** `grep -c "loop-lane" docs/PLUGIN-PHILOSOPHY.md` ≥ 1 (registry row present).
- **Sanity Check:** `test -f docs/conventions/loop-lane/README.md && test -f docs/conventions/loop-lane/CHANGELOG.md` exit 0.
- **Sanity Check:** repo CI green on the PR (`ci-status` required check).
- **Sanity Check:** `grep -En "plugins/(work-items|source-control|claude-ops|autonomy)/" docs/conventions/loop-lane/README.md` returns citations only in pointer form (reviewed: no restated mechanics blocks >3 lines quoting a plugin file).

### Phase 3: `rate-limit-guard` plugin [TODO]

Review: security
New small plugin in claude-code-plugins. One PR. Pre-flight consumer check N/A (new surface, no
existing consumers). Fresh-docs mandate: WebFetch statusline + hooks reference pages before
authoring; cite URLs in the PR.

| File | Action | What |
|---|---|---|
| `plugins/rate-limit-guard/.claude-plugin/plugin.json` | Create | manifest, semver 0.1.0, `userConfig`: hook kill switch ONLY (reviewer finding: threshold/tee-path overrides are dead config — `${user_config.*}` is plugin-scoped and cross-plugin consumers read the documented fixed values; contract path + 90% are FIXED) |
| `plugins/rate-limit-guard/hooks/hooks.json` | Create | `StopFailure` matcher `"rate_limit"` → `record-rate-limit-stop.sh` |
| `plugins/rate-limit-guard/hooks/record-rate-limit-stop.sh` + `.test.sh` | Create | side-effect-only detection record (hook output/exit ignored by harness — verified); test-first |
| `plugins/rate-limit-guard/hooks/hook-utils.sh` | Create | synced copy via `scripts/sync-hook-utils.sh` (CI byte-parity gate) |
| `plugins/rate-limit-guard/scripts/statusline-tee.sh` + `.test.sh` | Create | wraps the user's statusline command; tees stdin JSON `rate_limits` + ISO timestamp to the contract path via ATOMIC write (temp file + rename — 3+ concurrent sessions write one path; readers must never see torn JSON; Windows: rename-over-open-target can EACCES without FILE_SHARE_DELETE — retry-then-skip, and a tee failure NEVER propagates into the statusline pipeline; `.test.sh` covers the locked-target case); tees any session-distinguishing field present so a future account-id field is adopted automatically; defined no-statusline path (installs as standalone minimal statusline when none configured); Windows/Git Bash shell requirement stated in the script header and verified live (first instantiation is the operator's Windows machine); test-first |
| `plugins/rate-limit-guard/skills/setup/SKILL.md` | Create | CHECK-ONLY setup (PLUGIN-PHILOSOPHY L270: setup must NOT mutate Claude Code user settings): `check` verifies jq, probes tee freshness (distinguishing "no statusline configured" from "wrapper missing"), and PRINTS the exact `settings.json` statusline edit for the operator to apply; surfaces the chezmoi/dotfiles tracking proposal for the operator-changed user-scope file |
| `plugins/rate-limit-guard/reference/reader-contract.md` | Create | pause when EITHER window ≥90%, until the TRIPPED window's `resets_at` (the later `resets_at` applies only when BOTH windows trip — reviewer finding: the earlier phrasing over-pauses a 5-hour trip until the weekly reset); staleness rule (no account-id field — consumers MUST arm a session Monitor on the tee file; plugin ships no monitor config, fleet Monitors stance is "Wait" per PLUGIN-PHILOSOPHY L134); capability-detect fail-open (absent/absurd = unknown = reactive-only); drain-then-pause; fixed tee path + threshold as the operable constants consumers inline; consumer list (3 lanes) |
| `plugins/rate-limit-guard/README.md`, `CHANGELOG.md` | Create | per repo norms |
| `.claude-plugin/marketplace.json` | Modify | plugin entry (no version field) |
| `scripts/skill-leaf-name-registry.txt` | Modify | register `setup` leaf if registry requires per-plugin entries (verify gate script semantics at build) |

Build-time verifications (Brief "Deferred questions", arbiter: this plan): StopFailure
`rate_limit` matcher behavior on API-key auth (empirical: forced-failure probe); statusline
stdin schema fields present on this CLI version (live probe); shell-run fields reject
`${user_config.*}` → exec-form args/env only (already verified; re-verify against current docs).

- **Sanity Check:** `bash scripts/validate-plugins.sh` exit 0.
- **Sanity Check:** `bash scripts/run-plugin-tests.sh` exit 0 (includes new `.test.sh` files).
- **Sanity Check:** `bash scripts/sync-hook-utils.sh --check` exit 0.
- **Sanity Check:** live probe — with wrapper wired, `jq -e '.rate_limits and .captured_at' <tee-file>` exit 0 after one statusline refresh.
- **Sanity Check:** `/skill-quality:check setup` PASS.

### Phase 4: work-items `work-loop` + `attend-queue` skills [TODO]

Review: architecture
Two thin-delta skills in `plugins/work-items/skills/`. One PR. Bodies invoke owned mechanics —
never restate selection/claim/lease/dispatch/triage machinery (constraint; the seam hub
`reference/tracker-seam.md` is read at invocation start per plugin norm).

| File | Action | What |
|---|---|---|
| `plugins/work-items/skills/work-loop/SKILL.md` | Create | loop layer (content below) |
| `plugins/work-items/skills/work-loop/evals/evals.json` | Create | per evals schema |
| `plugins/work-items/skills/attend-queue/SKILL.md` | Create | attended lane (content below) |
| `plugins/work-items/skills/attend-queue/evals/evals.json` | Create | per evals schema |
| `plugins/work-items/CHANGELOG.md` + `.claude-plugin/plugin.json` | Modify | version bump + any new `userConfig` keys (adaptive-cap bounds) |
| `scripts/skill-leaf-name-registry.txt` | Modify | register new leaf names (gate) |

`work-loop` delta only: per-cycle intake sweep (mechanical triage via `/work-items:triage`
autonomous lane — #459 CLOSED, autonomous mode exists); work-class gate in autonomy contract
terms (C2 → autonomous; C3 bug-fix-shaped → autonomous, feature-shaped → human-gated (operator
tightening, no justification needed per `admission-policy.md` L38-40); C4/C5/unclassified →
human-gated fail-closed); adaptive item cap (start 2, +1 after 3 consecutive clean, ceiling 3,
−1 on dirty, floor 1; no ramp while rate-limit warning live; QUOTA GUARD (operator-resolved
2026-07-23): frontier-tier items run at concurrency 1 with adaptive ceiling 2 — the general
ceiling 3 applies to non-frontier tiers only; composed-budget statement with
implement-dispatch per-item wave cap — note #573: userConfig cap enforcement not yet wired,
loop-body arithmetic is the interim enforcement); #572 workaround in-template (explicit
`/source-control:worktree` provisioning before dispatch); escalation + telemetry + stop shapes +
budget semantics BY CITATION to `docs/conventions/loop-lane/`; guard integration by citation to
reader contract; exit condition = seam frontier empty ∧ every open issue closed or has active
non-draft PR (GraphQL close-linkage per `adapters/github/README.md` L183-192); dynamic `/loop`
pacing via ScheduleWakeup. Q18 quality-signal surfacing: verify design intent against
`reference/pipeline-shape.md` at build (deferred-question arbiter: this plan).

`attend-queue` delta only: attended poll of (a) `needs-human` role-labeled items with
machine-marked comments, (b) untriaged intake via `/work-items:triage` attention view;
composes `/work-items:triage` + `/planning:interview`; writes answers back as issue comments;
flips items to `agent-ready` role label (resolved, never literal).

Cross-cutting work items (both skills, reviewer findings):

- Inline the guard operable floor (fixed tee path, 90% threshold, staleness rule,
  drain-then-pause) per the convention's inline-floor rule; cite reader contract for provenance.
- Every cross-plugin invocation (`/implementation:implement-dispatch`,
  `/source-control:worktree`, `/planning:interview`) follows the declared-or-guarded rule +
  seam-phrasing convention (gate + documented fallback per site) — same phrasing
  `plugins/work-items/skills/work/SKILL.md` already uses for the same targets.
- Naming (operator-resolved 2026-07-23): the Brief's `hitl-queue` violated the repo
  imperative-verb rule (PLUGIN-PHILOSOPHY L41); renamed to `attend-queue` (verb-first)
  throughout this Plan. `work-loop` is verb-first and passes.
- Exit-condition includes the drain-terminal state (all remaining open items human-gated →
  report + clean stop) per the Phase 2 invariant `[FALLBACK]`.
- Admission hardening (stress-test findings — the C3 classifier is the loop that benefits from
  admitting the item): (a) instantiation-level path/topic HARD GATE — any item touching SHA
  pins, checksums, or ci-workflows CLAUDE.md ground-rule surfaces is human-gated regardless of
  classification (the tool-version-drift advisories surface-read as C2 dep bumps but are
  trust-on-first-download checksum recomputation on security-critical pins, operator-owned per
  ci-workflows CLAUDE.md L52-58); (b) triage author-rule: workflow-bot-authored advisory issues
  → `needs-human` by default (also makes drain exits terminate against automated intake);
  (c) HITL ratifies every C3-autonomous admission for the first full drain (operator-adopted
  2026-07-23; earn-trust posture).

- **Sanity Check:** `/skill-quality:check work-loop` PASS and `/skill-quality:check attend-queue` PASS.
- **Sanity Check:** `bash scripts/validate-plugins.sh` exit 0 (evals schema, leaf-name, catalog gates).
- **Sanity Check:** `grep -c "conventions/loop-lane" plugins/work-items/skills/work-loop/SKILL.md` ≥ 1 and same for `attend-queue` (convention cited, not restated).
- **Sanity Check:** `grep -En "claude-(opus|sonnet|haiku|fable)-[0-9]" plugins/work-items/skills/{work-loop,attend-queue}/SKILL.md` returns empty (no hard-coded model IDs; tiers only).

### Phase 5: ci-workflows tracker binding [TODO]

One PR to ci-workflows. Pre-flight consumer check (contract surface = new tracked file): grep
ci-workflows workflows/scripts for `.work-item-tracker.json` readers — none expected (file is
new; seam tooling is the only reader).

| File | Action | What |
|---|---|---|
| `ci-workflows/.work-item-tracker.json` | Create | `{"schema_version":"1.0","provider":"github","config":{"lease_ttl_hours":24}}` (role_labels omitted → canonical defaults `agent-ready`/`needs-human`/`recurring` with loud warning; defaults match the org label taxonomy) |

Phase-entry checks: (a) `gh label list -R melodic-software/ci-workflows --limit 100` — confirm
`agent-ready`, `needs-human`, `recurring` exist; any missing label → STOP, route a `github-iac`
Pulumi PR first (label set is IaC-owned; never `gh label create`). (b) worker commit signing vs
`required_signatures` ruleset: RESOLVED by live verification during the stress-test — the
`signing` ruleset targets the default branch only, `base` allows squash as the sole merge
method, and GitHub web-flow signs API-created squash commits; worker feature-branch commits sit
outside the ruleset's ref scope. Retain a one-command build-time confirmation as a formality.

- **Sanity Check:** seam `capabilities` verb exit 0 in the ci-workflows checkout, and
  `list-frontier --autonomous` exit 0 returning a JSON envelope (the `health` verb does not
  exist — verified against `CONTRACT.md` verb table).
- **Sanity Check:** two-session claim race — CONCURRENT, not sequential (stress-test finding:
  sequential A-then-B passes even with a wide race window): fire both `claim <id>` calls in
  parallel; exactly one exits 0 and one exits 7, OR the residual is documented (GitHub comment
  listing propagation window — consequence is a duplicate PR, recoverable, caught by
  babysit/HITL; a jittered delay before the lease re-read shrinks it cheaply).

### Phase 6: standards lease-activation PR draft [TODO]

Prepare (never file) the standards change editing `conventions/process/issue-tracker.md` L37
block: record activation of assignee+lease claiming (trigger met: autonomous multi-worker
contention is now real), point at work-items `tools/work-item-tracker/CONTRACT.md` lease
protocol as the mechanism, retire the interim 🔒 marker text. "Never auto-filed" (Brief goal 4)
means: the session pushes the branch + prepares the PR body file and notifies the operator; NO
`gh pr create` is executed by the session or any lane — the operator files and merges.

- **Sanity Check:** branch exists on origin (`git ls-remote --heads origin <branch>` non-empty),
  PR body file present in the topic slice, operator notified in the session report;
  `gh pr list -R melodic-software/standards --head <branch>` returns EMPTY (nothing auto-filed).

### Phase 7: attended triage + launch + drain [TODO]

1. Attended triage pass (operator present) over live untriaged intake via `/work-items:triage`
   attention view — 10 zero-label issues at plan time (Brief said 14; count drifted, use live).
2. Launch three lanes: `work-loop` + `attend-queue` + babysit (babysit-PLAN Phase B3). Launch
   surface `[FALLBACK — confirm or override]`: FIRST cycle attended via interactive `/loop`
   (observability); unattended operation then moves to `claude-ops:lanes` (background named
   sessions) so budget-hit restart-requests reach the operator's one-command relaunch surface
   (`lanes restart` — operator-invoked by its contract; no automatic trigger consumes
   restart-requests today, per the loop-lane convention) — reviewer finding:
   an interactive `/loop` with nobody watching turns a #691 budget-hit into a silent drain
   stall. Until lanes-managed, the stall risk is documented in the lane report.
   PHASE-ENTRY GATE before any lanes migration (stress-test finding: statusline is verified
   interactive-only): verify statusline execution + tee freshness under ONE `--bg`
   lanes-launched probe session. If `--bg` sessions do not tee, either keep one attended anchor
   session alive (one machine, one tee file serves all readers) or defer the migration and
   document unattended operation as reactive-only.
3. Drain to exit condition; final report lists items closed / PR'd / escalated (acceptance
   criterion).

- **Sanity Check:** `gh issue list -R melodic-software/ci-workflows --state open --json number,labels` — zero items lacking triage outcome (every open item labeled or role-labeled).
- **Sanity Check:** exit-condition query — seam `list-frontier --autonomous` returns empty AND
  every remaining open issue has an OPEN close-linked PR (GraphQL probe) OR carries the
  `needs-human` role label (drain-terminal state, per the Phase 2 `[FALLBACK]` invariant).
- **Sanity Check:** guard behavior observed once: pause log entry at ≥90% or explicit
  reactive-only declaration on non-subscription auth; AND one resume observed without operator
  action after a `resets_at` passes (acceptance criterion covers resume, not just pause — if no
  window trips during the drain, record a synthetic tee-file probe: back-dated `resets_at`
  unpauses the loop).
- **Sanity Check:** one live `attend-queue` exercise: attention view lists ≥1 escalated +
  untriaged item in ONE view during the attended pass (acceptance criterion), captured in the
  session report.

Deferred acceptance criterion (explicit, with trigger): "second-repo adoption = one binding PR
\+ three sessions; zero plugin edits" is verifiable only when a second repo adopts — deferred to
that trigger (Brief "Deferred questions": multi-repo scale-out, USER-RESERVED).

## Blast radius

HIGH — new org-wide convention constraining all future lanes; new plugin with hooks + user-scope
statusline wiring (affects every session on the machine); autonomous PR authorship + (via babysit)
merges in an org repo with an org credential; multiple stress-test triggers match (infrastructure,
new conventions/enforcement, cross-plugin architecture, security-sensitive). Formal stress-test
REQUIRED.

## Stress-test summary

Two independent fresh-context rounds (2026-07-23):

- **Plan reviewer** (Step 3): 1 CRITICAL / 11 IMPORTANT / 5 SUGGESTION — all verified against
  sources and fixed in place. Clusters: rate-limit-guard seam doctrine (setup must not mutate
  user settings; operable floors must be inlined, not cited; dead userConfig; atomic tee;
  pause-window semantics) and unattended-termination realism (drain-terminal state, restart
  owner, compaction-durable loop state). Also: `health` verb didn't exist (→ `capabilities`),
  topic-docs contract kinds, naming grammar, Phase 6 filing ambiguity.
- **/devils-advocate** (Step 4): 2 CRITICAL / 3 HIGH / 6 MEDIUM / 2 LOW. Must-fix all applied
  or routed to operator: merge-authority contradiction with the autonomy matrix (→ Open
  Decision 5); babysit autopilot premise invalidated post-launch (→ Open Decision 6, babysit
  PLAN); `--bg` statusline tee verification gate (Phase 7); C3 self-classification hardening
  (Phase 4 path/topic gate + bot-author triage rule + HITL ratification period); quota
  economics surfaced (Open Decision 7). MEDIUMs absorbed as documentation-pass items across
  Phases 2/3/5. LOW #12 (squash-merge satisfies `required_signatures`) was VERIFIED LIVE
  during the stress-test — signing ruleset targets the default branch only, squash is the only
  allowed merge method, GitHub web-flow signs API squash commits; Phase 5's build-time
  confirmation retained as a formality.
- One research-iterate round sufficed; no unresolved CRITICAL/HIGH remains outside the three
  operator decisions.

## Execution shape

Phases are PR-boundary-sequential on the critical path; one genuine parallel opportunity:

| Phase | Surface | Basis |
|---|---|---|
| 1 | main-session | mechanical move + branch setup, trivial |
| 2 | main-session | judgment-heavy convention authoring; playbook-governed |
| 3 | main-session (+ fresh-context review sub-agents) | security-sensitive plugin; test-first scripts |
| 4 | main-session (+ fresh-context review sub-agents) | skill authoring, playbook-governed |
| 5 | main-session | small config PR + live race test needs two sessions (second is a sub-agent/worktree session) |
| 6 | main-session | operator-routed draft |
| 7 | main-session, operator present | attended triage + launch |

Dependency graph: 1 → 2 → {3, 4} → 5 → 7; 6 independent after 5's lease mechanism proves out;
babysit-PLAN B1/B2 parallel-safe with Phase 4 (disjoint plugin dirs), B3 joins at 7.
Wave option after Phase 2 merges: Phase 3 ∥ Phase 4 ∥ babysit B1+B2 (file-disjoint across
`plugins/rate-limit-guard/`, `plugins/work-items/`, `plugins/source-control/`) — material saving
if run as parallel sessions/agents; cost: 3 concurrent build agents multiply tokens. Default
recommendation: sequential 3 → 4 in one session (shared fresh-docs fetches amortize), babysit
B1/B2 in the operator's parallel session per succession note. Sequential fallback: if any
parallel build session reports scope-fence violation or cross-plugin edit, abort it and fold the
work into the main session sequentially.

## Open questions

None — all seven approval-round decisions resolved by the operator 2026-07-23:

1. Telemetry comment home → per-lane tracking issue in the TARGET repo (ci-workflows);
   convention doc records it at Phase 2. (Operator: "rest makes sense".)
2. Naming → renamed `hitl-queue` to `attend-queue` (verb-first) throughout the Plan.
3. Drain-terminal stop shape → adopted (modifies briefed exit condition).
4. Unattended launch surface → adopted: attended `/loop` first cycle, then `claude-ops:lanes`
   gated on the `--bg` tee probe — with the operator's coupling caveat encoded: lanes is a
   supporting, one-directional launcher; loop skills never depend on claude-ops (guarded
   if-installed, `/loop` fallback documented).
5. Merge authority → configurable autonomy ladder; shipped default = human merge for all but
   gate-proven bot/C2 mechanical PRs; higher rungs (through full autonomy with frontier
   subagents driving to merge) opt-in via tracked-config flip = the matrix's recorded
   human-ratified promotion.
6. Babysit tier for ci-workflows → WORKER (autopilot premise invalidated post-launch).
7. Quota economics → frontier concurrency 1 + adaptive ceiling 2 for frontier items (general
   ceiling 3 for other tiers).

## Handoff to implementation

### User-approval gates

- Phase 5 phase-entry (a): any missing role label → STOP; github-iac Pulumi PR is operator work.
- Phase 6: draft PR routed to operator; no lane files or merges it.
- Phase 7 launch: operator present for triage; lane launch is operator-initiated.
- `[FALLBACK]` rows in the decisions table (presentation) — confirm or override before the
  affected phase starts.

### Execution shape ([EXEC-SHAPE] tagged)

- [EXEC-SHAPE] Sub-topic promotion DECLINED: PR-boundary phases already give independent commit
  boundaries; the two-track split (two PLAN files) is the operative decomposition; a third level
  would scatter the contract. Evidence: topic-docs convention supports multi-file slices.
- [EXEC-SHAPE] #691 implementation shape: budget-hit emits restart-request telemetry + clean loop
  stop; restart is launcher/operator-initiated. Evidence: `claude-ops` lanes SKILL.md verified
  behavior — a running loop cannot `/clear` or restart itself.
- [EXEC-SHAPE] Lane prompts are one-line skill invocations stored via the `claude-ops` lanes
  `prompt_dir` seam (`.work`, #480 forward dependency) — no new prompt storage built.
- [EXEC-SHAPE] Phase ordering 3 → 4 sequential in one session; babysit track parallel per
  succession note. Scope fences = plugin directory boundaries listed per phase.

### Mechanical work

- One PR per phase (2, 3, 4, 5, 6); commit convention per claude-code-plugins norms; topic docs
  ride build branches; phase tags advanced in PLAN.md as each completes.
- Verification checkpoints: repo CI (`ci-status`) green per PR; `skill-quality:check` per new
  skill; fresh-context review sub-agent before each PR (producer ≠ critic).
- Close-out at final PR: `/planning:plan close-out` (publish PLAN to PR, graduate ADR candidates
  — the loop-lane convention itself is the durable doc; prune the contract slice).
