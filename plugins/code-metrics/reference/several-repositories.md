# Running an audit over several repositories

`/code-metrics:audit`, `audit-coverage`, `audit-duplication` and `audit-suppressions` take the
target forms of [`target-scope.md`](target-scope.md) (`--repo`, `--repos-from`, `--owner`,
`--fleet`, `--skip`, or the same request in words). That file owns the forms, "Resolving
repositories", "Fan-out", "Merging findings" and "Writes stay per repository". This file states
only what differs for these four skills.

With no target form, nothing here applies: each skill runs exactly as its own body says.

## One repository's pass

- **Where the script runs.** Each audit script takes its root, its configuration
  (`docs/conventions/code-metrics.yaml`) and its state key from the working directory. The
  repository's subagent starts the script from `<root>` (`cd <root> && <script> <args>` in one
  Bash call), so the report's root, the configuration layers and the kept reports all belong to
  that repository. The skills pre-approve only their scripts, so the `cd` and the git calls below
  may ask for permission.
- **Which tree it reads.** The scripts read the working tree. A repository that is not the
  session's own checkout is measured only when, after the one `git -C <root> fetch origin`, its
  checkout is clean (`git -C <root> status --porcelain` prints nothing) and `HEAD` is the commit
  its default branch names on the remote: `origin/HEAD`, else `origin/main`, else `origin/master`,
  the order the scripts use. That tree is then the one the contract reads. Any other checkout, or a
  clone with none of those refs, is reported as skipped with the reason and is not measured.
- **Scope.** The scope arguments are `--all`, a path and `--base`. The default change scope
  compares a branch with its default branch, which a checkout at that branch has nothing to compare.
  So in a run over several repositories, no scope argument means `--all` in each repository other
  than the session's own, and the report says so. A `--base` keeps change mode in every repository.
- **Paths stay relative.** A path given with a target form (a scope path, `--artifacts`,
  `--registry`, `--memory-dir`) must be relative, and is read from each root; refuse an absolute
  one before the fan-out, since it would point every repository at one file or one directory. A
  repository that lacks a named path, or a registry its resolved configuration names (an old
  user-global file, still read, applies to every repository), reports the usage error as that repository's
  failure, and the others still run.
- **Every other argument** (`--json`, `--keep`, `--findings`) passes to each repository's run
  unchanged.

## Reports and state

- **One document per repository.** A `--json` run keeps each repository's document as its own
  file or fenced block, labeled with its `owner/name`, never run together on one stream, and adds
  no field to either schema. A `code-metrics/v2` document carries its own `root.path`; a
  `code-metrics/suppressions/v1` document has no root field, so its label is what ties it to its
  repository. Basis: every path in a `code-metrics/v2` document is relative to its `root.path`
  (`report-schema.md`, "Path relativity"), the clone trend compares a document with an earlier one
  of the same project, and `/verification:measure metrics` compares two documents. A merged
  document would need a second root and would break all three.
- **The markdown report** gives each repository its own section, headed by its `owner/name`, as
  the script printed it. A closing table merges the rows "Merging findings" asks for, each action
  in its own script's row order: rows over a reference first, then by the measured value with the
  worse end first (largest for size, complexity, CRAP and duplicated lines; smallest for coverage
  and typed percentage), suppressions with correctness rules first. A number beside a reference
  keeps the reference that repository's configuration resolved.
- **State stays in each repository.** Kept reports (the duplication trend baseline) are keyed by
  each repository's own state key, so one repository's trend never compares against another's.
- **The one write is `--findings`.** The audits edit nothing, so no worktree or pull request
  follows. A `--findings` run writes one findings file into each repository's own memory root
  (`<root>/.work` unless `--memory-dir` names another), for that repository's branch, as "Writes
  stay per repository" puts per-repository state. A checkout with no current branch, such as one
  detached at the default branch, fails `--findings` before the scan; report it as that
  repository's failure.

## Cross-repository copies

`audit-duplication` compares files within one repository. A file copied between repositories
is the contract's "Cross-repository signals", measured by `/coupling:reduce` when the `coupling`
plugin is enabled; run that skill for it. Without it, say the run did not look for copies between
repositories.
