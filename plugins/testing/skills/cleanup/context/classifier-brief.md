# Classifier brief

The brief [`../SKILL.md`](../SKILL.md) step 4 writes to `<work>/classifier-brief.md` and hands to a
fresh-context subagent. Copy the template below and fill the candidate list. Hand over the test
files, the production files they import, and the findings; never the reasoning that picked them.

## Template

```markdown
# Classify these test candidates

You are classifying tests for a cleanup batch over `<folder>`. You write nothing: return one row per
candidate in the table shape at the end. You are done when every candidate below has a row. When
the files you were given are not enough to decide a candidate, return it as row 6 (keep) with the
evidence that is missing, rather than guess.

Read section 1 of `<plugin-root>/skills/test-value/SKILL.md`, "Every expected value names its
independent source". A rewrite takes its expected value from a source that section names.

## Inputs per candidate

- F: the user named it flaky.
- CF: it cannot fail or checks little: a scanner finding below, or a judge FLAG verdict.
- K: a contract exists: callers, users or an external system depend on the behavior. Cite it as
  `file:line`.
- B: brittle: it asserts internals and would fail on a behavior-preserving refactor.
- D: a behavior-level duplicate of a kept test on the same inputs. Cite both tests.

## Rule: the first matching row wins

| # | Condition | Action |
|---|---|---|
| 1 | F | quarantine (the skill applies it; return the row only) |
| 2 | CF and K | rewrite: same behavior, expected value from the contract |
| 3 | B and K | rewrite to assert the observable outcome through the public API |
| 4 | CF or B, and a positive no-contract statement | delete; if real logic lives in a collaborator, name the test to add there |
| 5 | D, both tests cited | merge (parameterize) or delete the duplicate |
| 6 | none | keep |

- Row 4 needs a positive statement, not a missing citation: the subject is trivial (a constant, a
  getter, pass-through glue) or unreachable from any public path, stated with its evidence. A
  contract reached through reflection, dependency injection, an HTTP route or another repository
  does not show up in a search, so "no citation found" leads to row 2, 3 or 6, never to row 4.
- An advisory scanner finding (one marked report-only) reaches any row only after you quote the
  defect from the test text.
- Mutation results never license a deletion or a merge.
- A judge FLAG carries a proposed diff. It is a candidate rewrite only: use it when you pick row 2
  or 3 and it fits, otherwise write your own.
- A file whose adapter is `block_model: file` (`<list>`) is one whole-file test to the scanner:
  rows 4 and 5 do not apply; rewrite individual checks or keep.
- Row 5 merges only tests at the same level: never an integration or end-to-end test with a unit
  test.
- A snapshot-only finding is row 2: an explicit assertion where requirements give the value,
  otherwise a smaller snapshot.

## Candidates

<one block per candidate: test name and file:line, the finding rows or FLAG verdict that made it a
candidate, F when named flaky>

## Return

| Test | Row | Evidence (quoted line) | K citation or no-contract statement | Action | Diff |
|---|---|---|---|---|---|
```

## Reading the answer

Write the subagent's table to `<work>/classifier-answer.md` unchanged. A row without a quoted line,
a row 2 or 3 without a `file:line` K citation, or a row 4 without a positive no-contract statement
is treated as row 6 (keep), and the decision table says why.
