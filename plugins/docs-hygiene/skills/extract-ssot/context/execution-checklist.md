# Execution checklist

Per-phase checks for the `execute` action. SKILL.md ships the phase header (identify-cluster → architect-plan → execute-migration → sweep-references → verify); this file covers what to verify before, during, and after each call site is migrated.

Composes with `decision-framework.md` (gate before extraction), `citation-form.md` (form at each call site), `/encapsulation-audit` (remediation paths for violations), `anti-patterns.md` (failure modes to guard against), and SKILL.md "Evidence discipline" (Tier 0 evidence).

## Pre-extraction (before writing or extending the SSOT)

Run ALL of these. Any failure means STOP — do not proceed to writing or extending the SSOT.

| # | Check | Evidence required | Source |
|---|-------|-------------------|--------|
| 1 | 3+ instances confirmed via grep | Tier 0 grep output captured this turn (NOT recall); count + file list recorded in the working notes | SKILL.md "Evidence discipline" + `decision-framework.md` test #1 |
| 2 | All 6 extraction-gate tests pass (Rule of Three, namable, stable, self-contained, bounded size, one level deep) | Decision-framework checklist marked in the working notes; one bullet per test with PASS/FAIL annotation | `decision-framework.md` "EXTRACT into shared SSOT only when ALL six tests pass" |
| 3 | Output type chosen | Consolidate-into-existing-home / rule file / skill / new action decided; rationale recorded in the working notes | `decision-framework.md` "Output type: rule file vs skill" |
| 4 | Stable headings list drafted | Headings the SSOT will expose are pre-named; the working notes capture them so callers can be migrated atomically | `citation-form.md` "Rename discipline" |
| 5 | Encapsulation classification done | Each consumer marked as "vocabulary citer" (cite-by-name OK) vs "behavior caller" (route via `/name` needed) | `/encapsulation-audit` |
| 6 | User has reviewed the plan | Phase-boundary user gate: the user diff-reviewed the plan before execute; never auto-stage or auto-commit | SKILL.md "What this skill does NOT do" |

If any check fails, record a defer decision in the working notes and stop. Do NOT silently proceed.

## Per-callsite (during migration of each consumer)

Run for EACH call site. The callsite list is locked in the working notes from the pre-extraction phase.

| # | Check | Evidence | Source |
|---|-------|----------|--------|
| 1 | Citation/import in form native to the call site's file class | Markdown: `` per `<file>.md` "Y" `` form. Code: native `import` / `using` / `source`. Config: YAML anchor / JSON `$ref` / build-tool include | `citation-form.md` "Headline contract" (markdown form); language-idiomatic for code/config |
| 2 | Exact identifier match (heading / function / anchor) — no fuzzy or positional refs | Diff inspection | `anti-patterns.md` #1 (citation rot) |
| 3 | 1-line inline summary present where context needed | Markdown: `— <description>` after the citation in body paragraphs (Cross-references sections OK without summary). Code: descriptive import name + brief comment at non-obvious call sites. Config: descriptive anchor name | `citation-form.md` "1-line inline summary template" |
| 4 | One level deep — citation does NOT chain through another SSOT | Diff inspection; the SSOT itself does not cite another SSOT for the same domain. Code: no re-export-only modules | `anti-patterns.md` #2 (over-indirection) |
| 5 | Heading text on one line at the call site (markdown only) | Diff inspection | `citation-form.md` "Line-wrap edge case" |
| 6 | Encapsulation violation handled | If the consumer's content was promoted out of a skill: citation rewritten to the new home. If routed: the caller invokes `/<skill> <action>` instead of reading an internal file. If no public action exists: side observation filed, NOT a silent workaround | `/encapsulation-audit` |
| 7 | No leaky-abstraction context-bleed introduced | Markdown: no `prior`, `earlier`, `above`, `as discussed`, `the X we mentioned` referring outside the call site. Code: no implicit dependency on caller-side global state. Config: no implicit variable inheritance | `anti-patterns.md` #3 (leaky abstraction) |
| 8 | Lint clean on the edited file (per file class) | Markdown: `npx markdownlint-cli2 <file>` (or the repo's markdown linter) exits 0. Code/config: the repo's language-native linter | The consuming repository's lint conventions |

If a callsite fails any check, fix in place before moving to the next callsite. Do NOT batch failures across callsites — single-callsite review is the smallest reviewable unit.

## Sweep references (after all callsites migrated)

After every callsite is migrated, run the rename sweep across the WHOLE repo to catch citations that weren't in the pre-extraction inventory.

**Consolidate-into-existing-home branch:** when the migration only adds citations to a stable existing heading (no identifier renamed), the `/rename-references` sweep is a no-op — skip it; the work is straggler-migration + de-recap only (consistent with `verify` Gate 2's SOME-cite straggler path and anti-pattern Shape C "no identifier change → no sweep"). Gates below that assume a freshly-written file (size bound, "SSOT file exists") apply to creation outputs only.

| # | Check | Command | Source |
|---|-------|---------|--------|
| 1 | All 10 syntactic forms swept | `/rename-references` invoked with the SSOT name + each new identifier (heading / function / anchor) as renames-of-record | `/rename-references` (owns the 10-pattern sweep) |
| 2 | Pure-token grep returns no orphans | `grep -rn 'OldText\|OldIdentifier'` across all tracked files returns clean | `citation-form.md` "Rename discipline" |
| 3 | New SSOT is grep-discoverable | `grep -rn '<new-filename-or-identifier>'` across tracked files shows the expected callsites | Tier 0 verification |
| 4 | No violation patterns reintroduced | Re-run `/encapsulation-audit detect` | `/encapsulation-audit` |
| 5 | Code/config: language-aware refactor cross-checked | If applicable, run the IDE rename refactor and confirm the result matches the grep sweep — the IDE catches typed call sites grep misses | `anti-patterns.md` #1 |

## Post-extraction (before declaring done)

Final gates before the phase-boundary user gate.

| # | Check | Evidence | Source |
|---|-------|----------|--------|
| 1 | SSOT reads sensibly in isolation (leaky-abstraction self-test) | Open the SSOT fresh; read top-to-bottom; confirm meaning is clear without surrounding context | `anti-patterns.md` #3 |
| 2 | All cross-references / imports resolve | For each `per X.md "Y"` in the new SSOT, grep X.md for the literal heading "Y" — exact match. For code: build/typecheck pass. For config: schema-validate passes | Tier 0 verification at citation resolution |
| 3 | SSOT file size within bound | Markdown: `wc -l <ssot-file>` < 500. Code/config: per language idiom | `decision-framework.md` test #5 |
| 4 | Lint clean across all edited files | Markdown: `npx markdownlint-cli2` (or the repo's markdown linter). Code/config: the repo's per-ecosystem linter | The consuming repository's lint conventions |
| 5 | The repo's own verification reports green for all changed ecosystems | Build + test + lint pass per the consuming repository's verification workflow | The consuming repository's verification conventions |
| 6 | Working notes updated: phase marked done + next action recorded | Status entry in the working notes | SKILL.md "Phases per invocation" |
| 7 | Handoff entry written so a fresh session can resume | Dated entry in the working notes: what changed, what's next | SKILL.md "Phases per invocation" |
| 8 | Side observations surfaced | If new candidates were discovered during execution, surface as one-line callouts (≤2 per response; never block the current task) | `actions/verify.md` "Side observations" |

## Sanity-check format for the working notes

Every phase ends with a Sanity Check item in the working notes. For an `execute` phase the format is:

```markdown
- [ ] **Sanity Check:**
  - SSOT file at `<path>` exists and is < 500 lines
  - All N callsites migrated (list in the phase handoff entry)
  - `/rename-references` sweep ran clean
  - markdownlint clean
  - The repo's verification reports green
  - Cross-references in the SSOT resolve to real headings
```

Tick the box only when ALL bullets are confirmed via direct evidence — Tier 0 (tool output captured this turn), not recall.

## Failure recovery

If post-extraction gates fail:

| Failure | Action |
|---------|--------|
| Gate 1 (leaky abstraction) | Edit the SSOT to be self-contained; re-run the gate; if irrecoverable → `unwind` action |
| Gate 2 (cross-reference doesn't resolve) | Either fix the citation OR fix the SSOT heading; re-run the sweep |
| Gate 3 (>500 lines) | Split the SSOT into multiple files (one per coherent topic) OR push detail to a `context/<topic>.md` |
| Gate 4 (lint failure) | Fix lint; re-run |
| Gate 5 (repo verification red) | The failure is not out of scope — fix it before proceeding, never defer |
| Gate 6-7 (working notes not updated) | Update; re-run the gate |
| Gate 8 (no side observations surfaced when new candidates were found) | Surface as one-line callouts at the end of the response (≤2 per response) |

If failure compounds (3+ gates fail), invoke the `unwind` action and re-evaluate via `identify` — the extraction shape was probably wrong.

## Cross-references

- `decision-framework.md` — pre-extraction gate that should have been passed before reaching this checklist
- `citation-form.md` — per-callsite citation contract
- `/encapsulation-audit` — per-callsite promote-vs-route decision (separate skill)
- `anti-patterns.md` — failure modes the per-callsite checks guard against
- SKILL.md "Evidence discipline" — evidence discipline for "all checks pass" claims
- SKILL.md "Phases per invocation" — working-notes persistence model
