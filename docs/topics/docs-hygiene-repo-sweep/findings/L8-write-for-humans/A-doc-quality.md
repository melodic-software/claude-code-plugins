# A-doc-quality

Lane `L8-write-for-humans`, wave 1, read-only. Audience slice: 8 `HUMAN` rows (4 plugin READMEs,
4 CHANGELOGs). The 4 CHANGELOGs are judged as a class in `README.md`.

This group contains the resolved standard itself
(`plugins/ai-slop/skills/audit/reference/rewrite-guide.md`, an `AGENT` row belonging to `L7`), so
its READMEs get read closely.

## Findings

| # | Path | Predicate | Severity |
|---|---|---|---|
| A1 | `plugins/docs-hygiene/README.md:15` | `L1` | S2 |
| A2 | `plugins/docs-hygiene/README.md:18` | `L1` | S3 |

### A1. A 75-word single sentence in a table cell

`plugins/docs-hygiene/README.md:15`, the `/docs-hygiene:extract-ssot` row of the skills table.
Verbatim cell content:

```text
Deduplicates repeated content into a single named source of truth and migrates call sites to cite it by heading. Reports duplication at every multiplicity in three labelled buckets, a lone recap of an existing SSOT, a drifting pair with no declared owner, and clusters that meet the Rule of Three, while refuse-fast verification gates (Rule of Three, Tier-0 evidence) keep *creating* a new artifact reserved for 3+ instances; below that, only non-abstracting remedies are offered.
```

The second sentence runs 75 words with a three-item apposition, a parenthetical, a semicolon, and a
final subordinate clause. Predicate `L1`: the reader must backtrack to find out that the three
labelled buckets are the three items in the apposition. In a table cell, which is a glance surface,
that is worse than it would be in a paragraph.

Replacement for the cell:

```text
Deduplicates repeated content into a single named source of truth and migrates call sites to cite it by heading. Reports duplication at every multiplicity in three labelled buckets: a lone recap of an existing SSOT, a drifting pair with no declared owner, and a cluster that meets the Rule of Three. Refuse-fast verification gates reserve *creating* a new artifact for three or more instances; below that the skill offers only non-abstracting remedies.
```

Three changes: the apposition gets a colon so the reader knows the list is the buckets; the run-on
splits at the semicolon; and `3+` becomes `three or more`, because a table cell reads better as
prose than as shorthand.

### A2

`plugins/docs-hygiene/README.md:18`, the `/docs-hygiene:write-for-humans` row, 61 words in one
sentence. Same shape as A1, one degree milder. No replacement supplied; wave 3 applies the same
treatment, splitting at the sentence's `so the plugin never silently imposes a house style` clause.

## Document mode

All four plugin READMEs in this group hold one mode: reference with a short explanation lead and a
skills table. No mode findings.

Two things checked and cleared:

- `plugins/docs-hygiene/README.md:3`, verbatim:

  ```text
  A Claude Code plugin bundling documentation-hygiene skills. One cohesive
  capability: keeping a repository's tracked markdown lean, deduplicated, and
  free of decayed references.
  ```

  `One cohesive capability: …` is a verbless fragment. It is **not** a finding: the same cadence
  appears as the lead in nine plugin READMEs across the corpus (`Two skills, one concern: …`,
  `Three skills, one concern: …`, `A Claude Code plugin bundling one cohesive capability: …`). A
  repeated deliberate cadence is house voice, which the resolved guide's legitimate-hit class 5
  protects and which predicate `N1` positively wants kept consistent. Rewriting it in one README
  would break the class.

- `plugins/ai-slop/README.md` and the `markdown-format` and `typos-format` READMEs quote the tells
  they detect. That is legitimate-hit class 2 (text that documents the tell it bans). No findings,
  and wave 3 must not "fix" the quoted examples.

## Predicates with no findings in this group

`M1`, `M2`, `M3`, `A1`, `A2`, `Am1`, `Am2`, `Am3`, `Am4`, `N1`, `C1`.

On `M3`: all four plugin READMEs that carry a generated options block have it under
`## Configuration`. Fully conformant.

On `M2`: `plugins/markdown-format/README.md:12` and `plugins/typos-format/README.md:32` and `:35`
carry bare `(#1809)`, `(#2650)` citations. Each attaches a rationale to a present-tense design
statement rather than narrating a version change, and the bare form is house convention per
`docs/conventions/tracker-reference-form/README.md`. Not findings.

## Cross-lane observations

- **`ai-slop:audit`**: nothing in this group's READMEs. Note for the orchestrator that this group
  owns the detector and its rewrite guide, so a finding here would have been a dogfood failure.
- **`source-control`**: nothing in this group.
