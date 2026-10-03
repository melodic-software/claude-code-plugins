# go-faster bottleneck catalog

The catalog is a set of pointer records for bottleneck classes, built from a verified research
pass. Each row is re-read live, at its `pointer`, when a finding cites it. A row is never itself
proof: it says where to look and what to measure, and the live source and your own measurement
settle the claim.

## Record schema

Each catalog file holds one markdown table. Its columns, in this order:

- `class`: the bottleneck class, named in a few words.
- `area`: one or more area slugs separated by `, `, or `all` for a measurement-method row that
  applies to every area.
- `cause`: why the class costs time, a clause.
- `measure`: how to observe the cost on this machine, a clause.
- `remedy`: the change that removes or shrinks the cost, a clause.
- `accuracy_guard`: the metric or check that would show accuracy slipping if the remedy is adopted.
- `fix_owner`: a `/plugin:skill` that exists in this repository, or the token `steps-for-you` when
  only the human can apply it.
- `confidence`: `HIGH`, `MEDIUM`, `LOW`, or `judgment`.
- `candidate_only`: `yes` or `no`.
- `pointer`: the primary source URL, re-read when a finding cites the row.
- `as_of`: the date the source was read, `YYYY-MM-DD`.
- `recheck_trigger`: the concrete event that makes the row stale.

Rules that follow from the schema:

- Any confidence other than `HIGH` (`MEDIUM`, `LOW`, `judgment`) means `candidate_only` is `yes`.
  Such a row may seed only a candidate finding, never a measured finding and never a `now` finding.
- A flag-only remedy is never adoptable. Loosening a guard, Defender exclusions, a Dev Drive, and
  lowering model, effort or verification are all flag-only: the finding reports them and stops.
- A remedy that drops or weakens a check names `/overengineering:audit` as `fix_owner`.
- No prices, rates or vendor percentages appear in any row; token and cache use appear as counts.

## File to area map

- `harness.md`: hooks, instructions, model-cache, permissions, plugins-startup, skills.
- `agentic-workflow.md`: how-you-work, instructions, orchestration, session-work, skills.
- `ci-cd.md`: ci-cd, gates, tests.
- `review-and-tests.md`: gates, pr-review, tests.
- `git.md`: git.
- `windows-machine.md`: bash-windows, machine.
- `measurement.md`: `all`, ci-cd, model-cache, pr-review, tests.

## How it is checked

`python plugins/performance/scripts/findings.py lint-catalog <this folder>` reads every `*.md` file
in the folder. It parses only a table whose header row is the twelve columns above, exactly and in
order; any other table is skipped, not reported, and a non-table line ends a table. Separator rows
are skipped. On each parsed row it checks:

- the cell count matches the header;
- `class`, `area` and `recheck_trigger` are not empty;
- the `area` cell holds only known slugs or `all`;
- `confidence` is one of `HIGH`, `MEDIUM`, `LOW`, `judgment`;
- `candidate_only` is `yes` or `no`, and `yes` on every row that is not `HIGH`;
- `pointer` starts with `http`;
- `as_of` is a `YYYY-MM-DD` date.

A run that finds no catalog rows at all fails. This file holds no catalog table, so it adds no rows.
