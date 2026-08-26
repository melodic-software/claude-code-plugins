# D-work-planning

Lane `L8-write-for-humans`, wave 1, read-only. Audience slice: 14 `HUMAN` rows (4 plugin READMEs,
4 CHANGELOGs, and 6 adapter READMEs under `plugins/work-items/tools/work-item-tracker/`). The 4
CHANGELOGs are judged as a class in `README.md`.

## Findings

| # | Path | Predicate | Severity |
|---|---|---|---|
| D1 | `plugins/work-items/README.md:105` | `L1` | S2 |
| D2 | `plugins/planning/README.md:16` | `L1` | S2 |

### D1

`plugins/work-items/README.md:105`, 58 words, 5 interrupters, including a parenthetical nested
inside a parenthetical. Verbatim:

```text
**The work-item-tracker seam.** The plugin **ships** the seam (dispatcher, `schema.json`, and the `github`, `gitea`, `jira`, `linear`, and `local-markdown` adapters) under `tools/`; the consuming repo only declares its active provider in `.work-item-tracker.json` at the repo root (run `/work-items:onboard-adapter`; per-user lease TTL and per-provider auth identity (jira `email`/`token`, linear `key`, gitea `token`) may ride a gitignored `.work-item-tracker.local.json` overlay beside it).
```

Predicate `L1`. The nested parenthesis is the specific defect: by the time the reader reaches
`jira email/token` they are three levels deep and cannot tell which clause the closing parens
return them to. Also `Am3`: `email/token` is coordination and reads as one thing.

Replacement:

```text
**The work-item-tracker seam.** The plugin **ships** the seam under `tools/`: the dispatcher,
`schema.json`, and the `github`, `gitea`, `jira`, `linear`, and `local-markdown` adapters. The
consuming repo declares only its active provider, in `.work-item-tracker.json` at the repo root.
Run `/work-items:onboard-adapter` to write that file. A gitignored `.work-item-tracker.local.json`
overlay beside it may carry the per-user lease TTL and the per-provider auth identity: `email` and
`token` for jira, `key` for linear, and `token` for gitea.
```

### D2

`plugins/planning/README.md:16`, 57 words in a table cell describing `/planning:audit-answers`.
Verbatim:

```text
Independent adversarial validation of a completed `/planning:questionnaire`'s answers, over any filled ledger, hand-answered or auto-accepted: fresh-context validators re-examine each answer (rationale withheld) and return a per-answer confirmed / challenged / reclassified verdict, so only the challenged or reclassified answers, and every user-reserved decision, return as real human questions (open branches are accept
```

Predicate `L1`. Also `Am3`: `confirmed / challenged / reclassified` and `hand-answered or
auto-accepted` both coordinate with slashes and spaces, which reads as three separate things rather
than three values of one field.

Replacement for the cell:

```text
Independent adversarial validation of a completed `/planning:questionnaire`'s answers, over any filled ledger, hand-answered or auto-accepted. Fresh-context validators re-examine each answer with its rationale withheld and return one verdict per answer: `confirmed`, `challenged`, or `reclassified`. Only the challenged and reclassified answers, plus every user-reserved decision, return as real human questions.
```

The clause the quoted span cuts off (`open branches are accept…`) continues past the quote; wave 3
takes it as the next sentence.

### The remaining `L1` sentences in this group

Five over the filter:

```text
plugins/implementation/README.md:38
plugins/work-items/README.md:98
plugins/work-items/README.md:162
plugins/work-items/tools/work-item-tracker/adapters/github/README.md:313
plugins/planning/README.md:18
```

## Document mode

Four plugin READMEs, all reference with an explanation lead. No mode mixing.

Two sections examined for `M2` and **cleared**:

- `plugins/implementation/README.md:66`, `## Migrating from an earlier implementation`. Verbatim
  lead:

  ```text
  If you had `implementation` installed before the `0.6.0` split, `build`, `lint`, `setup`,
  `test-plan`, `test-write`, `test-e2e`, `test-diagnose`, `verify-changes`, and `verify-improvement`
  no longer live here, nine skills moved into the new `toolchain`, `testing`, and `verification`
  plugins.
  ```

  This names a version and says `no longer`, so the mechanical `M2` filter flags it. It is not a
  finding. The section is a **how-to** addressed to a real reader with a real problem (their skills
  vanished), its condition is stated first (`If you had implementation installed before the 0.6.0
  split`), and it ends with the commands that fix it. That is mode-correct and reader-serving. The
  predicate's carve-out covers it exactly.

  One `A1` note inside it, filed at S3: the sentence is a comma splice (`no longer live here, nine
  skills moved into`) and the instruction that follows is also spliced (`does not apply, install the
  plugins you relied on:`). Wave 3 may replace both commas with a period or a colon while it is in
  the file. No behavior change, and it does not need a separate finding.

- The six adapter READMEs under `plugins/work-items/tools/work-item-tracker/adapters/` are developer
  reference for people writing an adapter. They hold reference mode cleanly. No findings.

## Predicates with no findings in this group

`M1`, `M2`, `M3`, `A2`, `Am1`, `Am2`, `Am4`, `N1`, `C1`.

On `M3`: all plugin READMEs in this group that carry a generated options block have it under
`## Configuration`. Fully conformant.

## Cross-lane observations

- **`ai-slop:audit`**: nothing in this group's READMEs.
- **`source-control`**: nothing in this group.
