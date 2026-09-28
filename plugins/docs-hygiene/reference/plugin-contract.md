# docs-hygiene plugin contract

Recorded decision for
[#4142](https://github.com/melodic-software/claude-code-plugins/issues/4142).
A future skill is measured against this charter, not against whether it feels
adjacent.

## What the plugin is

**A repository's tracked markdown, kept honest.** Five concerns, each with a
stated moment:

| Concern | Moment | Skills |
|---|---|---|
| Authoring | while the text is being written | `write-for-agents`, `write-for-humans` |
| In-page quality | after it exists, inside one file | `compress`, `audit-noise` |
| Whole-document worth | after it exists, about the file itself | `audit-derivability`, `audit-progressive-disclosure` |
| Cross-file structure | about the relationships between files | `extract-ssot`, `rename-references`, `audit-encapsulation`, the file-name set |
| Enforcement | so the above does not decay | `generate-file-name-gate` |

The file-name set is `setup`, `audit-file-names`, `realign-file-names`, and
`generate-file-name-gate`. `audit-encapsulation` belongs on the cross-file
axis: it is about citations between files, specifically citations into
skill-private surfaces. It has a README skills-table row.

The axis that makes this one plugin rather than four is the **artifact**:
tracked markdown a repository maintains.

## What it is not

1. **Not a prose-style engine.** `write-for-humans` resolves the consuming
   project's own style guide first and falls back to a named public set. It
   must never accumulate house rules.
2. **Not a linter.** Structural markdown lint belongs to `markdownlint-cli2`.
   Every skill here makes a judgment a linter cannot. `compress` is the only
   skill that gates its entry point on that binary; `extract-ssot` names it as
   one option for a ship-gate lint step. The README Requirements section
   states that split.
3. **Not a code-comment tool.** `code-tidying:audit-comment-residue` owns
   non-markdown files, even where the residue shapes are identical.
4. **Not a commit or PR authoring tool.** `source-control` owns commit-message
   shape and the marketplace owns PR-body sections.
5. **Not an auto-applier.** Every skill here that changes a file does it
   behind a human gate, per file. The file-name findings artifact does not
   declare `type: review-findings`, because that type is auto-applicable by
   construction.

## Listing budget and the file-name set

**Decision.** Accept the five-concern charter and the five boundaries.
Do not split the file-name set into a `docs-naming` plugin in this change.
Hold the line on adding a listed skill until a separately briefed extraction
exists. Do not grow by name-only listing: discovery that depends on a
`## Next` chain is how a skill becomes unloadable.

- **Claim:** the five-concern charter and five boundaries above are the
  plugin's contract; a `docs-naming` extraction is not this issue's work.
- **Basis:** #4142's own proposal (five concerns, five boundaries, three ways
  out of the listing-budget squeeze). After #4661,
  `check-listing-budget.sh plugins/docs-hygiene/skills` reads 5,234 / 8,000, so
  the 2026-09 squeeze that motivated an immediate split is no longer the
  design authority.
- **As of:** 2026-09-28.
- **Recheck:** a listed-skill addition that would push this plugin's
  listing-budget estimate back over 7,500, or a briefed `docs-naming`
  extraction PR.
