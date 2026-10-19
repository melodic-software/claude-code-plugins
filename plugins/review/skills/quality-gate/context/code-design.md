# Code-design review mode

Reviews a change for design that makes the next change costly: one fact or rule copied into
several places, one kind of change spread across many files, and abstraction with no second use.
The consumer's criteria govern; the bundled criteria below fill in only where the consumer has
none. A fresh-context `review:brief-reviewer` runs the review, never the invoking thread.

## Resolve the criteria

In this order; the first source that covers a concern governs it:

1. **Consumer criteria.** Resolve the project's standards through the
   [Resolution ladder](../../../reference/standards-contract.md) as [criteria.md](criteria.md)
   step 1 does, and keep the matched files that cover design, architecture, duplication or review
   of the changed surfaces. The severity vocabulary is the one SKILL.md "Shared inputs" names.
2. **Bundled criteria.** The table below, for each concern no consumer file covers.

When a matched consumer file contradicts a bundled row (it permits what the row flags, or rates it
differently), the consumer's rule applies, and the report carries one line per row it overrode,
with the row's Principle and the consumer file's repo-relative path:

```text
Overrides bundled default <principle> per <standards file>
```

## Quality bar

Take it from `--quality-bar`, else from a `Quality bar: prototype | internal | production` line in
the request. With neither, rate as `production` and put
`Quality bar: production (assumed: none given)` in the report.

## Bundled criteria

Principles are code smells from Fowler, *Refactoring* (2nd ed.), chapter 3, "Bad Smells in Code".
Markdown means Markdown prose files; code is every other changed file.

| Criterion | Principle | Flag | Code, `internal` or `production` | Markdown | Any surface, `prototype` |
|---|---|---|---|---|---|
| Introduced repetition | Duplicated Code | The diff adds a copy of a fact (a constant, list, schema or rule) or of logic that already exists in the diff or the codebase | CRITICAL when the cascade rule holds, else SUGGESTION | SUGGESTION | SUGGESTION |
| Change cascade | Shotgun Surgery | One kind of change already needs coordinated edits across several files, and the diff adds to that set | SUGGESTION | SUGGESTION | SUGGESTION |
| Unearned abstraction | Speculative Generality | An interface, parameter, hook or layer with one user and no second variant the change names | SUGGESTION | SUGGESTION | SUGGESTION |

### The cascade rule

A repetition finding is CRITICAL only when all of these hold; there is no file-count threshold:

- the diff introduces the copy (a copy that predates the base is at most SUGGESTION);
- the finding names the repeated fact or logic, the file and line of every copy, and a later,
  otherwise-correct change to one copy that leaves the others wrong (the CRITICAL test in the
  severity vocabulary);
- no shared source (one definition the copies import or generate from) and no sync check (a test,
  lint or CI step that fails when the copies disagree) keeps them aligned;
- the copies are code, the quality bar is not `prototype`, and no exemption below applies.

### Exempt from CRITICAL

These are judgment, not a review guide's rule. Each is SUGGESTION at most:

- a passage inside `contract-restatement` markers, which a check holds to its source;
- an entry in a registry the repository declares, a file that exists to list every member of a set;
- generated files;
- test fixtures and sample data;
- a rename or move, where the text at the new path is the old text rather than a second copy.

## Dispatch

Dispatch `review:brief-reviewer`, never a general-purpose agent. With phase-boundary inputs the
brief carries what [phase-boundary.md](phase-boundary.md) "The reviewer's brief" lists; otherwise
the change set is `git diff <review diff base>` plus `git ls-files --others --exclude-standard`
(SKILL.md "Shared inputs"). Substitute `<plugin-root>` (SKILL.md "Spoke paths"). The brief carries
no plan rationale and no account of the change:

```text
You are reviewing a change for code design. Concern: code-design.
<the Quality bar: line>

Read in order:
1. Severity vocabulary: <consumer file, or <plugin-root>/context/severity.md>.
2. Consumer criteria: <matched standards files, or "none">.
3. Bundled criteria: <plugin-root>/skills/quality-gate/context/code-design.md, sections
   "Bundled criteria", "The cascade rule" and "Exempt from CRITICAL".
4. The change set: <change-set commands>. Read every untracked file it lists.

Consumer criteria and severity win over the bundled ones. For each bundled row a consumer file
contradicts, apply the consumer's rule and write
"Overrides bundled default <principle> per <standards file>".
For each repetition finding, name the repeated fact or logic, the file:line of every copy, the
later change that would make the copies diverge, and whether a shared source or sync check exists.
Report every finding the criteria reach, uncertain or low-severity ones included; confidence is
high, medium or low.

| # | Severity | Confidence | Principle | Finding | File:Line | Action |
|---|----------|------------|-----------|---------|-----------|--------|
```

## Report

Verify each returned finding against the diff (SKILL.md Step 2) and check its severity against the
cascade rule, then report per SKILL.md Step 3, with the quality-bar line, the criteria source
(consumer files, or `bundled`) and every override line above the findings table. Unless
`--report-only`, write the findings artifact to the findings location as
`<UTC-timestamp>-code-design.md`.
