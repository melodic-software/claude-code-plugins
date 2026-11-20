# Over several repositories

A `--full` run given a target form. The target-scope contract,
[`reference/target-scope.md`](../../../reference/target-scope.md) in this plugin's root, two
directories above this skill's base directory, owns the target forms and how repositories resolve,
fan out and merge ("Target forms", "Resolving repositories", "Fan-out", "Merging findings", "Writes
stay per repository"); this file states only what differs for the mutation audit. Each repository
runs this skill's single-repository procedure, Phases 0 to 6, with the changes below. With no
target form, none of this applies.

A target form needs `--full`. A scope path, `--exercised`, `--paths`, `--phase`,
`--record-mutants` and `--replay-mutants` each read one checkout's change, so they stay
single-repository and refuse a target form, naming the conflict. `--max`, `--no-suppress` and
`--persist-findings` combine with one.

Running Phases 2 and 3 in a subagent per repository is the contract's fan-out, not a delegated
judgment: each subagent runs the same deterministic gate Phase 3 describes, and its tests' pass or
fail is still the verdict.

## Where each repository's mutants run

An in-tree regime writes mutants into the files it tests, so no repository is mutated in its main
checkout, whether or not it is the session's own. Each repository's subagent creates a throwaway
worktree: `git -C <root> fetch origin`, then `git -C <root> worktree add --detach <dir>
origin/HEAD`, where `<dir>` is a fresh directory from `mktemp -d`, outside every repository tree.
It installs what the tests need there the way that repository documents it, and runs every phase
against that worktree with `git -C <dir>`. The main checkout's working tree is not mutated, and a
dirty or behind checkout is not a stop. Its one write is a findings file in its memory root under
`--persist-findings` (below). A clone with no `origin/HEAD` is reported skipped with the reason.

The Phase 0 snapshot and every restoration check compare that worktree with itself. The worktree
stays until that repository's Phase 4 returns, so triage can run an equivalence demonstration in
it. Then it is removed with `git -C <root> worktree remove --force <dir>`, confirmed gone with
`git -C <root> worktree list`; `--force` because installed dependencies and tool reports are
untracked files. A repository that fails in Phase 0 or 1, or whose run the user declines, has its
worktree removed the same way. On a failed restoration the worktree stays and its path is named in
that repository's failure, so the evidence survives; nothing from that repository reaches Phase 4.

## Config, baseline and caps per repository

- **Config** resolves from that repository's layers, per [`config-fallback.md`](config-fallback.md):
  its team file at `origin/HEAD`, its personal `.local.md` file read from the main checkout when
  present (that file is untracked, so the worktree lacks it), and this plugin's `userConfig` as
  the user layer everywhere. A repository with no test command fails there, with Phase 0's
  remediation; the command is never guessed from another repository.
- **Questions.** A subagent cannot ask the user, so each point where Phase 0 would ask (no test
  command, a tool with no shipped adapter, a tool not installed, an unresolved `diff-target`)
  makes that repository a failure naming the question and its remediation, as an unattended run
  does. The other repositories carry on.
- **Baseline.** A red baseline, or one that cannot run because the worktree lacks what the tests
  need, is that repository's failure.
- **Caps.** `--max`, the configured `max-mutants` and the effort cap each bound one repository's
  mutants, never the set's total.
- **Suppression** reads that repository's own record at `origin/HEAD`. An entry never suppresses a
  mutant in another repository.
- **Verification level** for each repository's triage comes from that repository's
  `docs/conventions/mutation-testing.yaml` at its default branch on `origin`. Run Phase 4's
  `read-verification.sh` command with `CLAUDE_PROJECT_DIR=<root>` before `bash`, `<root>` being
  that repository's main checkout, and the same `--file docs/conventions/mutation-testing.yaml`.
  The `--file` path stays relative to the repository root: the script refuses an absolute path
  and falls back to `light`. Without `CLAUDE_PROJECT_DIR`, the script reads the invoking session's
  repository, not the target's.

## Estimate and confirmation

`--full` confirms before any mutant runs. Each repository's subagent runs Phases 0 and 1 and
returns its scope report with the estimate line Phase 1 step 5 prints, then stops, leaving its
worktree in place. Print every repository's line as its script printed it, with no combined
total: `--seconds` times one repository's mutant, so no sum across repositories is a figure the
script prints. Under each line, print what that repository will run on this machine: its origin
`owner/name`, the commit its worktree holds (`git -C <dir> rev-parse HEAD`, fetched from upstream
and not yet reviewed by anyone in this session), and the install and test commands it resolved.
Mark each repository whose origin owner is not the user's own as `third-party`, so a clone of
someone else's project is never run on the estimate alone. Confirm once for the set; the user can
decline any repository by name, and the rest go ahead. After confirmation, a fresh subagent per
repository resumes from Phase 2 in that same worktree. The subagent that ran Phases 0 and 1
returns everything Phase 2 onward reads, and the resuming one is handed all of it: the worktree
path, the resolved config and its `Config:` line, the Phase 0 snapshot and baseline result, the
resolved regime, the cached test selection, the Phase 1 mutant set after the coverage drop and
suppression, and the suppression dispositions Phase 5 reports.

## Triage stays fresh

A repository's subagent runs Phases 2 and 3 and returns its survivors with each mutated line, its
surrounding code and the tests that covered it. Phase 4 then runs from this session, one
fresh-context triage subagent per repository, briefed as Phase 4 says and given that repository's
worktree path; the lint over each arid proposal runs here too. The context that ran a repository's
mutants never grades them.

## Merged report

- Each repository keeps its own scope line, regime, `Config:` line and headline scores (the
  covered-code score and the plain mutation score), headed by its `owner/name`. A score is never
  summed or averaged across repositories, since their suites differ.
- The per-file rows from every repository rank on one scale, oracle gap ascending, each row
  carrying its `owner/name` beside its path. Rows never collapse across repositories: a survivor
  describes one suite's tests. The contract's cross-repository signals are not this audit's; it
  reports none.
- Each repository that failed or was skipped is listed with the reason: not cloned, no
  `origin/HEAD`, an unanswered Phase 0 question, red baseline, declined, or a failed restoration
  with its worktree path.

## Findings files per repository

Under `--persist-findings`, each repository's survivors go to a findings file in that repository's
own memory root, `<root>/<memory_dir>`, per [`persist-findings.md`](persist-findings.md) applied
to that repository: its `<memory_dir>`, its self-ignore guard, and the branch `origin/HEAD` names
as both the directory's branch slug and the file's `branch:` value, since the throwaway worktree
has no branch for `git branch --show-current` to print. The destination proof runs against the
checkout that governs that root, never the invoking one. A repository whose destination cannot be
proven outside tracked space gets no file, and the report says so for that repository.
