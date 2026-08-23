# bug-finding-skill — PLAN

## Brief

### TLDR

- New skill `/bug-report:scan` in the existing `bug-report` plugin: proactive, general-purpose bug finding — on demand, targeted ("find a bug in X"), or as a daily routine's single bounded pass.
- Read-only find → verify → report; two-stage precision (recall-biased hunter subagents, then a separate fresh-context default-refute verification gate); never fixes code in-run.
- Targeted scoping (path/feature/diff argument) plus whole-repo lane rotation with a per-run budget (stop at 3 verified findings or lane exhausted); lane cursor derived statelessly from tracker/git history.
- Optional filing behind an explicit argument only: every self-filed finding lands as raw intake (`status:needs-triage` via the consumer's `role_labels` map) — never born-briefed, never on bare invocation.
- Extend the plugin's `setup` skill to write a tracked, config-cascade-governed project file for lane globs + filing posture; ship evals; pass `skill-quality:check`; register nothing new in marketplace.json (plugin exists).

### Goal

The marketplace covers the bug lifecycle everywhere except its start: every existing finding-producer is gated on a diff, an observed failure, a factual claim, a test file, or a comment marker. `/bug-report:scan` fills that gap — a proactive hunter that reads resting code, surfaces defects nobody has observed yet, verifies them adversarially before reporting, and hands them to the existing report/filing/triage machinery. One invocation is one bounded scan, equally usable interactively ("find a bug in this feature"), from `/loop`, from a claude-ops lane prompt, or from a cloud Routine.

### Constraints

- Read-only on bare invocation (verb-table contract for `scan`); mutation (filing) only behind an explicit argument.
- No sibling-plugin imports; composition with `work-items`, `debugging`, `review` is presence-gated with graceful degradation.
- The two-stage precision shape is mandatory: the discovering agent never grades its own findings (fresh-eyes rule); default-refute; "if uncertain, it is NOT a finding."
- Filing conforms to the dogfood-filing contract: raw intake only; the `needs-triage` marker resolves from the consumer's live label set per the label-taxonomy dual-axis rule (priority axis: `--priority needs-triage` replaces the filing floor; status axis: label applied post-creation) — `role_labels` holds only the three canonical roles and never `needs-triage`; no label creation.
- Durable cross-run state must not live in `.work/` (checkout-local); the lane cursor derives statelessly via a documented ladder — tracker filing history when filing is in play → persisted-report metadata under `${CLAUDE_PLUGIN_DATA}` → deterministic date-derived lane selection as the zero-state floor; `.work/` is a per-checkout cache only, with reset semantics documented.
- The persisted findings report must NOT declare detector-findings `type: review-findings` frontmatter (that alone routes it into the `review:fanout fix` relay); refuted candidates are retained in the report marked `refuted`, never silently discarded, and refill rounds after a full-refute pass are capped.
- Cross-plugin composition is by skill invocation or artifact contract only — never by dispatching another plugin's agents; the scan description must disambiguate its triggers from `claude-ops:known-issues` ("scan repo for issues") and `bug-report:write` ("file a bug").
- Lane globs and filing posture are team config in a tracked project file (config-cascade-governed, written by setup) — not `userConfig`.
- No scheduler in the skill; loop-friendly single-pass semantics with `cadence: daily` metadata.
- Skill fences (skip-when) must name: `review:*` (diff review), `review:security-review` (security-focused auditing), `debugging:debug` (observed failures), `codebase-health:audit` (doc/config/code-quality/arch claim drift — all its dimensions), `code-tidying:tidy` (structure), `work-items:scan-todos` (comment markers), `testing:audit` / `mutation-testing:audit` (coverage gaps).
- Repo gates: `skill-quality:check` (22-check static gate), evals present, CI check scripts, markdownlint, skill-reference-verify.

### Acceptance criteria

- `/bug-report:scan <path|feature|diff>` runs a targeted hunt and emits verified findings in the 5-field bug-report shape, each labeled `reproduced` or `verified-by-reading`; bare `/bug-report:scan` self-selects a lane via the stateless cursor and stays within the per-run budget (default: stop at 3 verified findings or lane exhausted).
- Every reported finding passed a separate fresh-context default-refute verification subagent; unverified candidates never appear in the report.
- V1 hunting lenses shipped: in-code contract-vs-body mismatch (same-unit signature/types/docstring/named invariants only), boundary/edge-case, cross-file consistency drift, state/concurrency hazards, git-hotspot-guided reads.
- Filing happens only with the explicit filing argument, produces raw-intake work items through the tracker seam per dogfood-filing beat 4 (live-label-set resolution, dual-axis `needs-triage`), and runs a tracker duplicate-search first.
- Execution contract (per-unit close-out): each hunted lane/target is processed one unit at a time — hunt, verify, report (optionally file), advance cursor; a unit is closed when its verified findings are reported and deduped.
- Setup skill writes/updates the tracked project config file (lane globs, filing posture) and degrades gracefully when absent (bundled generic lane fallback).
- New skill passes `skill-quality:check`, ships `evals/evals.json`, all repo CI gates pass, and `plugin.json` is version-bumped per convention (current-main version → 0.8.0 with CHANGELOG entry — main was 0.7.4 at plan time; `docs/CATALOG.md` + `docs/SKILL-CHEAT-SHEET.md` regenerated).
- Same-PR obligations land together: setup's check-only self-description rewritten (the tracked file dissolves its carve-out and `apply` becomes mandatory, bounded to that file); a `bug-report` row added to the config-cascade Implementers table with merge semantics declared beside the keys; `output_dir` stays userConfig-only and is never duplicated into the cascade file.
- This Brief (`docs/topics/bug-finding-skill/PLAN.md`) is pruned in the final pre-merge commit (contract-slice-prune gate keys on the net PR diff).
- Skip-when fences for all eight named neighbors present in the skill description.

### Captured assumptions

- Operator's actual daily-routine vehicle unknown — V1 supports both lane-prompt and standalone/Routine invocation equally; revisit if a concrete lane deployment surfaces new needs.
- `scan` remains an approved read-only verb in the verb table — revisit if PLUGIN-PHILOSOPHY's verb contract changes.
- The bug-report plugin's existing persisted-report path (`${CLAUDE_PLUGIN_DATA}/bug-reports/<project-slug>/`) is reusable for scan findings — revisit if the impl-surface exploration shows a conflicting convention.

### Out-of-scope

- Fixing bugs in the same run (routes to `debugging:debug` / remediation lanes).
- Cross-repo scanning (post-V1; compose repo-fleet infrastructure when it comes).
- Formal loop-lane convention adoption — telemetry comments, role-label escalation, autonomy matrix (explicit post-V1 follow-up through the owner doc).
- Born-briefed / verified+briefed self-filing (deferred pending a dogfood-filing owner-contract amendment).
- Detector-findings-format persistence (deferred unless deterministic sub-rules emerge that pass the admission test).
- A new standalone `bug-finding` plugin (superseded by extending `bug-report`).

### Deferred questions

*(none — all 18 register rows resolved; the deferrals above are scope decisions, not open questions)*

## Plan

Standards grounding: docs/PLUGIN-PHILOSOPHY.md (verb table; setup narrow-write `apply` contract :383-412; cross-skill citation form :296-302; seam phrasing :22-33), docs/conventions/config-cascade/README.md (merge-semantics-beside-keys :75-77; Implementers row obligation :200-224), plugins/work-items/reference/dogfood-filing.md (4-beat filing), docs/conventions/detector-findings/README.md (negative constraint: no `type: review-findings`), docs/conventions/plugin-data-report-keying/README.md, skill-quality 22-check gate. No standards index file exists in this repo (absent-index path; grounding done via the verified impl-surface exploration).

Decisions made under the Brief's arbiter delegation, tagged per contract:

| Decision | What it changes in the plan | Basis (evidence) |
|---|---|---|
| [EXEC-SHAPE] Verifier = fresh-context subagents dispatched inline by the skill body (prompts in context spokes), not a plugin agent file and not `context: fork` | Phase 1 ships `context/verification-gate.md` instead of an `agents/` entry | codebase-health:audit Phase 2 dispatches its false-positive gate as a SEPARATE inline-prompted subagent (audit/SKILL.md:161-164) — the worked precedent; plugin agents also can't set `permissionMode` (plugins-reference, RESEARCH-frontmatter) |
| [EXEC-SHAPE] Variant-analysis seeding deferred post-V1 | No bug-corpus machinery in Phase 1; git-hotspot lens partially covers | Big Sleep names it most tractable but it requires a curated bug corpus a generic consumer lacks (RESEARCH externals sidecar) |
| [EXEC-SHAPE] Lens-3 boundary line | `context/lenses.md` states: cross-file consistency drift = behavioral divergence between code units that must agree (duplicated logic, parallel implementations, caller/callee assumptions); factual claims in docs/config vs code stay `codebase-health:audit`'s | Validator A D6 + both audit rounds converged on this line |
| [EXEC-SHAPE] Refill cap = 2 | After a hunt wave whose candidates are all refuted, at most 2 refill waves; then report the refuted set and stop | Validator B D7 flagged the unbounded path; Heelan 1:50 signal-to-noise makes unbounded refill a token sink (RESEARCH) |
| [EXEC-SHAPE] Filing flag is `--track`, not `--file` | Phase 1 argument-hint and filing section | write/SKILL.md:88 already defines `--file` = persist report to disk within this plugin; same token with different mutation semantics would collide (plan review #1); `--track` matches the work-items seam verb |
| [EXEC-SHAPE] Frontmatter: `workflow-stage: operator` + `cadence: daily` + `summary` | Phase 1 frontmatter | cheatsheet-config.mjs requires cadence⇔operator pairing and a non-empty summary; `anytime`+cadence fails the generator and thus validate-plugins (stress-test #2); morning-brief is the dual-use precedent |
| [EXEC-SHAPE] Scan-filed items carry a body provenance line (`Filed by /bug-report:scan (lane: <name>)`) | Phase 1 filing section; cursor rung 1 searches this marker | no-label-creation rule bars a label marker; body provenance is searchable and is how rung 1 recognizes its own filings (plan review #6) |
| [FALLBACK — confirm or override] Same-day concurrent sessions on a zero-state checkout may hunt the same lane | stated in cursor reset semantics; accepted for V1 (tracker dedupe + report dedupe absorb duplicates) | date-derived floor is deterministic by design; per-session jitter would break daily coverage guarantees (plan review #6) |

### Phase 0: base refresh [DONE]

`origin/main` merged into the branch (was 161 commits behind; bug-report moved 0.7.1 → 0.7.4 including a setup rewrite). Re-merge again immediately before Phase 5's merge step (the `stale-base-overlap-gate` fails on any touched-path overlap with commits landed since).

**Sanity Check:** `git rev-list --count HEAD..origin/main` = 0 at Phase 5 entry.

### Phase 1: `/bug-report:scan` skill [DONE]

Create `plugins/bug-report/skills/scan/` and the shared config reference:

- `SKILL.md` — frontmatter: description with proactive-hunt triggers (single-quoted: 'find a bug', 'bug hunt', 'scan for bugs', 'hunt for bugs in <X>') + skip-when fences naming all eight neighbors + explicit disambiguation vs `claude-ops:known-issues` ('scan repo for issues' = known-issue registry, not this) and `bug-report:write` ('file a bug' you already observed = write, not this) — **character budget: description ≤ 1536 chars (`wc -c` before close-out), terse fence phrasing**; `argument-hint: "[<path|feature|diff>] [--lane <name>] [--track] [--dry-run]"`; `user-invocable: true`; `disable-model-invocation: false`; `metadata: {workflow-stage: operator, cadence: daily, summary: <≤100 codepoints, no ": ">}`. Body: pre-computed context (branch, recent commits — degrade gracefully on shallow/no-history clones); mode resolution (targeted arg → that scope; bare → lane from cursor ladder); cursor ladder (rung 1: search tracker for scan-filed items via the body provenance marker → rung 2: persisted-report cursor metadata → rung 3: deterministic date-derived lane index; `.work/` cache only; reset semantics state the same-basename slug-sharing caveat and the same-day-concurrency posture); **verb-contract reconciliation sentence: writes under `${CLAUDE_PLUGIN_DATA}` are plugin-owned state, not target-repo mutation — bare scan stays read-only toward the repo while persisting its own report/cursor; `--dry-run` neither persists nor advances the cursor**; per-run budget (stop at 3 verified findings or lane exhausted; candidate cap 10 per hunt wave; refill cap 2; "lane exhausted" = the budget-bounded sample of the lane is complete — V1 is sampling, not exhaustive coverage); two-stage pipeline (per-lens hunter dispatch → separate fresh-context verification gate); report assembly + persist and **report-level dedupe via write's duplicate scan** (cite both via the `${CLAUDE_PLUGIN_ROOT}/skills/write/...` form — no reinvention); `--track` action: presence-gated work-items handoff per dogfood-filing beats 1–4 (dedupe search `--state all` → 5-field body via `track add` with the provenance line `Filed by /bug-report:scan (lane: <name>)` → `--priority needs-triage` on the priority axis / status-axis label post-creation, resolved from the live label set; no label creation; degrade to report-only with a printed notice when work-items is absent OR no tracker binding resolves); read-only contract on bare invocation; handoff pointers (verified finding → `/debugging:debug`; security-tagged → `review:security-review` lane).
- `context/lenses.md` — five lens specs as hunter prompt templates using the four-part subagent contract (objective / output format / tool guidance / task boundaries), each with an evidence-quote requirement and explicit "reporting no candidate is a valid outcome" permission; lens-3 boundary line above; lens 5 (git-hotspot) degrades to skip-with-notice on shallow clones; **plus the bundled generic default-lane section** bare scan uses when no `.claude/bug-report.md` exists.
- `context/verification-gate.md` — gate subagent prompt: default-refute stance, per-candidate independent context, evidence-quote grounding, cheap-repro attempt guidance, confidence floor, `reproduced` vs `verified-by-reading` labeling, retained-refuted output contract (refuted candidates returned with refuting argument, never dropped).
- `context/findings-report.md` — report format: no `type: review-findings` frontmatter; per-finding 5 fields + evidence label + lens id; refuted-candidates tail; cursor metadata block (lane, timestamp, counts).
- `../../reference/config.md` (plugin-root `plugins/bug-report/reference/config.md`) — the single home for the `.claude/bug-report.md` key contract (lanes: concatenating merge with declared empty-list opt-out; filing_posture: nearest-wins scalar; `output_dir` partition rule); both scan and setup cite it (config-cascade "keys live in the plugin's own bundled reference").
- `evals/evals.json` — cases: targeted scan, bare lane-rotation scan, `--track` gated filing, bare-invocation read-only (no filing), fence/disambiguation routing, dry-run. Conform to `plugins/skill-quality/reference/evals.schema.json`.

**Sanity Check:** `CHECK_SKILL_SKILLS_ROOT="$PWD/plugins/bug-report/skills" bash plugins/skill-quality/scripts/check-skill.sh --require-evals scan` exits 0. `grep -o 'review:security-review\|debugging:debug\|codebase-health:audit\|code-tidying:tidy\|scan-todos\|testing:audit\|mutation-testing:audit\|review:fanout\|review:code-review\|quality-gate' plugins/bug-report/skills/scan/SKILL.md | sort -u | wc -l` ≥ 8. `grep -q '^type: review-findings' plugins/bug-report/skills/scan/context/findings-report.md` exits non-zero (absence). `check-jsonschema --schemafile plugins/skill-quality/reference/evals.schema.json plugins/bug-report/skills/scan/evals/evals.json` exits 0 (CI runs this via pinned action; locally installed here). `awk '/^description:/' plugins/bug-report/skills/scan/SKILL.md | wc -c` ≤ 1536.

### Phase 2: setup extension + tracked config contract [DONE]

- `plugins/bug-report/skills/setup/SKILL.md` — extend the CURRENT main text (0.7.4 rewrite) to the `check|apply` narrow-write shape (PLUGIN-PHILOSOPHY :406-412): `apply` bounded to `.claude/bug-report.md` only; the now-false userConfig-only carve-out replaced in BOTH the frontmatter description and the body; cascade layers + merge semantics cited from `reference/config.md` (Phase 1's shared home), not restated; key partition rule (`output_dir` stays userConfig, never in the cascade file).
- `docs/conventions/config-cascade/README.md` — add `bug-report` Implementers row (all three layers | conforms).
- `docs/conventions/plugin-data-report-keying/README.md` — extend the bug-report Implementers row to cover scan as a new slug-keyed producer (reports + cursor metadata); verify the row's line-cited reference to write/SKILL.md survives.
- `plugins/bug-report/skills/setup/evals/evals.json` — add apply-action case(s).

**Sanity Check:** `CHECK_SKILL_SKILLS_ROOT="$PWD/plugins/bug-report/skills" bash plugins/skill-quality/scripts/check-skill.sh --require-evals setup` exits 0. `grep -q "bug-report" docs/conventions/config-cascade/README.md` exits 0 (Implementers table). `grep -q "nothing an apply could write" plugins/bug-report/skills/setup/SKILL.md` exits non-zero (phrase removed from description; verified present on current main pre-change). `grep -c "apply" plugins/bug-report/skills/setup/SKILL.md` ≥ 5.

### Phase 3: plugin metadata + generated docs [TODO]

- `plugins/bug-report/.claude-plugin/plugin.json` — version 0.7.4 (current main) → 0.8.0; description/keywords updated only if scan changes the plugin's summary (default: keywords gain "scan"/"bug-hunting" if schema-permitted; marketplace.json untouched).
- `plugins/bug-report/CHANGELOG.md` — 0.8.0 entry (new scan skill; setup check|apply; tracked config file) added ABOVE the preserved 0.7.2–0.7.4 headings (parity gate checks preservation + order).
- `plugins/bug-report/README.md` — scan section + config-file documentation.
- Regenerate `docs/CATALOG.md` + `docs/SKILL-CHEAT-SHEET.md` (`node scripts/generate-catalog.mjs && node scripts/generate-cheatsheet.mjs`).

**Sanity Check:** `bash scripts/check-changelog-parity.sh` exits 0. `bash scripts/validate-plugins.sh` exits 0 (includes `--check` regen staleness). `grep -q '"version": "0.8.0"' plugins/bug-report/.claude-plugin/plugin.json`.

### Phase 4: full local gate pass [TODO]

Run every gate CI will run, fix findings: `bash scripts/check-changed-skills.sh origin/main`; `markdownlint-cli2` on changed .md; `typos`; `editorconfig-checker`; `bash scripts/check-contract-slice-prune.sh --check-diff origin/main` expectation check (slice still present pre-prune — gate failure EXPECTED here, resolved in Phase 5); re-run `bash scripts/validate-plugins.sh`.

**Sanity Check:** each named command exits 0 (except the contract-slice-prune expectation, exit non-zero while the slice exists — recorded, resolved by Phase 5).

### Phase 5: PR, CI, prune, merge [TODO]

1. Commit phases as they complete (conventional messages); push to `claude/bug-finding-skill-f2vst1`.
2. Close-out step 1: open the PR to main with a **Conventional-Commits title** (repo is squash-only; squash subject = PR title, enforced by pr-title.yml); PR body carries `Closes #N` or the literal `No linked issue` line AND a non-empty `## Related` section (pr-issue-linkage.yml strips HTML comments — an unedited template fails), the approved PLAN.md in a `<details>` block, and the attribution footer. Subscribe to PR activity.
3. Budget a respond-to-review loop: `claude-review.yml` + `claude-security-review.yml` auto-run on the PR; resolve their findings per the review-disposition contract, not just CI failures. Ensure no `do-not-merge` label.
4. Final pre-merge commit: re-merge `origin/main` (stale-base-overlap-gate), then prune `docs/topics/bug-finding-skill/` (contract-slice-prune judges the net three-dot diff; deletion exempts), leaving the PR body as the pointer. No ADR (admission test fails: decisions reversible, recorded in PR).
5. Drive CI to green (diagnose + fix + push per failure); **squash-merge** when green (user-authorized).

**Sanity Check:** all CI checks green on the PR; `git diff origin/main...HEAD --name-only | grep -c "^docs/topics/"` outputs 0 at merge time; PR state = MERGED.

## Blast radius

MEDIUM — a new user-facing skill + a convention-registry row + a rewritten setup contract in one plugin; no runtime code paths outside markdown/evals/CI; all changes branch-isolated and gate-checked. No consumer-breaking contract migrations (the tracked config file is new, additive).

## Stress-test summary

Two fresh-context reviews ran (plan-reviewer + devils-advocate), 21 findings total, all verified against primaries and folded in: CRITICAL stale-base (161 commits; fixed by Phase 0 merge + re-merge before merge step), cheat-sheet generator's cadence⇔operator + summary requirements, corrected gate-command invocations (skill-name positional + `CHECK_SKILL_SKILLS_ROOT`; `check-changed-skills.sh origin/main`; `--check-diff`), `--file`→`--track` flag rename (intra-plugin collision), plugin-data-state vs verb-contract reconciliation, shared `reference/config.md` key-contract home, write dup-scan reuse, cursor rung-1 provenance marker + degrade paths (unbound tracker, shallow clones, generic default lane), PR gates (title convention, issue-linkage markers, squash-only, do-not-merge label, auto review workflows), description char budget, keying-convention row. CONFIRMED assumptions: prune-gate deletion semantics, changelog parity shape, catalog auto-pickup, evals schema fit, no leaf-name collision, no unenumerated CI lane.

## Execution shape

Sequential, single session — Phases 1→2 share vocabulary and cross-citations (scan cites the config file the setup phase defines), Phase 3 depends on both, Phase 4 gates on 1–3, Phase 5 is terminal. No material parallel saving (the two parallel-safe phases are both prose-authoring against the same contracts). Per-phase routing: Phase 1–3 via `/implementation:implement` dispatch (scope-fenced per phase), Phase 4–5 main session (gates + git + PR are orchestration). PLAN.md edits main-session-only.

## Open questions

None at approval time — the four deferred execution-shape decisions are resolved in the table above.

## Handoff to implementation

### User-approval gates

- Standing authorization already given by the user for the full pipeline (plan → implement → PR → merge, picking recommended). Remaining hard gate: none beyond CI green before merge. Any mid-flight pivot that would change the Brief's acceptance criteria stops and surfaces.

### Execution shape ([EXEC-SHAPE] tagged)

- Sequential phases; per-phase implementer dispatch allowed for Phases 1–3 with scope fences: Phase 1 ALLOWED `plugins/bug-report/skills/scan/**` + `plugins/bug-report/reference/config.md`; Phase 2 ALLOWED `plugins/bug-report/skills/setup/**` + `docs/conventions/config-cascade/README.md` + `docs/conventions/plugin-data-report-keying/README.md`; Phase 3 ALLOWED `plugins/bug-report/{.claude-plugin/plugin.json,CHANGELOG.md,README.md}` + regenerated `docs/CATALOG.md`, `docs/SKILL-CHEAT-SHEET.md`. FORBIDDEN everywhere: `docs/topics/**` (main session only), other plugins.
- Sequential fallback is the primary shape; no parallel orchestration to fall back from.

### Mechanical work

- Commit per phase; conventional-commit subjects; multi-line messages via `git commit -F - --cleanup=verbatim` (repo hook blocks multi-line `-m`).
- Verification checkpoint after Phase 4 = the full local gate list above; Phase 5 merges only on green CI.
