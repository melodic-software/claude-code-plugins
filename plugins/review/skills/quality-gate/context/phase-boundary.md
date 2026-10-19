# Phase-boundary inputs

An orchestrator reviews one plan phase from its own checkout, against a worker's separate worktree,
often before any pull request exists. These four inputs let it say exactly what to review, so the
gate never guesses the change set from the invoking checkout or the forge. Every mode accepts them;
the table says which modes read each one.

| Input | Meaning | Modes that read it | Effect |
|---|---|---|---|
| `--worktree <path>` | The checkout holding the change, separate from the invoking session's | all but `pr` and `close-out` | Every git command runs as `git -C <path> ...` and every file read resolves under `<path>`, starting with the repository-context gather (`git -C <path> branch --show-current`, `git -C <path> status --porcelain \| head -20`). The invoking checkout is never read as the change. A path where `git -C <path> rev-parse --show-toplevel` fails is a STOP. |
| `--base <sha>` | The previous phase-boundary commit | `self`, `code`, `code-design`, `architecture`, `security`, `spec`, `downstream`, `slice`, `restatement`, `criteria` | The review diff base is `<sha>`. No pull-request lookup, fetch or remote read runs. The change set is `git -C <path> diff <sha>` (commits since the boundary plus uncommitted edits) and `git -C <path> ls-files --others --exclude-standard`. Without `--worktree`, the same commands run in the current checkout. |
| `--quality-bar <prototype\|internal\|production>` | The `Quality bar:` line from the plan or Brief | every mode that dispatches a reviewer: `self`, `code`, `code-design`, `architecture`, `security`, `spec`, `downstream`, `slice`, `restatement`, `criteria` given `--base` or `--worktree`, and, given neither, `pr` and `close-out`; `criteria` without either reviews inline and ignores it | Passed to each dispatched reviewer as the line `Quality bar: <value>`. Absent means `production`, and the report names that assumption. Tier tests stay those of the severity vocabulary in SKILL.md "Shared inputs". With `--base` or `--worktree`, `pr` and `close-out` STOP (Mode notes). |
| `--report-only` | The caller persists and acts on the result | every mode | The gate writes nothing and asks nothing: no findings artifact, no `downstream` probe (it runs as `report`), no Step 4 handoff. A point that would ask the user (an ambiguous mode, the `spec` rung-4 ask) is a STOP naming what is missing, with one exception: the standards [Resolution ladder](../../../reference/standards-contract.md) skips its offer and ask rungs and takes its non-interactive rung, and the report names that assumption. The Step 3 report is the result. |

## Pre-flight with a base SHA

Step 0.5 runs against the base SHA in place of the "Shared inputs" ladder:

- `git -C <path> rev-parse --verify <sha>^{commit}` must resolve and
  `git -C <path> merge-base --is-ancestor <sha> HEAD` must succeed; otherwise STOP and name the SHA.
  A base outside the branch's history reviews the wrong diff.
- An empty `git -C <path> diff <sha>` with no untracked files is "Nothing to review": STOP.

## Mode notes

- With `--base`, Step 0 mode inference never checks whether a pull request exists for the branch.
- `pr` and `close-out` take their change set from a pull request or a spec container, which only the
  forge or tracker holds. Given `--base` or `--worktree`, they STOP and name `code` as the mode that
  reviews a local diff.
- `criteria` with `--base` or `--worktree` resolves standards from the change's checkout and applies
  no criteria inline: it dispatches a fresh-context `review:brief-reviewer` with the resolved
  criteria, briefed as below.
- `code` with `--base` or `--worktree` skips the `pr-review-toolkit` primary path and dispatches the
  `code-reviewer` fallback, briefed as below.
- `code` with `--worktree` skips the size-crossing step, which measures the invoking checkout; the
  report says size crossings were not measured. Without `--worktree`, under `--report-only` that
  step writes no path file: the loop reads `git diff --name-only -z <base>` with `read -r -d ''`,
  where `<base>` is the `--base` SHA when given, else the review diff base ("Shared inputs"), and
  the crossings go in the gate's report.
- `code-design` resolves consumer criteria from the change's checkout and always dispatches
  `review:brief-reviewer`, briefed as below.
- `restatement` with `--base` or `--worktree` reviews no file inline: it dispatches a fresh-context
  `review:brief-reviewer` for every batch, briefed as below.
- `downstream` with `--base` skips the `downstream_probe` layer read from the default branch, which
  needs `git ls-remote` and `git fetch`. The floor is `report`, so no probe runs, and the report
  says the committed setting was not read.
- `spec` with `--base` resolves its spec only from rung 1 as a local `--spec <path>` under the
  worktree. Rung 2 reads commit refs through the tracker and the pull-request body through the
  forge, so it does not run; without a local path the mode STOPs.

## The reviewer's brief

Dispatch each mode's own reviewer in fresh context, as its context file names, with:

- the change set commands above, with the worktree path and base SHA substituted. These replace
  the reviewer's own change-set step: `review:code-reviewer`, `review:security-reviewer` and
  `review:architecture-guardian` run only the commands their brief supplies, with no forge lookup
  or fetch;
- the worktree's absolute path as the target of every command and tool call in the review, for
  every dispatched reviewer including `review:brief-reviewer`: git runs as `git -C <worktree>`
  (its own `git log -S` or `git grep` included), every Read, Grep and Glob and every listed
  untracked path resolves under it, and any other command, such as a dependency audit, runs with
  the worktree as its directory or path argument, never the invoking checkout;
- the concern tag: the mode, or `slice <name>`;
- the `Quality bar:` line;
- the inputs the mode's own brief requires: the slice criteria file path in `slice`, the size
  crossings in `code`, the finding-class table and the spec text read from the local
  `--spec <path>` in `spec`, the resolved criteria (file paths and sections) in `criteria`, the
  consumer criteria paths and the bundled criteria path in `code-design`, and
  the paved-path file from [criteria.md](criteria.md) step 2;
- this rule, verbatim: "Rate a finding only when the phase diff causes it: a line the diff adds or
  changes, or something the diff leaves out that the change requires. The file it names may be
  outside the diff, such as a caller the change breaks or a canonical home the added text
  duplicates. A problem the diff did not cause goes in a separate `Outside this phase` list, one
  line per item naming the file, with no severity and no effect on the verdict, or is left out."
  The gate's report keeps that list unrated, so debt the phase did not add never blocks it, while
  `downstream`, `restatement` and `spec` still rate what the change breaks, duplicates or misses.

Never give it the plan's rationale, the conversation or the implementer's account of the change,
just as the [per-slice.md](per-slice.md) prompt template carries none of them: the reviewer judges
the diff, not the story behind it. In `self`
mode this replaces gathering the plan in the orchestrator sequence's first step.
