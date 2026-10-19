# Phase-boundary inputs

An orchestrator reviews one plan phase from its own checkout, against a worker's separate worktree,
often before any pull request exists. These four inputs let it say exactly what to review, so the
gate never guesses the change set from the invoking checkout or the forge. Every mode accepts them;
the table says which modes read each one.

| Input | Meaning | Modes that read it | Effect |
|---|---|---|---|
| `--worktree <path>` | The checkout holding the change, separate from the invoking session's | all but `pr` and `close-out` | Every git command runs as `git -C <path> ...` and every file read resolves under `<path>`, starting with the repository-context gather (`git -C <path> branch --show-current`, `git -C <path> status --porcelain \| head -20`). The invoking checkout is never read as the change. A path where `git -C <path> rev-parse --show-toplevel` fails is a STOP. |
| `--base <sha>` | The previous phase-boundary commit | `self`, `code`, `architecture`, `security`, `spec`, `downstream`, `slice`, `restatement` | The review diff base is `<sha>`. No pull-request lookup, fetch or remote read runs. The change set is `git -C <path> diff <sha>` (commits since the boundary plus uncommitted edits) and `git -C <path> ls-files --others --exclude-standard`. Without `--worktree`, the same commands run in the current checkout. |
| `--quality-bar <prototype\|internal\|production>` | The `Quality bar:` line from the plan or Brief | every mode that dispatches a reviewer | Passed to the reviewer as the line `Quality bar: <value>`. Absent means `production`, and the report names that assumption. Tier tests stay those of the severity vocabulary in SKILL.md "Shared inputs". |
| `--report-only` | The caller persists and acts on the result | every mode | The gate writes nothing and asks nothing: no findings artifact, no `downstream` probe (it runs as `report`), no Step 4 handoff. A point that would ask the user (an ambiguous mode, the `spec` rung-4 ask) is a STOP naming what is missing. The Step 3 report is the result. |

## Pre-flight with a base SHA

Step 0.5 runs against the base SHA in place of the "Shared inputs" ladder:

- `git -C <path> rev-parse --verify <sha>^{commit}` must resolve and
  `git -C <path> merge-base --is-ancestor <sha> HEAD` must succeed; otherwise STOP and name the SHA.
  A base outside the branch's history reviews the wrong diff.
- An empty `git -C <path> diff <sha>` with no untracked files is "Nothing to review": STOP.

## Mode notes

- `pr` and `close-out` take their change set from a pull request or a spec container, which only the
  forge or tracker holds. Given `--base` or `--worktree`, they STOP and name `code` as the mode that
  reviews a local diff.
- `criteria` ignores `--base`; with `--worktree` it resolves standards from that checkout.
- `spec` with `--base` resolves its spec only from rung 1 as a local `--spec <path>` under the
  worktree. Rung 2 reads commit refs through the tracker and the pull-request body through the
  forge, so it does not run; without a local path the mode STOPs.

## The reviewer's brief

Dispatch each mode's own reviewer in fresh context, as its context file names, with only:

- the change set commands above, with the worktree path and base SHA substituted;
- the concern tag: the mode, or `slice <name>`;
- the `Quality bar:` line.

Withhold the plan's rationale, the conversation and the implementer's account of the change, as
[per-slice.md](per-slice.md) does: the reviewer judges the diff, not the story behind it. In `self`
mode this replaces gathering the plan in the orchestrator sequence's first step.
