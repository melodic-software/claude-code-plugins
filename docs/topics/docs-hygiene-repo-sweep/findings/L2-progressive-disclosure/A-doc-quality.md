# L2 progressive disclosure: `A-doc-quality`

78 files, 15 `T2`. Plugins: `ai-slop`, `docs-hygiene`, `markdown-format`, `typos-format`.

Totals: T1=1, T2=8, T3=1.

## Split lane

**No findings.** The largest `T2` body in this group is
`plugins/docs-hygiene/skills/audit-noise/SKILL.md` at 210 lines / 3,424 words, comfortably under
both the 500-line and 5k-token ceilings. The small-corpus guard applies to the rest.

`plugins/ai-slop/skills/audit/reference/catalog.md` is 901 lines, but it is `T3` and it is one
concern: `SKILL.md:20` names it the single rule inventory both detection layers read, so splitting
it would break that contract. Its defect is navigational, treated under `missing-toc` below.

## Structure lane

### `missing-toc` (Tier 1)

| Path | Lines | Evidence |
|---|---|---|
| `plugins/ai-slop/skills/audit/reference/catalog.md` | 901 | File opens at line 1 with `# AI-writing tell catalog`, then prose, then `## Attribution and license` at line 12. No `## Contents` block. |

Remediation: insert a `## Contents` section immediately after the opening paragraph (before the
`<!-- ai-slop-ignore-file: ... -->` comment on line 11), listing every `##` heading as an anchor
link. Follow the pattern already used in this repo at
`plugins/docs-hygiene/skills/audit-progressive-disclosure/context/tier-model.md:3-9`. Add one line
above the list stating the grep recipe for row lookup, since the file is consulted per tell rather
than read end to end.

### `blind-pointer` (Tier 2)

Five sibling skills carry the identical bare shared-fallback pointer. Same treatment for all five.

| Path:line | Verbatim |
|---|---|
| `plugins/docs-hygiene/skills/audit-derivability/SKILL.md:78` | `Shared clean-tree / no-scope shape: [`../../context/clean-tree-fallback.md`](../../context/clean-tree-fallback.md).` |
| `plugins/docs-hygiene/skills/audit-noise/SKILL.md:83` | same sentence |
| `plugins/docs-hygiene/skills/audit-progressive-disclosure/SKILL.md:69` | same sentence |
| `plugins/docs-hygiene/skills/compress/SKILL.md:76` | same sentence |
| `plugins/docs-hygiene/skills/extract-ssot/SKILL.md:100` | same sentence |

The line names the target and nothing else: no read condition, no execute-vs-read intent. The
numbered list that follows it supplies the behavior inline, so a reader has no reason to open the
target and no statement of when opening it would help.

Remediation, per file, replacing the quoted line:

```markdown
Read [`../../context/clean-tree-fallback.md`](../../context/clean-tree-fallback.md) before
offering a repo-wide audit, when the arg is empty and the tree is clean: it owns the offer
wording and the unattended-stop rule the numbered defaults below assume.
```

### `blind-pointer`: index sections with no load condition (Tier 2)

Three hub sections list spokes with a what-it-holds description but no when-to-read clause. The
repo's own better pattern is `plugins/plugin-quality/skills/audit/SKILL.md:485`
(`## Reference index. Load on demand`).

| Path:line | Verbatim heading |
|---|---|
| `plugins/docs-hygiene/skills/audit-encapsulation/SKILL.md:200` | `## Cross-references` |
| `plugins/docs-hygiene/skills/compress/SKILL.md:149` | `## Cross-references` |
| `plugins/docs-hygiene/skills/extract-ssot/SKILL.md:220` | `## Cross-references` |

Sample row, `plugins/docs-hygiene/skills/extract-ssot/SKILL.md:224`:

```text
- `context/anti-patterns.md`. 13-pattern taxonomy with mitigations
```

Remediation: rename each heading to `## Reference index. Load on demand`, and give each row a
trailing when-clause. For the sampled row:

```markdown
- `context/anti-patterns.md`. Read when classifying a duplication instance you cannot place:
  the 13-pattern taxonomy with mitigations.
```

### `missing-toc`, 100 to 300 lines (Tier 3, awareness only)

5 files in this group are reference-shaped and sit in the 100 to 300 line band with no TOC. The
two official sources disagree at this length (platform best-practices says a TOC is expected above
100 lines, `skill-creator` says above 300), so these carry no treatment.

## Cross-lane observations

- The rubric script this lane runs on,
  `plugins/docs-hygiene/skills/audit-progressive-disclosure/scripts/detect.sh:186`, has a
  correctness bug that inverts its own orphan output: `md_links()` ends in a pipeline whose first
  stage is `grep`, so under `set -euo pipefail` it exits 1 for any file with zero markdown links,
  which aborts the `{ md_links ...; grep -oE '`[^`]+\.md`' ...; }` group in `ref_candidates()`
  before the backtick branch runs. Every hub whose `SKILL.md` cites spokes only in backticks
  therefore reports all its spokes as orphans. Measured effect on this corpus: 132 reported
  orphans against 4 real ones. It also cannot resolve `${CLAUDE_PLUGIN_ROOT}`-rooted or`@./`
  citation forms, which are this repo's dominant conventions. Not a docs finding; belongs to
  whoever owns that script.
- `plugins/ai-slop/skills/audit/reference/catalog.md` quotes the tells it detects and carries an
  `ai-slop-ignore-file` marker at line 11. The L5/L6 lanes should honor that marker.
