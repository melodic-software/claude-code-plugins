# Target scope: one target by default, several repositories on request

Owner doc for **what an improvement, maintenance or cleanup skill runs over**: one path or
repository by default, or a set of repositories when the user asks for one. One home per the
[convention registry](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/plugin-philosophy.md#convention-registry); an adopting skill cites this doc and
states only what differs for it.

## Boundary

This doc owns the target forms, how repository paths resolve, how a multi-repository run fans out
and merges, the signals only a multi-repository run has, and the rule that writes stay per
repository. It does not own:

- **What a skill hunts, how it ranks, or what one repository's pass does.** Each adopter's own body
  decides that; a multi-repository run repeats it per repository.
- **Repository hygiene across a machine** (merged branches, worktrees, sync), which
  `/repo-fleet-hygiene:audit` owns with its own scope ladder.
- **How big a pull request may be**, which the
  [PR scope budget](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/contracts/pr-scope-budget/README.md) owns, per repository.

## Target forms

The default is unchanged: a bare run, or a run given one path, resolves its target the way the
skill always has. A run covers several repositories only when its arguments or the user's request
name them. The flags reuse `/repo-hygiene:clean`'s repository selection (its SKILL.md §8,
"Repo sources"), so the same words select the same set everywhere.

| Form | Selects |
|---|---|
| *(none)* or `<path>` | The skill's own single target: the path, else its default rung |
| `--repo <path or owner/name>` | That repository; repeatable |
| `--repos-from <file or ->` | One path or `owner/name` per line, such as `ghq list -p` output |
| `--owner <owner>` | Every local clone whose origin is `<owner>/*` |
| `--fleet` | Every local clone (`ghq list -p`) plus the dotfiles source (`chezmoi source-path`) |
| `--skip <entry>` | Drops a repository from any form above; repeatable |

A request in words ("across all our repos", "in api and web") maps to the same forms; say which
form it became before the run starts.

## Resolving repositories

- **`owner/name` to a path**: `<ghq root>/github.com/<owner>/<name>`, the root from
  `git config --path --get ghq.root`. A repository kept elsewhere, such as dotfiles under
  `chezmoi source-path`, is found by its origin URL.
- **Identity**: a repository is its origin `owner/name`. Two clones of one origin count once; keep
  the first that is not skipped, as `--fleet` does in `/repo-hygiene:clean`.
- **Missing clone**: report it as `not cloned` and leave it out. Never clone during a run.
- **Read state**: read each repository at `origin/HEAD` after one `git -C <root> fetch origin`, not
  its working tree, unless the repository is the session's own checkout and the skill reads the
  working tree there. Another session's main checkout can be dirty or behind.
- **Count first**: state the number of repositories, and list them, before any fan-out.

## Fan-out

One subagent per repository, each running the skill's single-repository procedure with its root
anchored: `git -C <root>` for every git call and file reads under `<root>`, so no evidence comes
from the invoking repository. Each subagent reads that repository's `AGENTS.md` at `origin/HEAD`
and follows its conventions. Dispatch follows the repository's
[delegation mechanics](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/plugin-philosophy.md#delegation-mechanics), and a stage
running more than one agent follows the
[fan-out guard](https://github.com/melodic-software/claude-code-plugins/blob/main/plugins/multi-agent/reference/config.md#the-fan-out-guard). With more
repositories than the session's concurrency, run in waves. A skill whose single pass already fans
out per area keeps that inside each repository's subagent.

## Merging findings

- Every finding carries its repository (`owner/name`) beside its path.
- Rank all findings on one scale, the skill's own; a repository never ranks higher for being
  listed first.
- The same finding in several repositories is one row listing each repository, because one fix in
  an owner may close all of them.
- Report the repositories that failed or were skipped, with the reason, so a short list is never
  read as a clean one.

## Cross-repository signals

These exist only when two or more repositories are in scope:

- **Exact copies**: one file blob tracked in two or more repositories.
- **Diverged copies**: one file name in two or more repositories with differing content, ranked by
  how similar the variants are. A near-identical pair is a copy that drifted.
- **Cross-repository coupling**: one repository naming another's internal paths, branch names or
  unversioned files instead of a released contract.

A copy that a mechanism already owns is not a finding: a sync manifest's destinations, a vendoring
registry's copies, and files whose header says they are generated. Read each in-scope repository
for such a mechanism and exclude what it declares. A managed copy that differs from its source is
still a finding, owned by that mechanism. `/coupling:reduce` ships the measurement as
`scripts/cross-repo-dups.py`; another adopter that needs these signals runs that skill, never a
copy of the script.

## Writes stay per repository

Read-only runs write nothing to any repository. A run that changes files works one repository at a
time, by that repository's rules:

- one worktree per repository, created by that repository's convention; never the main checkout;
- one pull request per repository, sized by the PR scope budget;
- per-repository state (ledgers, cursors, findings files) stays in that repository's working-docs
  root, never in the invoking one.

A cross-repository finding is fixed in the repository that owns the source. The copies then point
at it, in their own pull requests.

## Adopters

| Skill | Status |
|---|---|
| `/architecture:improve` (deepening and conventions lenses) | Through `improvement-steps.md` "Scope and fan-out" and its plugin-shipped copy |
| `/coupling:reduce` | Points here through its plugin-shipped copy; measures cross-repository copies |
| `/code-metrics:audit`, `audit-coverage`, `audit-duplication`, `audit-suppressions` | Through `reference/several-repositories.md` and the plugin-shipped copy; one report per repository, and only `--findings` writes |

## Plugin-shipped copies

An installed plugin cannot read this repository's `docs/`, so an adopting plugin carries a
byte-identical copy at `plugins/<plugin>/reference/target-scope.md`, generated by
`scripts/sync-shared-copies.sh` from this file and registered in `scripts/shared-copies.txt`.
Edit this file, never a copy, then rerun the script.
