# Official source record

Fetched and re-verified 2026-07-16. These sources define the runtime and evidence contracts; the
plugin does not rely on remembered behavior.

## Claude Code

- [Create plugins](https://code.claude.com/docs/en/plugins) — plugin root/layout, namespaced skills,
  local `--plugin-dir` testing, and reusable plugin boundary.
- [Plugins reference](https://code.claude.com/docs/en/plugins-reference) — manifest fields,
  `${CLAUDE_PLUGIN_ROOT}`, and plugin cache isolation.
- [Skills](https://code.claude.com/docs/en/skills) — skill frontmatter, arguments, and `allowed-tools`
  semantics. `allowed-tools` grants permission but does not remove other tools, so the skill also states
  its report-only behavioral boundary explicitly.
- [Plugin marketplaces](https://code.claude.com/docs/en/plugin-marketplaces) — local marketplace
  catalog structure and validation.

## Git

- [`git` environment and global options](https://git-scm.com/docs/git) — `GIT_NO_LAZY_FETCH=1`
  prevents on-demand promisor-remote fetches, while `GIT_OPTIONAL_LOCKS=0` prevents optional
  lock-taking side effects such as index refreshes.
- [`git for-each-ref`](https://git-scm.com/docs/git-for-each-ref) — exact ref iteration fields and the
  documented `%00` NUL and `%09` TAB format escapes used for branch/tip records.
- [`git rev-parse`](https://git-scm.com/docs/git-rev-parse) — `--show-toplevel`,
  `--git-common-dir`, `--path-format=absolute`, and repository-layout-safe path resolution.
- [`git remote`](https://git-scm.com/docs/git-remote) — `get-url` expands Git URL rewrite rules and
  returns the configured fetch URL without changing it.
- [`git worktree`](https://git-scm.com/docs/git-worktree) — stable porcelain output, `locked` and
  `prunable` annotations, the linked-worktree `.git` file/common-directory relationship, repair after
  moves, and the instruction to use Git plumbing instead of assuming administrative paths.

## GitHub

- [`gh pr list`](https://cli.github.com/manual/gh_pr_list) — repository/head/state filters and JSON
  fields including `headRefName`, `headRefOid`, `mergedAt`, and `url`.
- [`gh repo view`](https://cli.github.com/manual/gh_repo_view) and
  [`gh api`](https://cli.github.com/manual/gh_api) — repository-qualified JSON/API lookup and
  formatted output.
- [`gh environment`](https://cli.github.com/manual/gh_help_environment) — host, prompt, update-check,
  extension-update-check, and telemetry controls used to keep the audit non-interactive and constrain
  undeclared egress.
- [Get a repository REST endpoint](https://docs.github.com/en/rest/repos/repos#get-a-repository) —
  canonical `full_name`/`default_branch` response and documented 200, 301, 403, and 404 outcomes.
- [Transferring a repository](https://docs.github.com/en/repositories/creating-and-managing-repositories/transferring-a-repository) —
  old repository URLs redirect after transfer, but GitHub recommends updating existing local remotes.

## Process bounds

- [GNU Coreutils `timeout`](https://www.gnu.org/software/coreutils/manual/html_node/timeout-invocation.html) —
  `--kill-after` guarantees KILL escalation after the initial TERM deadline, including when the
  managed command ignores or blocks TERM. The collector feature-detects this capability and otherwise
  uses an equivalent finite Bash watchdog.

## Design consequences

- Git porcelain/common-dir facts establish local registration and linkage; directory naming never does.
- GitHub merged state is repository-qualified, and the PR head OID must match the local tip before a
  high-confidence handoff.
- A successful old-identity lookup whose canonical `full_name` differs establishes transfer/rename;
  a 403/404 does not distinguish access, deletion, or absence and remains unknown.
- All cleanup/repair/update operations are outside this plugin even though the official tools document
  them; this plugin reports the exact receiving-tool target only.
- Every Git probe disables lazy fetch and optional locks. Every Git/gh call must match a fixed
  command/option/environment allowlist; GitHub REST calls specify `--method GET` explicitly.
- Worktree and branch inventories carry the producing Git command's status. Failed or partial output
  is not evidence and degrades to `UNKNOWN` without a successful-repository count.
