# J-toolchain-platform

Lane `L8-write-for-humans`, wave 1, read-only. Audience slice: 39 `HUMAN` rows (18 plugin READMEs,
18 CHANGELOGs, plus `plugins/machine-health/skills/audit/README.md`,
`plugins/rate-limit-guard/bench/README.md`, and two fixture READMEs this lane reclassifies out).
The 18 CHANGELOGs are judged as a class in `README.md`.

This is the largest group by plugin count and the second-largest source of `M3` outliers.

## Findings

| # | Path | Predicate | Severity |
|---|---|---|---|
| J1 | `plugins/machine-health/README.md:76` | `M3` | S1 |
| J2 | `plugins/instruction-placement/README.md:124` | `M3` | S1 |
| J3 | `plugins/skill-quality/README.md:111` | `M3` | S2 |
| J4 | `plugins/desktop-notification/README.md:85` | `M3` | S2 |
| J5 | `plugins/wizard/README.md:35` | `L1` | S2 |
| J6 | `plugins/plugin-quality/README.md:9` | `L1` | S2 |
| J7 | reclassification | two fixture READMEs | n/a |

### J1. The options reference is under `## Tests`

`plugins/machine-health/README.md:76`, block at line 88. Verbatim heading and section:

```text
## Tests

A Pester 5.7+ suite ships with the plugin (`skills/audit/tests/`). Windows-only. It
mocks Win32/MSFT CIM types that resolve only there:
```

Predicate `M3`, severity S1. This is the least findable placement in the corpus alongside
`plugins/disk-hygiene/README.md`'s `## Sources`. A consumer setting `report_dir` has no reason to
open a section about the plugin's Pester suite, and the section itself is contributor documentation.

Remediation as in `B-cc-config-ops.md`: move the marker-delimited block, from
`<!-- ai-slop-ignore-start: generated options block` through the matching `<!-- END GENERATED` and
its `ai-slop-ignore-end`, together with the `### How to set these` subsection, under a new
`## Configuration` heading placed before `## Tests`. Do not edit the generated table.

### J2. The options reference is under `## Revisit triggers`

`plugins/instruction-placement/README.md:124`, block at line 139. Verbatim heading and lead:

```text
## Revisit triggers

Conditions that should change this plugin, recorded so they are acted on rather than forgotten.
```

Predicate `M3`, severity S1. The section is a maintainer's watchlist. Its own lead sentence says so.
The consumer-facing options table is 15 lines below it under the same heading. Same remediation as
J1.

### J3 and J4

| Path | Heading the block sits under | Options block at |
|---|---|---|
| `plugins/skill-quality/README.md:111` | `## Requirements` | line 123 |
| `plugins/desktop-notification/README.md:85` | `## Telemetry (opt-in)` | line 95 |

Both S2 rather than S1: `## Requirements` and `## Telemetry (opt-in)` are at least consumer-facing,
so a reader scanning the document will pass over them. Same remediation.

### J5

`plugins/wizard/README.md:35`, 99 words, 8 interrupters, the longest-scoring sentence in the corpus
by interrupter count. Verbatim opening:

```text
**Hardened template.** The fixed library above the `# ---` marker (never hand-edited, identical in every wizard) enforces: https-only URL opening with the full URL printed before dispatch; fail-closed prompts (a closed terminal aborts, it never falls through); key-name validation; single-quoted, escaped `.env` values with `chmod 600` after every write, an is-it-gitignored check, and trap-cleaned atomic temp-f
```

Predicate `L1`. The content is a list of guarantees and it is already punctuated as one, with
semicolons. Turning it into an actual list costs nothing and removes all eight interrupters.

Replacement:

```text
**Hardened template.** The fixed library above the `# ---` marker is never hand-edited and is
identical in every wizard. It enforces:

- https-only URL opening, with the full URL printed before dispatch.
- Fail-closed prompts: a closed terminal aborts rather than falling through.
- Key-name validation.
- Single-quoted, escaped `.env` values, with `chmod 600` after every write.
- An is-it-gitignored check.
- Trap-cleaned atomic temp files.
```

The final bullet's wording is reconstructed from the truncated `temp-f` in the quoted span. **Wave 3
must read the full sentence in the file and use its actual wording**, plus any further items past
the quote, rather than the reconstruction here.

### J6

`plugins/plugin-quality/README.md:9`, 77 words, 7 interrupters. Verbatim opening:

```text
**Audit skill** (`/plugin-quality:audit`), the six-step hub: (1) evidence capture on the main thread into a durable, compaction-proof packet; (2) map + ground in the fresh `plugin-auditor` subagent, with every load-bearing harness-behavior claim verified against current official docs; (3) persist-check on the returned findings, then blindspot pass + candidates; (4) interactive contract lock (scope, severity, assumptions,
```

The quote is cut mid-word at the 300-character scan limit; step 4's final clause and steps 5 and 6
continue in the file.

Predicate `L1`. Same shape as J5: a numbered sequence written inline. It is a **sequence**, so per
the address layer it takes a numbered list, not bullets.

Replacement:

```text
**Audit skill** (`/plugin-quality:audit`), the six-step hub:

1. Evidence capture on the main thread, into a durable, compaction-proof packet.
2. Map and ground in the fresh `plugin-auditor` subagent, with every load-bearing harness-behavior
   claim verified against current official docs.
3. Persist-check on the returned findings, then a blindspot pass and candidates.
4. Interactive contract lock: scope, severity, assumptions, and what is written down.
```

Steps 5 and 6 continue past the quoted span. **Wave 3 reads them from the file** and adds them as
list items 5 and 6. Step 4's final clause is cut off in the quote above and must be taken from the
file rather than from the reconstruction here.

### J7. Reclassification: two fixture READMEs in the human slice

```text
plugins/machine-health/skills/audit/tests/fixtures/windows/README.md
plugins/machine-health/skills/audit/tests/fixtures/windows/Environment/README.md
```

Both are classified `HUMAN` in `inventory/manifest.tsv`. Both are test-fixture scaffolding under a
`tests/fixtures/` path. Reclassify as **out of scope: functional artifact**, matching
`L1-derivability`'s category for the same shape. No authoring doctrine applies and no edit is
proposed. See `README.md` for the full reclassification set.

`plugins/autonomy/skills/setup/scripts/fixtures/prerequisite-resolution/positive-verdict/repo/docs/README.md`
is the same shape but sits in group `E-session-behavior`. It is reported in the roll-up rather than
twice.

### The remaining `L1` sentences in this group

Two over the filter beyond J5 and J6:

```text
plugins/markdown-format/README.md:109
plugins/powershell-format/README.md:37
```

`plugins/markdown-format/README.md` belongs to group `A-doc-quality` by the plan's partition; it is
listed here because the mechanical scan groups by plugin directory. The wave 3 editor should take it
from whichever file it reaches first, once.

## Document mode

Eighteen plugin READMEs. The formatter plugins (`actionlint`, `bash-format`, `biome-format`,
`eol-normalizer`, `go-format`, `powershell-format`, `ruff-format`) share a tight house shape:
lead, `## Behavior` as a bulleted reference list, `## Requirements`, `## Install`,
`## Configuration`, `## License`. All seven hold one mode. No findings.

The four `M3` findings above are mode findings in substance: reference content placed under a
heading that promises something else. Two of them (`## Tests`, `## Revisit triggers`) also put
contributor content and consumer content in one document, the same two-audience question raised in
`H-knowledge-research.md`. Filed at S3 there and not repeated as a separate finding here.

`plugins/machine-health/README.md:54`, `## Migrating from an in-repo copy`, was checked against `M2`
and **cleared** for the same reason as `plugins/implementation/README.md:66`: it is a how-to
addressed to a reader with a real present problem, its condition is stated first, and it ends with
numbered steps. Mode-correct.

## Predicates with no findings in this group

`M1` as its own finding, `M2`, `A1`, `A2`, `Am1`, `Am2`, `Am3`, `Am4`, `N1`, `C1`.

On `C1`: `plugins/skill-quality/README.md:117` claims `the other twenty-four still gate`. This is a
count of gate checks, not of skills, so `scripts/check-skill-count-claims.sh` does not cover it and
this lane could not verify it from the tree. **Recorded as an unverified claim rather than as a
finding.** Wave 3 or the orchestrator may want to check it against
`plugins/skill-quality/skills/check/`, and, per the skill's third survives-the-guide rule, the doc
should carry the command that regenerates the number.

## Cross-lane observations

- **`ai-slop:audit`**: nothing in this group's READMEs.
- **`source-control`**: nothing in this group.
