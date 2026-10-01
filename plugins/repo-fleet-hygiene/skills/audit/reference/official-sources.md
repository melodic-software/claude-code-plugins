# Official source record

Fetched and re-verified 2026-07-16, except the Git entries dated 2026-09-29 under "Git claims the
skill bodies restate", which were fetched that day. Recheck trigger: any GitHub GraphQL or REST rate-limit change,
any change to the Git commands or porcelain fields the collector parses, and each Claude Code
minor release that touches skills, plugins, or `allowed-tools`. These sources define the runtime
and evidence contracts; the plugin does not rely on remembered behavior.

## Claude Code

- [Create plugins](https://code.claude.com/docs/en/plugins): plugin root/layout, namespaced skills,
  local `--plugin-dir` testing, and reusable plugin boundary.
- [Plugins reference](https://code.claude.com/docs/en/plugins-reference): manifest fields,
  the plugin-root path variable, and plugin cache isolation.
- [Skills](https://code.claude.com/docs/en/skills): skill frontmatter, arguments, and `allowed-tools`
  semantics. `allowed-tools` grants permission but does not remove other tools, so the skill also states
  its report-only behavioral boundary explicitly.
- [Plugin marketplaces](https://code.claude.com/docs/en/plugin-marketplaces): local marketplace
  catalog structure and validation.

## Git

- [`git` environment and global options](https://git-scm.com/docs/git): `GIT_NO_LAZY_FETCH=1`
  prevents on-demand promisor-remote fetches, while `GIT_OPTIONAL_LOCKS=0` prevents optional
  lock-taking side effects such as index refreshes.
- [`git for-each-ref`](https://git-scm.com/docs/git-for-each-ref): exact ref iteration fields and the
  documented `%00` NUL and `%09` TAB format escapes used for branch/tip records.
- [`git rev-parse`](https://git-scm.com/docs/git-rev-parse): `--show-toplevel`,
  `--git-common-dir`, `--path-format=absolute`, and repository-layout-safe path resolution.
- [`git remote`](https://git-scm.com/docs/git-remote): `get-url` expands Git URL rewrite rules and
  returns the configured fetch URL without changing it.
- [`git worktree`](https://git-scm.com/docs/git-worktree): stable porcelain output, `locked` and
  `prunable` annotations, the linked-worktree `.git` file/common-directory relationship, repair after
  moves, and the instruction to use Git plumbing instead of assuming administrative paths.

### Git claims the skill bodies restate

Each entry: claim, basis, as-of date, recheck trigger.

- **`ls-remote` probes the remote's live refs and reports no match as success.** Basis:
  [`git ls-remote`](https://git-scm.com/docs/git-ls-remote): `--exit-code` "Usually the command
  exits with status 0 to indicate it successfully talked with the remote repository, whether it
  found any matching refs." As of 2026-09-29. Recheck when the collector's ls-remote probe changes
  or that page changes the exit-status text.
- **`--heads` limits output to `refs/heads`.** Basis: the same page, where `--heads` and `-h` are
  "deprecated synonyms for `--branches` and `-b` and may be removed in the future". As of
  2026-09-29. Recheck when a Git release removes `--heads` or the collector moves to `--branches`.
- **`ls-remote --symref origin HEAD` names the remote's default branch.** Basis: the same page,
  `--symref`: shows "the underlying ref pointed by" a symbolic ref, and "upload-pack only shows the
  symref HEAD". As of 2026-09-29. Recheck when the sync skill's default-branch probe changes or
  that page changes the `--symref` text.
- **`git -C <path> config` honors `includeIf`, so a repository's own `worktreeroot.path` is read
  per repository.** Basis: [`git config`](https://git-scm.com/docs/git-config), Includes: the
  `gitdir` condition matches when "the location of the .git directory matches the pattern", and
  for a linked worktree the location is the final `.git` directory, not the `.git` file. As of
  2026-09-29. Recheck when the collector's worktree-root read changes or that section changes.
- **`GIT_CONFIG_GLOBAL`, `GIT_CONFIG_SYSTEM` and `GIT_CONFIG_COUNT` replace or neutralize the
  global, system and environment configuration layers.** Basis: the same page, Environment:
  `GIT_CONFIG_GLOBAL`/`GIT_CONFIG_SYSTEM` "take the configuration from the given files instead
  from global or system-level configuration"; `GIT_CONFIG_COUNT` adds `GIT_CONFIG_KEY_<n>` /
  `GIT_CONFIG_VALUE_<n>` pairs, and an empty or zero count processes none. As of 2026-09-29.
  Recheck when the collector's environment scrub changes or that section changes.
- **The `ls-remote` transport comes from global and system configuration.** Basis:
  [`core.sshCommand`](https://git-scm.com/docs/git-config) (read from the page source,
  `Documentation/config/core.adoc`): "`git fetch` and `git push` will use the specified command
  instead of `ssh`" and it is "overridden when the environment variable is set"; and
  [`gitcredentials`](https://git-scm.com/docs/gitcredentials): `credential.helper` is read from
  configuration, and helpers are tried in turn until Git has a username and password. As of
  2026-09-29. Recheck when either entry changes or a transport setting the probe depends on is
  added or removed. The `core.sshCommand` text names fetch and push, not `ls-remote`; that
  `ls-remote` also uses it is not stated on the page and rests on `ls-remote` connecting through
  the same transport.

## GitHub

- [`gh api graphql`](https://cli.github.com/manual/gh_api): aliased `repository` /
  `pullRequests(headRefName:, first:, states:)` queries for exact-name merged-PR evidence; `--jq`
  flattens alias pages. Never use the search API's `head:` qualifier (prefix semantics).
- [GitHub GraphQL rate limits](https://docs.github.com/en/graphql/overview/rate-limits-and-node-limits-for-the-graphql-api):
  5,000-point/hour primary limit, 500,000 nodes per call, `first`/`last` ∈ 1–100. Measured cost for
  the collector's aliased merged-PR page stays 1 (nodeCount equals the alias count, ≤100 per page).
- [`gh repo view`](https://cli.github.com/manual/gh_repo_view) and
  [`gh api`](https://cli.github.com/manual/gh_api): repository-qualified JSON/API lookup and
  formatted output.
- [`gh environment`](https://cli.github.com/manual/gh_help_environment): host, prompt, update-check,
  extension-update-check, and telemetry controls used to keep the audit non-interactive and constrain
  undeclared egress.
- [Get a repository REST endpoint](https://docs.github.com/en/rest/repos/repos#get-a-repository):
  canonical `full_name`/`default_branch` response and documented 200, 301, 403, and 404 outcomes.
- [Transferring a repository](https://docs.github.com/en/repositories/creating-and-managing-repositories/transferring-a-repository):
  old repository URLs redirect after transfer, but GitHub recommends updating existing local remotes.

## Process bounds

- [GNU Coreutils `timeout`](https://www.gnu.org/software/coreutils/manual/html_node/timeout-invocation.html):
  `--kill-after` guarantees KILL escalation after the initial TERM deadline, including when the
  managed command ignores or blocks TERM. The collector feature-detects this capability and otherwise
  uses an equivalent finite Bash watchdog.

## Design consequences

- Git porcelain/common-dir facts establish local registration and linkage; directory naming never does.
- GitHub merged state is repository-qualified, and the PR head OID must match the local tip before a
  high-confidence local/worktree handoff, or the remote-tracking tip before a high-confidence
  `merged-remote-branch` handoff. HIGH for that kind also requires `git ls-remote --heads` to confirm
  the tip still exists on the remote; a last-fetched remote-tracking match alone is only MEDIUM when
  the probe fails, and emits nothing when the remote head is already gone. A remaining remote head
  after merge is evidence that `delete_branch_on_merge` was not enabled or was blocked; enabling that
  setting is complementary and outside this plugin's mutation boundary.
- A successful old-identity lookup whose canonical `full_name` differs establishes transfer/rename;
  a 403/404 does not distinguish access, deletion, or absence and remains unknown.
- All cleanup/repair/update operations are outside this plugin even though the official tools document
  them; this plugin reports the exact receiving-tool target only.
- Every Git probe disables lazy fetch and optional locks. Every Git/gh call must match a fixed
  command/option/environment allowlist; GitHub REST identity calls specify `--method GET`
  explicitly; GraphQL merge evidence admits `query` documents only (never `mutation`).
- Worktree and branch inventories carry the producing Git command's status. Failed or partial output
  is not evidence and degrades to `UNKNOWN` without a successful-repository count.
