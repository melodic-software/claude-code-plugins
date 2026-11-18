# Official source record

Each entry states what the plugin does and where to read the upstream specifics live; the plugin
does not rely on remembered behavior.

## Claude Code

- **Pointer**: when changing the plugin's layout or testing it locally with `--plugin-dir`, fetch
  [Plugin layout](https://code.claude.com/docs/en/plugins/create#plugin-layout) and
  [Develop without a marketplace](https://code.claude.com/docs/en/plugins/create#develop-without-a-marketplace)
  live.
- **Pointer**: when a manifest or skill path uses `${CLAUDE_PLUGIN_ROOT}`, fetch
  [Environment variables](https://code.claude.com/docs/en/plugins/manifest-reference#environment-variables)
  live.
- **Pointer**: when a script reads a path outside the plugin root, fetch
  [Find plugins on disk](https://code.claude.com/docs/en/plugins/loading#find-plugins-on-disk) live.
- The skill states its report-only boundary in its own text and does not rely on `allowed-tools`
  to hold it.
  - **Pointer**: when changing the skill's frontmatter or `allowed-tools`, fetch
    [Frontmatter reference](https://code.claude.com/docs/en/skills#frontmatter-reference) and
    [Pre-approve tools for a skill](https://code.claude.com/docs/en/skills#pre-approve-tools-for-a-skill)
    live.
- **Pointer**: when changing the marketplace entry or reading a validation message, fetch
  [Marketplace file](https://code.claude.com/docs/en/plugins/marketplace-reference#marketplace-file) and
  [Validation messages](https://code.claude.com/docs/en/plugins/marketplace-reference#validation-messages)
  live.

## Git

- Every Git probe sets `GIT_NO_LAZY_FETCH=1` and `GIT_OPTIONAL_LOCKS=0`, so the audit fetches no
  objects and takes no optional lock.
  - **Pointer**: when changing the probe environment, fetch
    [`GIT_NO_LAZY_FETCH`](https://git-scm.com/docs/git#Documentation/git.txt-GITNOLAZYFETCH) and
    [`--no-optional-locks`](https://git-scm.com/docs/git#Documentation/git.txt---no-optional-locks)
    live.
- Branch and tip records come from `git for-each-ref` with `%09` between fields and `%00`
  ending each record.
  - **Pointer**: when changing the record format, fetch
    [`git for-each-ref --format`](https://git-scm.com/docs/git-for-each-ref#Documentation/git-for-each-ref.txt---formatformat)
    live.
- Repository paths come from `git rev-parse`, never from an assumed `.git` layout.
  - **Pointer**: when changing path resolution, fetch
    [`--show-toplevel`](https://git-scm.com/docs/git-rev-parse#Documentation/git-rev-parse.txt---show-toplevel),
    [`--git-common-dir`](https://git-scm.com/docs/git-rev-parse#Documentation/git-rev-parse.txt---git-common-dir)
    and
    [`--path-format`](https://git-scm.com/docs/git-rev-parse#Documentation/git-rev-parse.txt---path-formatabsoluterelative)
    live.
- The remote URL is read with `git remote get-url`; the audit changes no remote.
  - **Pointer**: when changing how the remote URL is read, fetch
    [`git remote get-url`](https://git-scm.com/docs/git-remote#Documentation/git-remote.txt-get-url)
    live.
- Worktree registrations come from `git worktree list --porcelain -z`, never from Git's
  administrative directories.
  - **Pointer**: when changing the worktree probe or how its `locked` and `prunable` lines are
    read, fetch [Porcelain Format](https://git-scm.com/docs/git-worktree#_porcelain_format) and
    [DETAILS](https://git-scm.com/docs/git-worktree#_details) live.

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

- Merged-PR evidence comes from aliased `gh api graphql` `repository` /
  `pullRequests(headRefName:, first:, states:)` queries, flattened with `--jq`. Never use the
  search API's `head:` qualifier: the evidence needs an exact branch-name match.
  - **Pointer**: when changing the merged-PR query, fetch
    [`gh api`](https://cli.github.com/manual/gh_api) live.
- GitHub GraphQL limits: the measured cost for the collector's aliased merged-PR page stays 1
  (nodeCount equals the alias count, ≤100 per page). Pointer: when sizing a query, fetch the
  [primary rate limit](https://docs.github.com/en/graphql/overview/rate-limits-and-query-limits-for-the-graphql-api#primary-rate-limit)
  and [node limit](https://docs.github.com/en/graphql/overview/rate-limits-and-query-limits-for-the-graphql-api#node-limit)
  live. As of: 2026-11-10. Recheck trigger: either section lowers a limit below the collector's
  measured page.
- Every repository lookup goes through `gh api` and names its repository explicitly.
  - **Pointer**: when changing a repository lookup or its output format, fetch
    [`gh api`](https://cli.github.com/manual/gh_api) live.
- The collector sets gh's host, prompt, update-check, extension-update-check and telemetry
  variables, and clears its repository, pager, editor and browser ones, so the audit never prompts
  and makes no network call it does not declare.
  - **Pointer**: when changing those variables, fetch
    [`gh environment`](https://cli.github.com/manual/gh_help_environment) live.
- Identity lookups read the canonical `full_name` and `default_branch`; how each status is
  treated is under [Design consequences](#design-consequences).
  - **Pointer**: when changing the identity lookup or adding a status it handles, fetch
    [Get a repository](https://docs.github.com/en/rest/repos/repos#get-a-repository) live.
- A transfer or rename is reported as `github-remote-moved` with a `git remote set-url`
  suggestion. Analysis goes on against the resolved `full_name`, and the audit changes no remote.
  - **Pointer**: when deciding how a moved repository is reported, fetch
    [What's transferred with a repository?](https://docs.github.com/en/repositories/creating-and-managing-repositories/transferring-a-repository#whats-transferred-with-a-repository)
    live.

## Process bounds

- Each gh call is bounded by `timeout --signal=TERM --kill-after` when an installed `timeout` or
  `gtimeout` offers `--kill-after`, and otherwise by a finite Bash watchdog, so a hung call
  cannot stall the audit.
  - **Pointer**: when changing the deadline or its fallback, fetch
    [GNU Coreutils `timeout`](https://www.gnu.org/software/coreutils/manual/html_node/timeout-invocation.html)
    live.

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
