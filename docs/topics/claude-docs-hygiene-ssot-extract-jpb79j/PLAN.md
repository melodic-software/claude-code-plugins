# Whole-repo SSOT extraction batch — Brief + Plan

Working notes for a `/docs-hygiene:extract-ssot` whole-repo run plus a
same-PR update to the skill itself. Contract tier per
`docs/conventions/topic-docs/README.md`; pruned before merge.

## Brief (locked task contract, 2026-08-15)

Locked with the user via interview:

- **Scope:** the entire repository's tracked markdown (~1,131 files),
  excluding `docs/topics/`, `docs/upstream/`, and eval fixtures per the
  skill's identify-action scope rules.
- **Depth:** full pipeline — inventory → Tier 0 verify → execute every
  cluster that passes the gates. Refused clusters are documented with
  reason codes, never migrated.
- **Commit cadence:** wave-committed — each execution wave lands as its
  own conventional-commit on this branch so the PR reviews wave-by-wave.
- **Orchestration:** main session (Fable) orchestrates; worker subagents
  run on Opus 5. Concurrency hard-capped at **2** — the account's
  subscription rate-limit windows are shared with the user's other
  concurrent sessions, and the rate-limit-guard tee snapshot
  (`plugins/rate-limit-guard/reference/reader-contract.md`) is not
  visible from this cloud container, so the cap is static and
  conservative rather than dynamic.
- **Inventory:** the single read-only survey subagent dispatched at
  session start is retained as the inventory phase; its roster is
  treated as unverified synthesis (lead list) until each candidate is
  promoted to Tier 0 by verify workers.
- **Skill update (same PR):** `/docs-hygiene:extract-ssot` gains a
  confirm-scope fallback — a bare invocation that finds no working
  notes, no active roster, and no implied scope asks the user before
  dispatching an exhaustive survey (interview with prescribed defaults)
  — plus documented orchestrated-mode defaults: low static worker
  concurrency by default (most consumers run under shared subscription
  windows; enterprise is the exception), worker model tiering, and
  consumption of the rate-limit-guard reader contract when its snapshot
  is present, degrading to the static cap when it is not.

### Named assumptions

- Topic-docs defaults (`docs/topics` + `.work`, branch tier) are used
  without writing `.claude/topic-docs.yaml`; the repo already conforms
  to the default layout and the concern-file persist step wants an
  interactive confirmation this autonomous run does not force.
- Dynamic rate-limit scaling is out of scope for this run (snapshot not
  visible in cloud); the user may file an upstream issue to expose it.

## Plan

1. **Inventory** — exhaustive two-pass survey (literal + semantic) via
   read-only subagent; roster returned with per-candidate evidence
   shapes. *(in flight)*
2. **Classify** — dedupe roster against `context/lessons.md`
   known-refused patterns; spot-promote 3 candidates to Tier 0 in the
   main session as a sanity check on the survey's evidence quality.
3. **Verify** — 6-gate `verify` per candidate (HARD GATE, batch ≥5) via
   Opus 5 workers, concurrency 2. Abort if ≥80% refuse (identify-pass
   diagnostic per `actions/batch.md` Step 2).
4. **Wave-plan** — file-overlap matrix → greedy wave grouping;
   sequential within any wave sharing files; parallel only for pairwise
   disjoint PROCEED candidates, still capped at 2.
5. **Execute** — per-cluster plan/execute via Opus 5 workers; citation
   form per `context/citation-form.md`; `rename-references` sweep on
   any heading change; `audit-encapsulation detect` during refactor;
   one commit per wave.
6. **Skill update** — apply the confirm-scope fallback + orchestrated
   mode to `plugins/docs-hygiene/skills/extract-ssot/` (SKILL.md,
   `actions/identify.md`) after the survey completes (avoids editing
   files the survey is reading); CHANGELOG entry per plugin convention.
7. **Close out** — verify and append novel lessons; batch audit log
   here; repo lint/validation on touched files; push; ready-for-review
   PR.

## Verify results (2026-08-15, 29 clusters, 0 worker errors)

| Verdict | Clusters |
|---|---|
| PROCEED (7) | C01 (14/0), C02 (31/0), C04 (32/0), C06 (14/8), C07 (16/0), C09 (12/0), C23 (4/1) |
| WARN-borderline (4) | C03 (21/0), C13 (11/0), C17 (9/0), C25 (16/0) — adversarial diff review before commit |
| REFUSE (18) | C05, C19, C20, C28, C29 (rule-of-three, n=2); C14, C15, C18, C22, C31, C32 (already-cites-canonical); C11, C12, C16, C21, C27 (low-roi); C10 (off-by-one-different-concern); C24 (primary-source-citation-gate) |

Counts are `inline/citing` from each worker's own Tier 0 grep. C03
returned both a cached PROCEED (19/0) and a live WARN (21/0); the WARN
verdict governs. Refusal rate 62% — under the 80% batch-abort
threshold. Full per-gate evidence: workflow journal (memory tier).

## Execution wave plan (cap 2, disjoint lanes; one commit per wave)

| Wave | Lane A | Lane B | Overlap rationale |
|---|---|---|---|
| 1 | C02 (setup contract; owns `PLUGIN-PHILOSOPHY.md` edits this wave) | C06 (untrusted-content convention) | disjoint |
| 2 | C01 (advisor-fallback trim) | C09 (README preamble deletion) | disjoint; philosophy edits sequential after W1 |
| 3 | C07 (probe ladder) | C13 (context-gather, WARN) | disjoint |
| 4 | C04 (settings-ownership trim) | C17 (songwriting attribution, WARN) | disjoint |
| 5 | C03 (reconfigure recipe rule-file, WARN) | C23 (mktemp idiom) | disjoint |
| 6 | C25 (enabledPlugins wording, WARN) | — | after C09's README commits |

Setup-skill chain C02 → C07 → C04 → C03 stays strictly sequential
across waves (shared `plugins/*/skills/setup/SKILL.md` files); README
chain C09 → C25 likewise. Portability constraint injected into every
worker: plugin runtime surfaces must stay operable standalone — a
marketplace-docs citation is provenance-only, never a runtime
dependency (the loop-lane inline-floor form is the precedent).

## Batch audit log (2026-08-15, final)

| Cluster | Verify | Execute verdict | Wave | Outcome |
|---|---|---|---|---|
| C02 | PROCEED 31/0 | EXTRACTED | 1 | philosophy §setup extended; 31 setup skills normalized |
| C06 | PROCEED 14/8 | EXTRACTED | 1 | new `docs/conventions/untrusted-content/`; 15 adopters |
| C01 | PROCEED 14/0 | EXTRACTED | 2 | 14 sites normalized; 4 drifted sites repaired |
| C09 | PROCEED 12/0 | EXTRACTED | 2 | Shape C deletion ×9 + in-file pointer ×3 |
| C07 | PROCEED 16/0 | EXTRACTED | 3 | check-opening block; 16 setup skills |
| C13 | WARN 11/0 | REVERTED → DEFERRED | 3 | review found refuted mechanism canonicalized (Lesson 12) |
| C04 | PROCEED 32/0 | EXTRACTED | 4 | never-writes sentence; 12 wordings → 1; 8 provenance gaps closed |
| C17 | WARN 9/0 | EXTRACTED (review approved) | 4 | songwriting attribution ×9 |
| C03 | WARN 21/0 | EXTRACTED (review repairs applied) | 5 | reconfigure recipe block; 7 sites normalized |
| C23 | PROCEED 4/1 | EXTRACTED | 5 | mktemp dialect semantics hoisted to topic-docs ephemeral tier |
| C25 | WARN 16/0 | REFUSED-cluster-exhausted-by-C09 | 6 | clean refusal after re-count (Lesson 14) |
| 18 others | REFUSE | (not dispatched) | — | refuse-fast savings: 18 execute dispatches avoided |

Dispatch policy: strictly sequential waves, ≤2 workers per wave, disjoint
file lanes; WARN clusters carried a fresh-context adversarial diff
review before commit (caught C13's 4 blocking findings and C03's 6).
Lessons 12–14 appended to the skill's `context/lessons.md` after
orchestrator re-verification. Follow-ups recorded in the PR body:
C02b userConfig-carve-out stragglers (5 setup skills), C01 compressed
cousins (2 sites), songwriting README skill-table drift, R10 telemetry
copy drift advisory, C13 mechanism probe.

## Status log

- **2026-08-15** — Contract locked via interview; survey subagent
  dispatched (inventory in flight); this slice opened. Next: roster
  classification when the survey returns.
- **2026-08-15 (resume)** — User go-ahead received; verify fleet
  resumed from cached run and completed 29/29 (tally above). Wave plan
  locked; execution begins with Wave 1 (C02 ∥ C06). CI review lanes
  (429-failed earlier) deferred to close-out to avoid competing with
  the fleet for windows.
- **2026-08-15 (later)** — Inventory complete: 32 candidates + 27
  refusals persisted to `design/roster.md`; orchestrator spot-check
  passed (C01 exact, C09 exact, C02 under-counted). Skill update
  committed (confirm-scope gate + `context/orchestrated-mode.md`,
  plugin 0.12.0). Verify fleet launched (29 clusters, Opus workers,
  cap 2), then **PAUSED at the user's request** amid account-wide
  rate-limit pressure (a CI security-review bot 429'd; this session
  saw no 429s itself). 4 verdicts cached before pause: C01 PROCEED
  (Tier 0: 14 inline), C03 PROCEED (19; planning-setup site scoped out
  per R06), C04 PROCEED (32; R06 trio excluded), C05
  REFUSE-rule-of-three-fails (n=2 — structurally capped at two
  plugins). Resume: re-invoke the verify workflow from the saved
  script with the recorded run id; cached verdicts replay free, C02
  onward re-runs. Then: ≥80%-refusal abort check → wave plan → execute.
