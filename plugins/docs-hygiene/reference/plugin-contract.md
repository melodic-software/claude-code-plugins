# docs-hygiene plugin contract

Status: ratified by the owner on
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
   only when the user opts in, behind a confirmation per invocation or per
   batch. File-name renames are gated per file: `realign-file-names` accepts
   one file at a time. The file-name findings artifact does not declare
   `type: review-findings`, because that type is auto-applicable by
   construction.

## Listing budget and the file-name set

**Decision.** Accept the five-concern charter and the five boundaries. The
only listing-budget rule is the 8,000 default in
`plugins/skill-quality/scripts/check-listing-budget.sh`. Do not grow by
name-only listing: discovery that depends on a `## Next` chain is how a skill
becomes unloadable.

The four file-name skills (`setup`, `audit-file-names`, `realign-file-names`,
`generate-file-name-gate`) move to a `docs-naming` plugin, tracked in
[#5348](https://github.com/melodic-software/claude-code-plugins/issues/5348).
The extraction is not part of this change; the shared audit router is decided
with the split.

- **Claim:** the five-concern charter and five boundaries above are the
  plugin's contract, and the listing budget is governed only by
  `check-listing-budget.sh` at 8,000.
- **Basis:** the owner decision comment on
  [#4142](https://github.com/melodic-software/claude-code-plugins/issues/4142)
  (2026-09-29); `check-listing-budget.sh plugins/docs-hygiene/skills` reads
  5,234 / 8,000.
- **As of:** 2026-09-29.
- **Recheck:** a listed-skill addition that makes `check-listing-budget.sh`
  report over budget at 8,000 (`WARN`; the script exits 0), or the `docs-naming`
  extraction PR landing.
