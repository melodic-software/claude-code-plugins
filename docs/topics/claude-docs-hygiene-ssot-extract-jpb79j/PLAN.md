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

## Status log

- **2026-08-15** — Contract locked via interview; survey subagent
  dispatched (inventory in flight); this slice opened. Next: roster
  classification when the survey returns.
