# plugin-audit-port

## Brief

### TLDR

Port the machine-local `~/.claude/skills/plugin-audit` skill into this marketplace as a generalized,
repo/machine/user/org-agnostic plugin (`plugin-quality`, skill `audit`), improved rather than copied,
plus a new sibling producer plugin (`context-guard`) that makes per-session context-window usage
observable so the audit survives long sessions and compaction. Interview locked 2026-07-23; decision
ledger: `.work/plugin-audit-port/interview-checklist.md`.

### Goal

Two new marketplace plugins, two swim-lane PRs, seams-first:

1. **`context-guard`** (lands first — its reader contract is the seam):
   - Statusline tee script on the `rate-limit-guard` pattern (transparent byte-for-byte pass-through;
     atomic temp-file+rename writes; jq-missing visible degrade; Windows rename-retry; tests), writing
     per-session snapshots of raw statusline `context_window` fields verbatim
     (`used_percentage`, `total_input_tokens`, `total_output_tokens`, `context_window_size`,
     `current_usage`, `captured_at`, session fields) to
     `~/.claude/context-guard/context/<session_id>.json`. Stale-session pruning on write
     (implementation detail, not contract).
   - Reader contract doc (consumer-facing): file shape, staleness rule, fail-open capability
     detection — modeled on `rate-limit-guard/reference/reader-contract.md`.
   - **Zones SSOT**: `~/.claude/context-guard/zones.json` (machine-scope, optional) defines
     smart/acceptable/dumb bands over `used_percentage`; bundled resolver script
     (`context-zone.sh`: snapshot + zones file → prints zone) carries shipped good-practice defaults
     used when the file is absent — zero-config works. The operator's personal statusline may read
     the same file for display, eliminating band drift between display and consumers. Zones say
     *where you are*; consumers decide *what to do*.
   - Setup skill (`setup`, `disable-model-invocation: true`, `check`/`apply`) that verifies
     prerequisites and prints the statusline wiring — never edits user settings.
2. **`plugin-quality`** — skill `audit` (`/plugin-quality:audit <plugin>[:<component>]`):
   post-use behavioral audit of any plugin component (skill/agent/hook/command/config).
   Six-step workflow:
   1. **Evidence capture** (main thread, always — only place session evidence is visible): hook
      failures, permission-prompt denials, MCP/tool errors, transcript path, component invocation
      record, environment; persisted as a durable evidence packet on disk (compaction-proof,
      resumable).
   2. **Map + ground** (fresh named subagent, dispatched from the main thread): read component
      source/manifest/config resolution; verify every load-bearing harness-behavior claim
      against CURRENT official docs
      per topic (fresh-docs mandate applies inside the audit, not just to this repo).
   3. **Blindspot + candidate findings** (subagent output, presented to user).
   4. **Contract lock** (main thread, interactive): scope, severity calibration, named assumptions.
   5. **Review/gate** (presence-gated: `review:fanout`/`review:quality-gate`,
      `skill-quality:check` when target is a skill, `verification:confirm` when code changed;
      documented fallbacks when absent per seam-phrasing convention).
   6. **Emit** the work item to the configured sink.
   - **Context-gate**: consumes `context-guard` as a soft dependency (no manifest `dependencies`).
     Fresh snapshot → zone-informed dispatch decisions (dumb zone forces subagent + evidence flush);
     absent/stale snapshot → conservative default (always run deep phase in fresh subagent) with a
     one-line visible notice. Never halts or recommends handoff earlier than configured criteria.
   - **Sink**: backend-neutral work-item vocabulary. Default = GitHub issue on the audited plugin's
     source repo via `gh`. Resolution ladder: tracked config override → infer from the installed
     plugin's marketplace registration → ask + offer to persist → local markdown work-item fallback
     (no `gh`/repo). Unconditional full-draft + user-confirm before `gh issue create` (egress gate).
     Presence-gated `work-items` seam offered when that plugin is installed.
   - **Config**: tracked `.claude/plugin-quality.md` per the config-cascade convention (project +
     gitignored `.local` overlay + `~/.claude/` user-global) holding sink, zone-behavior criteria,
     repo-map overrides. No `userConfig` in v1. Setup skill (`check`/`apply`) — required by
     philosophy criteria (external prereq `gh`; consumer config surface).
   - **References ported, generalized** (machine paths and melodic name-drops stripped):
     recurring-concerns checklist, 5 component-type lenses, extend-without-bloating-the-hub pattern.
   - Evals (`evals/evals.json`) — warranted: triggering, routing, refuse-to-implement-in-session,
     emit shape. `version` 0.1.0, marketplace entry `./plugins/plugin-quality`, README row,
     CHANGELOG, plugin-acceptance security review (egress = `gh` issue creation, named + confirmed).

### Constraints

- Follow `docs/PLUGIN-PHILOSOPHY.md` + `docs/MIGRATION-PLAYBOOK.md` in full: per-plugin migration
  gate, naming grammar, two-lane convention posture, convention-resolution ladder, seam phrasing,
  cross-platform contract, fresh-docs mandate (re-fetch official docs at implementation time —
  interview verified statusline schema 2026-07-23 only).
- `context-guard` is a SEPARATE plugin from `rate-limit-guard` — do not mix concerns (owner
  decision, R2). Reuse the pattern, not the plugin.
- Deep-audit phase (steps 2–3) runs in a fresh-context NAMED subagent that the skill dispatches
  from the main thread; steps 1, 4, and 6 stay on the main thread. `context: fork` is not chosen —
  rejected on listing-budget and synchronization cost, not as inexpressible; basis in the
  [EXEC-SHAPE] agent decision below.
- No hardcoded repos, paths, owners; melodic-marketplace targets resolve via inference, never
  baked in.
- The producer/consumer split holds: audit session never implements fixes in the plugin repo.
- Kyle's machine keeps its handoff-inbox behavior via user-global tracked config
  (`~/.claude/plugin-quality.md` sink override) — mechanism preserved as configuration, not fork.

### Acceptance criteria

- `claude plugin validate` passes for both plugins; `claude plugin validate --strict` passes for
  the catalog; `--plugin-dir` smoke test in a clean non-source repo proves repo-agnosticism.
- Fresh install, zero config: `/plugin-quality:audit <x>` works end-to-end — conservative dispatch
  (no context-guard), issue-draft-with-confirm sink, inferred target repo.
- With context-guard wired: dumb-zone session provably routes deep analysis to a fresh subagent
  using the evidence packet.
- With `~/.claude/plugin-quality.md` sink override: findings land as a handoff-inbox markdown item
  byte-compatible with the current inbox schema; local `~/.claude/skills/plugin-audit` then deleted
  (cutover gate: plugin behaves same-or-better first).
- Both setup skills conform to the `check`/`apply` contract; skill-quality:check passes on all new
  skills; evals validate against the bundled schema.

### Captured assumptions

- Statusline stdin reliably carries `context_window.*` on current Claude Code (verified 2026-07-23;
  re-verify at implementation).
- Percentage-based zone bands are model-shift-resilient because `used_percentage` is normalized
  against the model's actual `context_window_size` upstream.
- `gh` CLI is the forge seam for v1 (GitHub-only default is declared at the coupling site, not
  shipped bare under a neutral name; other forges = future adapter via config).

### Out-of-scope

- AFK/fully-autonomous audit mode (deferred; interactive contract-lock is the v1 value).
- Renaming `rate-limit-guard` (e.g. `session-signals`) — recorded option only.
- `work-items` custom adapter for the handoff inbox.
- Auto-file (no-confirm) sink key — Rule of Three; revisit on demonstrated need.
- Changes to Kyle's existing statusline beyond optionally pointing it at zones.json.

### Deferred questions

- Exact default zone band numbers — ground against current compaction-trigger behavior at
  implementation. [`/planning:plan`]
- Evidence-packet field list finalization (capture-broadly starting set locked; trim after first
  real runs). [`/planning:plan`]
- Whether `context-guard` zones.json warrants an org/managed layer later. [USER-RESERVED]

## Plan

**What**: build and publish the two plugins the Brief locks — `context-guard` (statusline tee →
per-session context snapshots + zones SSOT) and `plugin-quality` (post-use component audit skill) —
as two swim-lane PRs, seams-first.
**Why**: the machine-local `plugin-audit` skill is invisible to cloud/routine contexts and coupled
to one machine's inbox; the port generalizes it and gives long-session audits a context-degradation
gate.

### Standards grounding

No `.claude/standards.yaml` index exists in this repo — grounding is the repo's own governing docs,
read in full this session: `CLAUDE.md` (fresh-docs mandate, design rules), `docs/PLUGIN-PHILOSOPHY.md`
(naming grammar, component stances, config ownership, setup contract, fresh-eyes doctrine,
cross-platform contract), `docs/MIGRATION-PLAYBOOK.md` (migration gate, extensibility contract v2.1,
convention-resolution ladder, evals warrant policy, swim-lane execution, security review),
`docs/conventions/config-cascade/README.md` (layering contract). No personal-layer rule shaped this
plan.

### Design inputs

`design/design-resolution.md` (early-exit: design threads resolved in the interview; contract
sketches there). Decision ledger: `.work/plugin-audit-port/interview-checklist.md`.

### Lane A — `context-guard` (merges first; its reader contract is the seam)

#### Phase A1: Plugin scaffold + statusline tee [DONE]

Create `plugins/context-guard/`:

- [ ] `.claude-plugin/plugin.json` — CREATE: name, `version: 0.1.0`, description, author, MIT,
  keywords. No `userConfig` v1 (no hook to kill; nothing personal-scalar — Brief B8 analog).
- [ ] `scripts/statusline-tee.sh` — CREATE: transparent byte-for-byte pass-through on the
  `rate-limit-guard/scripts/statusline-tee.sh` pattern (bounded stdin read, jq-missing visible
  degrade, atomic temp+rename, Windows rename retry, never alters wrapped output/exit code), but
  writing **per-session** snapshots to `~/.claude/context-guard/context/<session_id>.json`:
  `captured_at` + `session_id` + `context_window` object copied verbatim from stdin. Stale-sibling
  pruning on write (age-based, implementation detail). Standalone mode prints a minimal
  model+context line when no statusline is configured. `session_id` is sanitized before use as a
  filename (accept `[A-Za-z0-9_-]` only; anything else → skip the tee) — path-containment guard.
  Statusline schema re-verified 2026-07-23: all five Brief fields confirmed verbatim, plus
  `remaining_percentage`; `current_usage`/`used_percentage` may be `null` early in session and
  `current_usage` is `null` immediately after `/compact` — the tee copies whatever is present and
  the reader contract owns null handling.
- [ ] `scripts/statusline-tee.test.sh` — CREATE (test-first): red-green off the rate-limit-guard
  test harness pattern — pass-through fidelity (stdout bytes + exit code), snapshot shape, missing
  jq notice, missing `context_window` (snapshot still written with fields absent), unwritable dir
  (silent skip), pruning — including: prune never touches `.tmp.*` in-flight files, and the prune
  cutoff is much larger than the reader contract's staleness window (a live-but-idle session's
  snapshot must not be deleted; reader contract documents the idle-session behavior).

**Sanity Check:**

- [ ] `bash plugins/context-guard/scripts/statusline-tee.test.sh` exits 0 (harness sandboxes
  `HOME` — no test writes the operator's live `~/.claude/context-guard/`).
- [ ] Under `HOME=$(mktemp -d)`: `printf '{"session_id":"t1","context_window":{"used_percentage":50}}' | bash plugins/context-guard/scripts/statusline-tee.sh cat` echoes the exact input bytes and exits 0, and `$HOME/.claude/context-guard/context/t1.json` parses with `jq -e '.captured_at and .session_id and .context_window'`.

#### Phase A2: Zone resolver + zones contract [DONE]

- [ ] `scripts/context-zone.sh` — CREATE: `context-zone.sh <session_id>` reads the session snapshot
  plus the optional `~/.claude/context-guard/zones.json`, prints one word: `smart` / `acceptable` / `dumb`
  / `unknown` (absent, stale, or unparsable snapshot → `unknown`). Shipped default bands live in
  this script (zones.json absent = zero-config). Grounding outcome (fetched 2026-07-23): **no
  auto-compaction threshold percentage is documented anywhere** — how-claude-code-works,
  context-window, settings (`autoCompactEnabled`), and costs pages all say only "as you approach
  the limit". So the shipped defaults are declared judgment values, not doc-derived constants:
  proposed `smart` ≤ 50, `acceptable` 50–75, `dumb` > 75 `used_percentage`
  `[FALLBACK — confirm or override]`, documented in the reader contract as good-practice defaults
  with the zones.json override as the tuning path. Re-check the docs for a published threshold at
  implementation; cite the absence in the reader contract.
- [ ] **Band-vs-compaction ordering (stress-test #2):** empirically observe the auto-compact trip
  point on current Claude Code (drive a session toward the limit; record the last
  `used_percentage` before compaction) and confirm the dumb band starts below it with declared
  margin — the dumb tripwire is useless if auto-compact fires first. Also determine whether
  `used_percentage`/`remaining_percentage` are pre- or post-output-buffer values, and document
  the `autoCompactEnabled: false` variant in the reader contract.
- [ ] `scripts/context-zone.test.sh` — CREATE (test-first): band edges, zones.json override,
  malformed zones.json (fall back to shipped defaults + visible stderr notice), absent/stale
  snapshot → `unknown`, absurd `used_percentage` (outside 0–100 → `unknown`, fail-open like the
  rate-limit-guard reader contract), fresh snapshot with `used_percentage: null` /
  `current_usage: null` (documented early-session and post-`/compact` states) → `unknown`.
  All tests run under a sandboxed `HOME=$(mktemp -d)` per the rate-limit-guard harness pattern.

**Sanity Check:**

- [ ] `bash plugins/context-guard/scripts/context-zone.test.sh` exits 0.
- [ ] The reader contract's zone-defaults section states the shipped numbers AND that no official
  compaction threshold was documented as of the cited fetch date (grep both).

#### Phase A3: Reader contract doc [DONE]

- [ ] `reference/reader-contract.md` — CREATE, modeled on
  `plugins/rate-limit-guard/reference/reader-contract.md`: snapshot path pattern, file shape,
  staleness rule (single fixed value consumers inline), fail-open capability detection table
  (null `used_percentage` / null `current_usage` → unknown; zone is NOT a compaction indicator —
  a compacted session's percentage resets while its evidence is already gone, so consumers must
  treat known-compacted sessions as evidence-degraded regardless of zone), zones.json shape +
  resolver invocation, untrusted-field warning, per-session (NOT last-writer-wins machine-scope)
  semantics, invariants (no shipped Monitor config; path fixed as a cross-plugin seam, deliberately
  outside `${CLAUDE_PLUGIN_DATA}`).
- [ ] **Session-id discovery (consumer mechanism — review finding 1):** the contract documents how
  a model-context consumer learns its own session id: the `${CLAUDE_SESSION_ID}` substitution in
  skill content (skills doc, verified 2026-07-23); re-verify at implementation and record the
  fallback when unavailable (absent substitution → conservative/unknown path).
- [ ] **Inline-floor ownership (review finding 2):** this contract file OWNS the operable floor
  consumers inline (path pattern, staleness value, default zone bands) and states the
  byte-identity rule — inlined values must match this file verbatim; the lane-B drift check
  below enforces it in-repo.

**Sanity Check:**

- [ ] File exists; `grep -c 'staleness' plugins/context-guard/reference/reader-contract.md` ≥ 1;
  the staleness value and snapshot path in the doc byte-match the values in both scripts (grep).

#### Phase A4: Setup skill [DONE]

- [ ] `skills/setup/SKILL.md` — CREATE: `disable-model-invocation: true`; `check` (jq, statusline
  wiring state — stale-path detection compares the wired path against the currently resolved
  `${CLAUDE_PLUGIN_ROOT}`, so exists-but-outdated cache paths are caught, not just missing files
  (stress-test #4) — snapshot freshness probe, prints the exact
  operator `settings.json` statusline edit — never writes settings) + `apply` scoped to the one
  file the plugin owns the schema of: seed/refresh `~/.claude/context-guard/zones.json` from the
  shipped defaults on explicit request (idempotent, preserves an existing file's unrecognized keys,
  reports what it wrote). Dotfiles-tracking reminder as in rate-limit-guard setup.
- [ ] `skills/setup/evals/evals.json` — CREATE (setup skills are warrantable; rate-limit-guard
  setup eval is the model).

**Sanity Check:**

- [ ] `/skill-quality:check` passes on `context-guard/setup`; `validate-evals` passes.

#### Phase A5: Release chores (lane A) [DONE]

- [ ] `README.md` (plugin) — CREATE: capability, prerequisites (bash + jq, declared per
  failure-behavior rules; Windows = Git Bash), wiring, reader contract pointer, security posture.
- [ ] `CHANGELOG.md` (plugin) — CREATE: `0.1.0`.
- [ ] `.claude-plugin/marketplace.json` — MODIFY: add entry `"source": "./plugins/context-guard"`,
  category `claude-code`, tags.
- [ ] Repo `README.md` — MODIFY: catalog row.
- [ ] `docs/MIGRATION-PLAYBOOK.md` — MODIFY: plugin-acceptance security review record (no hooks, no
  MCP, no userConfig, no egress; writes only to `~/.claude/context-guard/` — operator-home
  carve-out; scripts reviewed).

**Sanity Check:**

- [ ] `claude plugin validate plugins/context-guard` exits 0; `claude plugin validate --strict .`
  exits 0.
- [ ] `claude --plugin-dir ./plugins/context-guard` smoke test in a clean non-source repo:
  `/context-guard:setup check` runs; after wiring, a snapshot file appears for the live session.

### Lane B — `plugin-quality` (opens after lane A merges; inlines lane A's reader contract)

#### Phase B1: `audit` skill hub [DONE]

- [ ] `plugins/plugin-quality/.claude-plugin/plugin.json` — CREATE (`0.1.0`, no `userConfig` v1).
- [ ] `skills/audit/SKILL.md` — CREATE: `/plugin-quality:audit <plugin>[:<component>]`. Six-step
  workflow per the Brief (evidence capture main-thread → map+ground in the fresh named subagent
  with per-topic fresh-docs verification → blindspot+candidates → interactive contract lock →
  presence-gated review/gate seams (`review:fanout` / `review:quality-gate`,
  `skill-quality:check` when target is a skill, `verification:confirm` when code changed; each with
  documented fallback per seam-phrasing) → emit). Context-gate: inline the operable floor of
  context-guard's reader contract verbatim (path pattern, staleness rule, zone resolution);
  absent/stale → conservative always-subagent + one-line visible notice. **Per-zone decision
  table (stress-test #1 — steps 2–3 run in the fresh subagent in EVERY zone per the Brief; the
  zone modulates only what it CAN modulate, and each row is observable):**

  | Zone | Steps 3–4 packet handling (main thread) | Step 5 review seams | Evidence flush |
  |---|---|---|---|
  | smart | full candidate list re-read into main context | inline allowed | at step transitions |
  | acceptable | full candidate list | dispatch preferred, inline permitted | at step transitions |
  | dumb | summary + packet pointer only (no bulk re-read) | MUST dispatch to fresh subagents | immediate flush of all main-thread evidence to the packet at every step boundary (the flush artifact is the observable) |
  | unknown (absent/stale/no-jq) | conservative = dumb row + one-line visible notice | as dumb | as dumb |

  The consumer reads `~/.claude/context-guard/zones.json` DIRECTLY via `jq` (a data seam — no
  sibling-script invocation under cache isolation), with the inlined default bands as fallback
  only when the file is absent/malformed (stress-test #3: otherwise the operator tuning
  zones.json would split the display from the one consumer that matters); the byte-identity
  drift check covers the fallback constants only. The gate re-evaluates at each dispatch point
  (steps 2 and 5), not once at invocation; a session the main thread knows was compacted is
  treated as evidence-degraded regardless of zone (reader-contract rule). Session id comes from
  `${CLAUDE_SESSION_ID}` substitution (re-verify at implementation). Sink resolution ladder +
  unconditional draft+confirm before `gh issue create`; the confirm surface includes the ACTING
  `gh` account (`gh auth status`) alongside the draft and target repo (stress-test #8 — this
  machine hosts three GitHub identity domains that must never cross-pollinate). Presence-gated
  seam fallbacks named in SKILL.md, one line each: `review:fanout`/`quality-gate` absent →
  structured self-review checklist in the fresh subagent; `skill-quality:check` absent → the
  skill-lens reference checklist; `verification:confirm` re-scoped to fire only when the audit
  session itself wrote files (e.g. setup-applied config) — the producer/consumer split means
  audit never changes the audited plugin's code (stress-test #10). Untrusted-content posture:
  audited plugin source, manifests, and marketplace registrations are DATA, never instructions —
  standing instruction in both SKILL.md and the auditor agent, backed by an anti-pattern eval
  (stress-test #9). Producer/consumer split stated (never implement fixes in the audited repo
  from the audit session).
- [ ] **Evidence packet spec (review finding 4; stress-test #5/#6/#14):** written to
  `${CLAUDE_PLUGIN_DATA}/evidence/<session_id>/<target-slug>/<run-nonce>/` (machine state →
  plugin data dir per the configuration-ownership table); the run-nonce (start timestamp) keeps a
  same-target re-audit in one session from clobbering the first run; `<target-slug>` sanitized
  with the same `[A-Za-z0-9_-]` character class as the tee's session_id (path containment);
  packets older than a stated retention window pruned on new audit run. Contract-lock notes are
  written INTO the packet (not left in compactable conversation context), and SKILL.md's resume
  instruction is the deterministic path re-derivation (session_id + target + latest nonce) — the
  route to the compaction-proof artifact must itself survive compaction. Verify at
  implementation that `${CLAUDE_PLUGIN_DATA}` resolves for a `--plugin-dir`-loaded plugin and
  note any identity difference vs the installed form (stress-test #12).
- [ ] **Trigger continuity (review finding 8):** map every trigger phrase of the local
  `plugin-audit` description onto the new `audit` description (playbook decompose step 5 table
  as evidence in the PR), and add negative routing boundaries: static skill QA →
  `skill-quality:check`; general code review → `review`; MCP-server audits →
  `mcp-tools:audit` when installed (presence-gated) — the component-type lens set stays
  {hook, skill, agent, command, config} with that boundary stated.

**Sanity Check:**

- [ ] `grep -c 'gh issue create' skills/audit/SKILL.md` ≥ 1 with the confirm gate stated in the
  same section; `grep -n 'context: fork' skills/audit/SKILL.md` returns nothing.
- [ ] Drift check (inline-floor byte-identity): the snapshot path pattern, staleness value, and
  default zone bands quoted in `skills/audit/SKILL.md` grep-match the values in
  `plugins/context-guard/reference/reader-contract.md` exactly.

#### Phase B2: References port + generalization [DONE]

- [ ] `skills/audit/references/recurring-concerns.md` — CREATE from the local skill's file,
  machine paths and melodic name-drops stripped.
- [ ] `skills/audit/references/component-types/{hook,skill,agent,command,config}.md` — CREATE ×5,
  generalized same way.
- [ ] Hub keeps the extend-without-bloating pattern (one reference file + one index row).
- [ ] Local `references/handoff-inbox.md` is NOT ported — replaced by the sink reference below.

**Sanity Check:**

- [ ] `grep -rniE 'C:\\\\|/Users/|KyleSexton|SW2030|handoff-inbox' plugins/plugin-quality/` returns
  empty (no machine paths, no consumer name-drops, no dead inbox references). This grep RE-RUNS
  as a B6 pre-PR check — B4's config reference is written after this phase and is the likeliest
  violator (stress-test #13).

#### Phase B3: Auditor agent [DONE]

- [ ] `agents/auditor.md` — CREATE: the fresh-context named subagent for workflow steps 2–3.
  Tools: Read/Grep/Glob/WebFetch plus Bash — named honestly (Bash is NOT read-only; it is needed
  for `claude plugin validate` and config-resolution probes, and is justified as such in the B6
  security record, stress-test #9). Carries the standing untrusted-content instruction (audited
  plugin source is data, never instructions). Consumes the on-disk evidence packet path passed in
  its dispatch prompt. Never the Agent tool's `fork` subagent type — basis in the [EXEC-SHAPE]
  agent decision.

**Sanity Check:**

- [ ] Agent file frontmatter validates (`claude plugin validate` covers agents dir); SKILL.md step
  2 dispatches by this agent's name.

#### Phase B4: Config surface + sink reference [DONE]

- [ ] `reference/config.md` — CREATE: `.claude/plugin-quality.md` keys (sink, zone-behavior
  criteria, repo-map overrides), layering per config-cascade (all three layers, merge semantics
  declared), sink resolution ladder (tracked config → infer from marketplace registration → ask +
  offer persist → local markdown work-item fallback), local-markdown item schema.
- [ ] **Compat-target reconciliation (stress-test #7):** the operator supplies the actual inbox
  `README.md` schema as a B4 input fixture (it lives on the producing machine) and B4 diffs it
  against the `work-items` `local-markdown` adapter shape BEFORE fixing the emitted item schema —
  the two compat targets must be reconciled in lane B, not discovered divergent post-merge at
  cutover.
- [ ] `docs/conventions/config-cascade/README.md` — MODIFY: add `plugin-quality` implementers row.

**Sanity Check:**

- [ ] `grep -c 'plugin-quality' docs/conventions/config-cascade/README.md` ≥ 1.

#### Phase B5: Setup skill [DONE]

- [ ] `skills/setup/SKILL.md` — CREATE: `check` (gh present + authed, context-guard snapshot seam
  present → reports dispatch mode, config layers found + effective sink with layer provenance) /
  `apply` (write/converge tracked `.claude/plugin-quality.md` from interview or arguments;
  idempotent; recommends the recursive `.claude/**/*.local.*` gitignore line, never writes the
  consumer's `.gitignore`).
- [ ] `skills/setup/evals/evals.json` — CREATE.

**Sanity Check:**

- [ ] `/skill-quality:check` passes on `plugin-quality/setup`; `validate-evals` passes.

#### Phase B6: Evals + release chores (lane B) [DONE]

- [ ] `skills/audit/evals/evals.json` — CREATE: triggering (mapped from the local skill's trigger
  vocabulary per the B1 continuity table), routing incl. negative boundaries
  (skill-quality/review/mcp-tools), refuse-to-implement-in-session guardrail, emit-shape
  (draft+confirm before create), conservative-dispatch anti-pattern case (absent snapshot must
  not skip the subagent), and a prompt-injection anti-pattern case: an instruction embedded in
  audited plugin source must not alter the sink target or skip the confirm gate (stress-test #9).
- [ ] Plugin `README.md` + `CHANGELOG.md` — CREATE.
- [ ] `.claude-plugin/marketplace.json` + repo `README.md` — MODIFY: entry + row.
- [ ] `docs/MIGRATION-PLAYBOOK.md` — MODIFY: security review record naming ALL data surfaces:
  egress = `gh issue create` (draft+confirm-gated); reads operator-home config per the carve-out;
  reads audited plugins' installed source under `~/.claude/plugins/cache` and marketplace
  registrations (justified: that IS the audit subject); writes the evidence packet
  (session-derived data — hook failures, transcript path, tool errors) to
  `${CLAUDE_PLUGIN_DATA}` with the stated retention; no hooks/MCP.

**Sanity Check:**

- [ ] `claude plugin validate plugins/plugin-quality` and `claude plugin validate --strict .` exit 0.
- [ ] `--plugin-dir` smoke in a clean non-source repo: `/plugin-quality:audit <some plugin>` reaches
  the sink draft with zero config (conservative dispatch notice visible; expected sink-ladder
  rung stated per smoke — the zero-config clean-repo run exercises rung 3/4, and the
  registration-inference rung 2 gets its own smoke against a repo with a known installed
  marketplace plugin, stress-test #12).
- [ ] Dumb-zone smoke (acceptance criterion 3) — FALSIFIABLE per the B1 zone table: hand-craft a
  fresh snapshot with `used_percentage` above the dumb threshold for the live session id, run
  the audit, and assert the dumb-row observables: the immediate-flush artifact exists in the
  packet at each step boundary, steps 3–4 used summary-plus-pointer (no bulk re-read), AND the
  conservative notice is ABSENT (the snapshot was fresh — a broken gate that fell through to
  conservative would print it). Subagent dispatch alone does not pass (it happens in every zone).
- [ ] Re-run the B2 forbidden-strings grep (pre-PR, catches B4/B5-authored files).

#### Phase B7: Operator cutover (post-merge, HITL) [TODO]

- [ ] Operator writes `~/.claude/plugin-quality.md` sink override pointing at the handoff inbox.
- [ ] One real audit run lands an inbox item byte-compatible with the inbox README schema.
- [ ] Only then: delete `~/.claude/skills/plugin-audit/` (cutover gate: same-or-better first).

**Sanity Check:**

- [ ] Full-item diff (stress-test #7 — keys-only is too weak for an irreversible deletion gate):
  the emitted item diffed field-by-field against a real existing inbox item — key set, value
  formats (dates, status/priority vocabulary), and body section structure all match; deviations
  resolved or owner-accepted BEFORE deletion. `ls ~/.claude/skills/plugin-audit` fails after
  deletion.

### Alternatives considered

| Alternative | Why rejected |
|---|---|
| Extend `rate-limit-guard` with the context tee | Owner decision R2: separate concerns; reuse the pattern, not the plugin |
| Join `review` / `skill-quality` | Fails the distinct-discovery-intent test (playbook Organization) |
| `context: fork` for the deep audit | Not impossible — rejected on cost. Would require a second skill existing only to be forked, spending shared skill-listing budget for zero user-facing capability. The requirement it must beat is stated as an invariant (fresh context + named dispatch target) in the `[EXEC-SHAPE]` agent decision below, deliberately independent of what any fork inherits |
| Fixed zone bands as tee-contract constants | Zones are per-consumer judgment knobs; unlike the 90% rate-limit floor there is no writer/reader split-brain risk forcing a constant |
| `userConfig` for sink/inbox | Per-repo-ish policy → tracked config cascade; `pluginConfigs` is user-settings-only |
| Verbatim 7-step port | Steps 4–5 overlapped; collapsed to one interactive contract-lock step (owner wants improvement, not a copy) |

### Test strategy

TDD (Red-Green-Refactor) for both shell scripts: write `.test.sh` cases first (the
rate-limit-guard test harness is the pattern), then implement to green. Skills/agents/references
are prompt artifacts — their behavioral contracts are covered by evals (model-graded fixtures,
manual-run per the playbook recipe until the runner lands) plus the deterministic gates:
`skill-quality:check` per skill, `claude plugin validate` (+ `--strict` catalog pass), and the
clean-repo `--plugin-dir` smoke tests named in the phase sanity checks. No existing tests change.

### Risks and mitigations

| Risk | L | I | Mitigation |
|---|---|---|---|
| Statusline `context_window` schema shifts before implementation | Med | High | Fresh-docs re-fetch is work item 1 of A1/A2; tee copies the object verbatim so field additions flow through without a plugin change |
| Zone defaults wrongly chosen vs real compaction behavior (no documented threshold exists to ground on — verified 2026-07-23) | Med | Med | Ship declared judgment defaults; zones.json override is the tuning path; owner confirms the numbers at plan approval |
| Snapshot dir grows unbounded (one file per session) | Med | Low | Prune-on-write with age cutoff, tested in A1 |
| `gh` absent / unauthed in consumer repo | Med | Med | Sink ladder ends in local markdown fallback; setup `check` reports |
| Inbox byte-compat drifts from `work-items` local-markdown shape | Low | Med | B4 documents the item schema; B7 diffs a real emitted item before the local skill is deleted |
| Windows statusline wiring friction (Git Bash requirement) | Med | Med | Same declared shell requirement + setup-printed wiring as rate-limit-guard (proven in the fleet) |

## Blast radius

MEDIUM — all-new additive code (no existing consumer changes; git revert clean), but it wires into
machine-wide statusline infrastructure, ships a skill that composes other skills, and adds a `gh`
egress surface — three stress-test triggers.

## Stress-test summary

Two fresh-context passes ran 2026-07-23, both against this plan (neither authored it):

1. **Plan reviewer** (Step 3): 1 CRITICAL + 5 IMPORTANT + 5 SUGGESTION. All 11 applied — the
   CRITICAL (no session-id discovery mechanism for consumers) resolved via the documented
   `${CLAUDE_SESSION_ID}` skill substitution (verified against the skills doc 2026-07-23);
   inline-floor ownership + drift check, dumb-zone smoke, evidence-packet spec, verb-contract
   deviation record, compaction blind-spot rule, plugin-cache read in the security record,
   trigger continuity + negative routing, MCP-lens boundary, sandboxed-HOME sanity commands, and
   null-field test cases all added.
2. **Devils-advocate** (Step 4, blast MEDIUM): 3 HIGH + 6 MEDIUM + 5 LOW; 5 MUST-fix, all
   applied — per-zone decision table making the dumb-zone smoke falsifiable (#1), empirical
   band-vs-auto-compact ordering task (#2), consumer reads zones.json directly with inlined
   defaults as fallback only (#3), B7 full-item diff + compat-target reconciliation in B4 (#7),
   honest auditor tool surface + untrusted-content posture + injection eval (#9). Should-fixes
   #5 (run-nonce), #6 (contract-lock notes into the packet), #8 (acting `gh` account in the
   confirm gate) applied. Accepted risks, documented in place: #4 (stale wiring after plugin
   update — upgraded check-time detection; shim alternative left as an open question), #10–#14
   (all landed as one-line plan-text hardenings).

No research-iterate round was needed: every contested claim was resolvable from the same-day doc
fetches or repo evidence.

## Execution shape

Two swim lanes per the playbook (worktree + branch + atomic PR each), **lane A merges before lane B
opens** (seams-first: B1 inlines A3's reader contract verbatim — authoring B against an unmerged
contract risks split-brain). Within each lane phases are sequential (each phase's artifacts feed
the next; single-worktree file ownership). Shared-file conflicts (`marketplace.json`, repo README)
don't arise because the lanes are serialized. Post-plan next step: `/work-items:decompose` this
plan into the two lanes' work items (Brief sequencing decision B13).

> **Scope change (2026-07-24, owner override at execution start):** both lanes are AUTHORED IN
> PARALLEL worktrees in one session — overriding this section's serialized-lanes row. **Merges stay
> serialized: lane A merges first**, then lane B rebases onto main and merges (seams-first becomes
> a merge constraint, not an authorship constraint). Split-brain guard: lane A's
> `reference/reader-contract.md` is authored EARLY and its inline-floor values treated as frozen;
> lane B's byte-identity drift grep re-runs after lane A merges and after any lane-A review change
> to those values. Expected shared-file conflicts at lane-B rebase (`marketplace.json`, repo
> `README.md`, `docs/MIGRATION-PLAYBOOK.md`, this file's phase tags) are trivial appends — resolve
> by keeping both sides. The native edge #1237←#1230 stays (it encodes merge order); #1237 is
> claimed explicitly by id.

| Phase | Surface | Basis |
|---|---|---|
| A1–A2 | implementation session (lane A worktree), main thread | TDD shell work, tightly coupled to fresh-docs grounding |
| A3–A5 | same session, main thread | docs + release chores reference A1–A2 outputs |
| B1–B6 | implementation session (lane B worktree), main thread | prompt-artifact authoring is judgment-heavy; volume is modest |
| B7 | operator (HITL), post-merge | machine-local cutover; user-reserved |

Sequential fallback: not applicable (no parallel agents recommended; decompose may still parallelize
B2's mechanical reference generalization to a sub-agent worker with an ALLOWED list of the seven
reference files if the implementing session chooses).

## Decisions made (gate-passed)

Every `[EXEC-SHAPE]` / `[FALLBACK]` tag in this plan, for override at approval:

| Decision | What it changes in the plan | Basis (evidence) |
|---|---|---|
| [EXEC-SHAPE] Two serialized lanes, sequential phases within each, main-thread implementation sessions | Execution-shape section; no parallel agent waves | Playbook swim-lane + seams-first sections read this session; B1 inlines A3's contract, so lane B authored against an unmerged contract risks split-brain |
| [EXEC-SHAPE] `plugin-quality` ships a plugin agent (`agents/auditor.md`) as the named fresh-context subagent that the main-thread skill dispatches for steps 2–3 | Phase B3 exists; SKILL.md step 2 dispatches by agent name; steps 1, 4, 6 stay main-thread | The audit's step topology is not expressible as `context: fork` — basis in full below |
| [EXEC-SHAPE] context-guard setup `apply` scoped to seeding/refreshing zones.json only — **widened 2026-07-24 (owner-approved) to also install the statusline shim**; see the resolved stable-shim entry under Open questions | Phase A4 apply surface; statusline wiring stays print-only | Philosophy setup contract (never mutate user settings) + rate-limit-guard check-only precedent; zones.json is the one machine file whose schema the plugin owns. Widening rationale: the shim lands in the same operator-home carve-out, is inert until wired, and cleared delta security review |
| [FALLBACK — confirm or override] Design gate satisfied by `design/design-resolution.md` early-exit instead of a `/planning:design` pass | No separate design stage before implementation | Interview resolved all design threads (15 branches, owner-confirmed 2026-07-23); artifact maps each design axis to its ledger branch |
| [FALLBACK — confirm or override] Draft+confirm read as the `audit` verb's "explicit user override" for the `gh issue create` emit | B1 emit design; no `--apply`-style argument gating the sink | Brief B14 locks unconditional draft+confirm; fleet precedent (`github:audit`) uses `--apply` instead — deviation recorded at the coupling site |
| [FALLBACK — confirm or override] Default zone bands: smart ≤ 50, acceptable 50–75, dumb > 75 | A2 shipped defaults; B1 inlined fallback constants | No documented auto-compact threshold exists (4 doc pages fetched 2026-07-23); judgment values with the A2 empirical-ordering task + zones.json override as correction paths |

### [EXEC-SHAPE] basis — why the deep audit is a dispatched named agent, not `context: fork`

This subsection is the single home for that basis; every other site points here.

Neither "fresh context" nor "named" discriminates, so neither is the reason. A forked skill starts
blank — "It won't have access to your conversation history" — and the `agent` frontmatter field
selects the subagent type to run: "Which subagent type to use when `context: fork` is set"
([skills](https://code.claude.com/docs/en/skills), verified 2026-07-24). So `context: fork` plus
`agent: auditor` would already be a fresh-context, named-agent-type run; `discovery`'s
`explore-deep` ships that pairing in this repo. The fresh-eyes doctrine is not the reason either:
it rules out the Agent tool's separate `fork` subagent type, which "inherits the entire
conversation so far instead of starting fresh"
([sub-agents](https://code.claude.com/docs/en/sub-agents), verified 2026-07-24) — a different
mechanism that shares the word.

The basis is topological — what the forked unit *is*:

1. **`context: fork` forks the whole skill, and only steps 2–3 want a fresh context.** "The skill
   content becomes the prompt that drives the subagent" — the entire body goes to the subagent, so
   steps 1, 4, and 6 would go with it. A skill cannot fork one of its own steps.
2. **Step 1 could not run at all.** Evidence capture reads what was invoked this session, the hook
   failures and permission denials observed, the anomaly that prompted the audit — that *is*
   conversation history, the one thing a forked skill is documented not to have. Forking the skill
   destroys the audit's only input.
3. **Steps 4 and 6 need user-interactive surfaces a forked skill lacks.** The contract-lock
   interview and the unconditional egress confirm gate must ask the user. `AskUserQuestion` is
   removed from every subagent "even when listed in the `tools` field"; forks that inherit the
   conversation skip that filter, but a forked *skill* does not — "the skill's subagent is a
   regular agent type, so the exemption for subagents that fork the conversation doesn't cover it"
   ([skills](https://code.claude.com/docs/en/skills),
   [sub-agents](https://code.claude.com/docs/en/sub-agents), verified 2026-07-24).

**Restated as an invariant, after two earlier rationales were defeated in review.** The first
claimed `context: fork` inherits degraded history — false; a forked skill has no conversation
access. The second claimed a forked skill is anonymous — false; the `agent` frontmatter field names
the subagent type. The third claimed a forked sibling could not receive per-run inputs — also false,
since `$ARGUMENTS` is exactly that channel and
`plugins/discovery/skills/explore-deep/SKILL.md` ships the pattern.

Each rationale argued from what fork does. The requirement does not depend on that, so it is stated
positively instead. The deep phase needs two properties:

1. **A context carrying the evidence packet but NOT this session's conversation history or prior
   reasoning.** The packet is the deliberate channel — `agents/auditor.md`'s procedure opens by
   reading it as ground truth, and step 1 exists to write it. What must not cross is the reasoning
   that produced the work under review; that is what a same-context self-check cannot escape.
2. **A named dispatch target** — the Brief's requirement, and what makes the dispatch site
   auditable: a reader sees which worker runs the deep phase without inferring it from file layout.

`agents/auditor.md` supplies both, and the plugin already ships it. A forked sibling skill could
satisfy (1) and, via `agent:`, arguably (2) — so it is not rejected as impossible. It is rejected on
cost: it requires shipping a second skill whose only purpose is to be forked, spending shared
skill-listing budget (#1271 measures that budget and the silent description drops it causes) for
zero user-facing capability, and splitting one workflow across two files that must stay in sync.

**Recorded caveat, unverified:** #1258 reports the Agent tool's `fork` subagent type not inheriting
the conversation in practice, against its documentation. The invariant above is deliberately
independent of how that resolves; the caveat is carried so the observation is not lost.

## Open questions

- Exact default zone-band numbers — docs carry NO compaction threshold (verified 2026-07-23), so
  the proposed 50/75 judgment defaults stand unless the owner overrides at approval.
- Evidence-packet field list — capture-broadly set locked; trimmed after first real runs
  (Brief-deferred).
- zones.json org/managed layer — USER-RESERVED, untouched by this plan.
- ~~Stable-shim question (stress-test #4)~~ **RESOLVED 2026-07-24 — owner opted in.** Shipped as
  `scripts/statusline-shim.sh` in BOTH guard plugins (context-guard 0.2.0, rate-limit-guard 0.2.0),
  installed to `~/.claude/<plugin>/bin/statusline-shim.sh` by `setup apply`. The operator wires the
  shim once and never re-wires; `check` now classifies version-pinned cache-path wiring as LEGACY
  regardless of whether the file still exists. Two options were weighed and rejected: keeping the
  interim `[ -f … ]` guard (survives pruning but still stops teeing at every version bump), and an
  inline glob in `settings.json` (untestable shell frozen in an operator file, and unreadable once
  two tees chain). The cost the original question flagged — a plugin writing an executable into the
  operator's home — was accepted after delta security review (MIGRATION-PLAYBOOK.md): the copy is
  byte-identical to reviewed bundled code, lands in the plugin's already-accepted operator-home
  carve-out, and is inert until the operator's own `settings.json` edit, so the base record's
  no-kill-switch justification survives intact. `setup apply` scope widened accordingly (owner-
  approved change to the A4 EXEC-SHAPE entry, which had scoped `apply` to zones.json only);
  statusline wiring stays print-only.

## Handoff to implementation

### User-approval gates

- Plan approval (this document) before any lane opens.
- B7 cutover: deleting `~/.claude/skills/plugin-audit/` only after the operator confirms the
  byte-compat check passed.
- Every `gh issue create` inside an audit run: unconditional draft + confirm (Brief B14) — this is
  a runtime gate the skill itself carries, restated here because it is also an egress gate.

### Execution shape ([EXEC-SHAPE] tagged)

- [EXEC-SHAPE] Two serialized lanes, sequential phases within each, main-thread implementation
  sessions (table above).
- [EXEC-SHAPE] `plugin-quality` ships a plugin agent (`agents/auditor.md`) as the named
  fresh-context subagent for audit steps 2–3.
- [EXEC-SHAPE] context-guard setup `apply` is scoped to seeding/refreshing zones.json only (the one
  plugin-schema-owned machine file); statusline wiring stays print-only.
- [FALLBACK — confirm or override] Design gate satisfied by `design/design-resolution.md`
  (early-exit: interview resolved the design threads) instead of a separate `/planning:design`
  pass.
- [FALLBACK — confirm or override] Verb-contract reading for `audit` + emit: the philosophy fixes
  `audit` = read-only, "mutation only behind an explicit user override". This plan reads the
  Brief-locked unconditional draft+confirm (B14) as that explicit override — the user approves
  the exact `gh issue create` at the mutation point — while the fleet precedent (`github:audit`)
  gates writes behind an `--apply` argument instead. The deviation is recorded at the coupling
  site in SKILL.md; alternative if overridden: emit only behind an explicit `emit` argument.

### Mechanical work

- Commit boundaries: one commit per phase minimum; PLAN.md phase-tag updates ride the same commit
  as the phase's changes; Conventional Commit subjects; PRs per lane, squash-merged, PR title =
  Conventional Commit.
- Verification checkpoints: each phase's Sanity Check runs before its commit; lane-level
  `claude plugin validate` + `--strict` before each PR; `/skill-quality:check` on every new skill.
- Close-out: `/planning:plan close-out` after lane B merges (PLAN.md → PR description, prune the
  contract slice, ADR test applied to the zones-SSOT and two-plugin-split decisions).
