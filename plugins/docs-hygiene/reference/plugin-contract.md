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
| Cross-file structure | about the relationships between files | `extract-ssot`, `rename-references`, `audit-encapsulation` |
| Enforcement | so the above does not decay | none |

`audit-encapsulation` belongs on the cross-file
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
   batch.

## Listing budget

**Decision.** Accept the five-concern charter and the five boundaries. The
only listing-budget rule is the 8,000 default in
`plugins/skill-quality/scripts/check-listing-budget.sh`. Do not grow by
name-only listing: discovery that depends on a `## Next` chain is how a skill
becomes unloadable.

The four file-name skills (`setup`, `audit-file-names`, `realign-file-names`,
`generate-file-name-gate`) live in the `docs-naming` plugin, tracked in
[#5348](https://github.com/melodic-software/claude-code-plugins/issues/5348),
so the Enforcement concern has no skill here. This plugin keeps a check-only
`setup` for its `markdownlint-cli2` prerequisite. The shared audit router is
not built: the sibling pointers in each audit description and the `repo-sweep`
catalog route between the audits.

- **Claim:** the five-concern charter and five boundaries above are the
  plugin's contract, and the listing budget is governed only by
  `check-listing-budget.sh` at 8,000.
- **Basis:** the owner decisions on
  [#4142](https://github.com/melodic-software/claude-code-plugins/issues/4142)
  (2026-09-29) and
  [#5348](https://github.com/melodic-software/claude-code-plugins/issues/5348)
  (2026-10-01); `check-listing-budget.sh plugins/docs-hygiene/skills` reads
  4,291 / 8,000 over 9 listed skills, and `plugins/docs-naming/skills` reads
  955 / 8,000 over 2.
- **As of:** 2026-10-01.
- **Recheck:** a listed-skill addition that makes `check-listing-budget.sh`
  report over budget at 8,000 (`WARN`; the script exits 0).
