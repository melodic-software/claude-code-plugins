# B-cc-config-ops

Lane `L8-write-for-humans`, wave 1, read-only. Audience slice: 15 `HUMAN` rows (7 plugin READMEs,
7 CHANGELOGs, no `docs/**`). Predicates and severities are defined in `predicates.md`; the resolved
standard is in `standard-resolution.md`.

The 7 CHANGELOGs are judged as a class in `README.md`, not file by file.

## Findings

| # | Path | Predicate | Severity |
|---|---|---|---|
| B1 | `plugins/claude-ops/README.md:40` | `Am1` | S1 |
| B2 | `plugins/claude-ops/README.md:60` | `Am1` | S1 |
| B3 | `plugins/context-guard/README.md:109` | `Am1` | S1 |
| B4 | `plugins/guardrails/README.md:213` | `Am1` | S2 |
| B5 | `plugins/context-budget/README.md:78` | `M3` | S2 |
| B6 | `plugins/context-guard/README.md:127` | `M3` | S2 |
| B7 | `plugins/guardrails/README.md:338` | `M3` | S2 |
| B8 | `plugins/rate-limit-guard/README.md:119` | `M3` | S2 |
| B9 | `plugins/claude-config/README.md:125` | `L1` | S2 |
| B10 | `plugins/claude-config/README.md:157` | `L1` | S2 |
| B11 | `plugins/claude-ops/README.md:29` | `L1` | S2 |

### B1. A fragment inside the opening parenthetical of `## The audit hooks`

`plugins/claude-ops/README.md:40`, verbatim:

```text
Eight advisory `*-audit` hooks (across nine hook scripts. `skill-usage-audit` has two producers, see below) emit the marketplace
```

`across nine hook scripts` is a fragment, and the period after it forces the reader to reparse the
whole sentence to work out that the parenthetical has not ended. Predicate `Am1`.

The contrast is four lines down in the same paragraph, where the same author gets it right:

```text
boolean (default **on**; see [Per-hook kill switches](#per-hook-kill-switches)).
```

That one uses a semicolon inside the parenthesis and stays one grammatical unit.

Replacement for line 40:

```text
Eight advisory `*-audit` hooks, spread across nine hook scripts because `skill-usage-audit` has two
producers, emit the marketplace
```

The `see below` pointer is redundant with the `Per-hook kill switches` link four lines down and is
dropped.

### B2. The same shape in the `hook-failure-audit` paragraph

`plugins/claude-ops/README.md:60`, verbatim:

```text
failing hook registration (`hookName` plus registered command. Several plugins
share an event+matcher), re-warning when a new registration starts failing.
```

Predicate `Am1`. `` `hookName` plus registered command `` is a noun phrase, not a sentence, and what
follows the period is the reason for it.

Replacement:

```text
failing hook registration, keyed on `hookName` plus the registered command because several plugins
share an event and matcher, re-warning when a new registration starts failing.
```

### B3. Cost sentence with a fragment inside the parenthetical

`plugins/context-guard/README.md:109`, verbatim:

```text
Cost: the tee adds roughly 0.6–0.9 s per statusline refresh on Windows/Git Bash (process-spawn
bound. `jq` and `date`), and correspondingly less on native POSIX shells.
```

`process-spawn bound` is a fragment and `` `jq` and `date` `` is a bare noun phrase; neither is a
sentence, so the internal period is wrong. Predicate `Am1`. The `Windows/Git Bash` slash is a
platform pair rather than coordination, so `Am3` does not reach it.

Replacement:

```text
Cost: the tee adds roughly 0.6–0.9 s per statusline refresh on Windows under Git Bash, where the
cost is process-spawn bound on `jq` and `date`, and correspondingly less on native POSIX shells.
```

### B4. Two sentences welded into one parenthetical

`plugins/guardrails/README.md:213`, verbatim:

```text
Each guard is toggled by its own `userConfig` boolean (default **on**, except
the two behavioral-class advisories `workflow-resilience-check` and
`flag-commit-pr-skill-bypass`, default **off** since 0.20.0 per #2021. Set to
`true` to opt in; set any switch to `false` for a clean no-op). This per-hook
```

The parenthetical carries a description and then an instruction. Predicate `Am1`, and the
instruction should not be inside a parenthetical at all: `A1` wants a command in its own sentence.

Replacement:

```text
Each guard is toggled by its own `userConfig` boolean, default **on**, except the two
behavioral-class advisories `workflow-resilience-check` and `flag-commit-pr-skill-bypass`, which
have been default **off** since 0.20.0 per #2021. Set a switch to `true` to opt in, or to `false`
for a clean no-op. This per-hook
```

### B5 to B8. The generated options block is not under `## Configuration`

Class finding, detailed once in `README.md` under `M3`. This group holds four of the sixteen
outliers:

| Path | Heading the block sits under | Options block at |
|---|---|---|
| `plugins/context-budget/README.md:78` | `## Boundaries` | line 90 |
| `plugins/context-guard/README.md:127` | `## Consumers` | line 136 |
| `plugins/guardrails/README.md:338` | `## Install` | line 355 |
| `plugins/rate-limit-guard/README.md:119` | `## Consumers` | line 128 |

Remediation in every case: move the whole marker-delimited block, from
`<!-- ai-slop-ignore-start: generated options block` through the matching `<!-- END GENERATED`
and its `ai-slop-ignore-end`, together with the `### How to set these` subsection that follows it,
so it sits under a `## Configuration` heading. Where the plugin has no `## Configuration` heading,
add one. Do not edit the generated table itself; it is regenerated by
`scripts/sync-plugin-options-docs.py`.

`guardrails` is the worst of the four: a reader following `## Install` gets two commands and then a
21-row option table, which is Diátaxis how-to and reference in one section with no link between
them.

### B9 to B11. Sentences the reader has to backtrack through

Predicate `L1`. This group has 16 sentences over the filter (45 or more words, 3 or more clause
interrupters). The three worst are given with replacements; the remaining 13 are listed after them
for the wave 3 editor to handle with `L6-compress` in the same pass.

#### B9

`plugins/claude-config/README.md:125`, 80 words, 7 interrupters. Verbatim:

```text
It supplies the run semantics that invoking those skills by hand does not: a three-scope inventory
taken before any check runs (managed policy read-only, user scope routed as recommendations,
project scope), an exclusion set derived at run time from the target's own shared-source registry,
the `audit-pass` rule, `.gitignore`, and the pass's own artifacts; content-derived finding identity
that survives an unrelated edit
```

Replacement, splitting the list off its lead-in:

```text
It supplies run semantics that invoking those skills by hand does not:

- A three-scope inventory taken before any check runs: managed policy read-only, user scope routed
  as recommendations, and project scope.
- An exclusion set derived at run time from the target's own shared-source registry, the
  `audit-pass` rule, `.gitignore`, and the pass's own artifacts.
- Content-derived finding identity that survives an unrelated edit.
```

The exact tail of the original sentence continues past the quoted span; the wave 3 editor takes the
remaining clauses as further bullets in the same list.

#### B10

`plugins/claude-config/README.md:157`, 79 words, 8 interrupters. The four-phase description packs a
parenthetical gloss into each phase name. Verbatim opening:

```text
Four resumable phases: **snapshot** (inventory the live project surfaces on a dedicated experiment
branch, classify hooks policy-vs-behavioral), **bare** (reversibly strip the behavioral tier:
tracked files via git, settings entries via manifest-recorded backups; policy gates and managed
settings are never touched), **observe** (work normally in fresh sessions, logging real stumbles to
a ledger),
```

Replacement: a four-row table, one phase per row, which is the reference form this content already
is.

```text
Four resumable phases:

| Phase | What it does |
|---|---|
| `snapshot` | Inventories the live project surfaces on a dedicated experiment branch and classifies each hook as policy or behavioral |
| `bare` | Reversibly strips the behavioral tier: tracked files via git, settings entries via manifest-recorded backups. Policy gates and managed settings are never touched |
| `observe` | You work normally in fresh sessions, logging real stumbles to a ledger |
```

The fourth phase is on the lines following the quoted span and takes the fourth row.

#### B11

`plugins/claude-ops/README.md:29`, 100 words in a single table cell, 6 interrupters. This is the
longest single sentence in any plugin README. Verbatim opening:

```text
One timed engine pass separates the four documented suspects: accumulated install-tree state
(retention-sweep health including the silent unparsable-`state` pause, plus a timed stat-walk whose
duration approximates the product's own daily sweep cost), version regression (CLI version against
a bundled known-performance-issues reference), component bloat (fleet and process censuses, verdict
routed to `audit-native-overlap`)
```

A table cell is a glance surface. Replacement for the cell:

```text
One timed engine pass separates four documented suspects: accumulated install-tree state, version
regression, component bloat, and the fourth named in the skill body. Each suspect's evidence and
verdict routing is documented in the skill.
```

The detail deleted from the cell is not lost: it is already in
`plugins/claude-ops/skills/audit-performance/SKILL.md`, which is where a reader who needs it will
be. This is the same rule-of-one remedy `L3-ssot` prefers, applied in place.

#### The remaining 13 `L1` sentences in this group

Listed for the wave 3 editor. Each is over the filter and each takes the same treatment: split the
list off its lead-in, or move the detail to the skill body and leave the glance line.

```text
plugins/claude-config/README.md:17
plugins/claude-config/README.md:59
plugins/claude-config/README.md:229
plugins/claude-ops/README.md:27
plugins/claude-ops/README.md:28
plugins/claude-ops/README.md:34
plugins/context-budget/README.md:22
plugins/context-budget/README.md:43
plugins/context-guard/README.md:24
plugins/context-guard/README.md:38
plugins/guardrails/README.md:14
plugins/guardrails/README.md:32
plugins/guardrails/README.md:105
```

## Document mode

The seven plugin READMEs in this group are **reference** documents with an explanation lead. That is
the right mode for the class and six of the seven hold it. Two mode findings:

### `plugins/guardrails/README.md` mixes how-to and reference under one heading

Covered as B7. `## Install` is how-to; the `### Options reference` and `### How to set these`
subsections nested under it are reference. The skill's rule is explicit: split and link instead.

### `plugins/context-guard/README.md:38` is explanation shelved under a reference heading

Verbatim:

```text
Its companion `channel-inventory.md` is the writer-side channel inventory: why the statusline is the
only capture channel, which other channels were checked and rejected (with sources and dates),
including the two that do carry live occupancy and still cannot supply a snapshot, and why
`context_remaining` in a session that runs no statusline, a cloud or headless session by default, is
structural rather than a defect.
```

The sentence is doing explanation work ("why", "rather than a defect") and it is the only such
sentence in its section. Severity S3: the pointer earns its place because a reader hitting the
missing-statusline case needs to know it is expected. The finding is the packing, not the content,
and it is already covered as an `L1` entry above. **No separate mode edit.** Recorded here so the
wave 3 editor does not flatten the explanation out of it while splitting the sentence: the resolved
guide's register gate protects an author's view in a narrative section.

## Predicates with no findings in this group

`M2`, `A1`, `A2`, `Am2`, `Am3`, `Am4`, `N1`, `C1`.

On `M2`: `plugins/guardrails/README.md` carries `default off since 0.20.0 per #2021` at four sites.
Each one explains why a hook a reader expected is silent, which is present-tense information a
current reader needs. Exempt per the predicate's own carve-out. `(#N)` citation form is house
convention per `docs/conventions/tracker-reference-form/README.md` and is never a finding here.

On `C1`: `plugins/claude-ops/README.md:3` claims `twelve skills` and the tree has 12.
`plugins/claude-config/README.md` and the other five were checked the same way. All correct.

## Cross-lane observations

- **`ai-slop:audit`**: nothing in this group's READMEs.
- **`source-control`**: nothing in this group.
