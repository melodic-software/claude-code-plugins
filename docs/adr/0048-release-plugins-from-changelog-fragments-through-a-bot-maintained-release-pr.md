# Release plugins from changelog fragments through a bot-maintained release PR

- Status: accepted
- Date: 2026-10-03

## Context

Every pull request that changes a plugin edits two shared files for that plugin: the `version` in
`plugins/<name>/.claude-plugin/plugin.json` and a new `## [<version>]` entry at the top of
`plugins/<name>/CHANGELOG.md`. The version is the update cache key, so an unbumped plugin never
reaches installed users (`docs/migration-playbook.md:493-496`; ADR 0019 lines 14-20 and 80-82).

Main moves those two files faster than a pull request can merge. Measured on `origin/main` on
2026-10-03 with `git log --since='7 days ago'`:

- 719 of 863 commits touched a `plugins/*/.claude-plugin/plugin.json`.
- The most-bumped plugins were `planning` (87), `claude-ops` (78, since renamed `harness-ops`), `source-control` (74) and
  `disk-hygiene` (72). At 87 a week, `planning` gets a new version about every 1.9 hours, so any
  branch on it that stays open longer than that expects a conflict.
- Successful full CI runs on `pull_request` (the 173 of the last 200 that ran longer than three
  minutes, `gh run list`) took a median of 6.4 minutes and a p90 of 12.7 minutes, before review
  and queue time.

Two concurrent pull requests that bump one plugin conflict on both files. The current repair is
`plugins/source-control/scripts/resolve-version-bump-conflict.sh`, which recomputes the version as
main's version plus one bump at the PR's level and re-heads the PR's changelog entry
(`resolve-version-bump-conflict.sh:7-14`). Four skill documents tell lanes to run it
(`resolve-conflicts/SKILL.md:77`, `babysit-loop/SKILL.md:417`, `babysit-prs/reference/loop.md:334`,
`babysit-prs/reference/orchestration.md:544`). Each conflict still costs a merge of main, a new
commit and a fresh CI run, and the resolver handles only the shape it recognizes; anything else is
left for manual resolution (`resolve-version-bump-conflict.sh:12-14`).

A merge queue does not fix this. `ci.yml:48-61` wires the `merge_group` event, and a queue tests
each pull request against the ones ahead of it, so two queued pull requests that bump one plugin
produce a CHANGELOG conflict and the later one is ejected. Main's active rules today carry no
`merge_queue` rule (`gh api repos/melodic-software/claude-code-plugins/rules/branches/main`,
2026-10-03: `pull_request` squash-only, `required_status_checks` on `ci-status` with
`strict_required_status_checks_policy: false`, `required_signatures`, `required_linear_history`).

The gates that enforce today's per-PR discipline:

| Gate | Where | What it requires of a pull request |
|---|---|---|
| `check-changelog-parity.sh --check` | `ci.yml:1312-1315` | Every versioned plugin has a CHANGELOG whose newest heading does not exceed the manifest version |
| `--check-bump` | `ci.yml:1316-1326` | A version change adds a `## [<v>]` entry, strictly greater than base, with a non-repeated body, and the plugin has another changed file (`check-changelog-parity.sh:87-96`) |
| `--check-preserved` | `ci.yml:1332-1342` | No touched changelog drops a heading it carried at the fork point |
| `--check-order` | `ci.yml:1346-1349` | Every changelog reads newest-first with no duplicate versions |
| `check-vendor-version-bump.sh --check-bump` | `ci.yml:1358-1368` | A `vendor/` change bumps the plugin version |
| `sync-shared-copies.sh --check-bump` | `ci.yml:2100-2369`; `sync-shared-copies.sh` | A shared-library change bumps every carrying plugin |
| `check-stale-base-overlap.sh` | `ci.yml:1274-1302` | No path the PR changed also changed on main since its merge base; every plugin.json and CHANGELOG bump counts as an overlapping path |

`.claude-plugin/marketplace.json` lists 85 plugins and none of the entries carries a `version`, so
the manifest is the only place a version lives. Dependabot cannot write the bump, so
`.github/workflows/pr-bump-plugin-version.yml` writes it on Dependabot pull requests through the
GraphQL `createCommitOnBranch` mutation, which GitHub signs (lines 9-14 and 85-111).

## Decision

Pull requests stop editing plugin versions and CHANGELOG entries. Each one adds a changelog
fragment instead, and one bot-maintained release pull request turns the pending fragments into
version bumps and CHANGELOG entries.

### Fragment format and location

- **Location:** `.changes/<plugin>/<branch-slug>-<suffix>.md` at the repository root, one file per
  plugin a pull request releases. The directory sits outside `plugins/` so fragments never ship
  into an installed plugin's cache copy. `<branch-slug>` is the branch name with `/` replaced by
  `-`, which alone is not unique (`fix/foo-bar` and `fix-foo/bar` map to one slug, and two forks
  can use one branch name), so `<suffix>` is 8 random hex characters. A new
  `scripts/new-changelog-fragment.sh <plugin> <bump>` creates the file with that name and the
  front matter, so a contributor needs no pull request number in advance. A gate still rejects a
  fragment whose path already exists on the base.
- **Format:** YAML front matter with one required key, then a Keep a Changelog body:

  ```markdown
  ---
  bump: minor
  ---

  ### Added

  - **`interview` recommends separate implement and verify effort levels.** ...
  ```

- **Bump level:** `bump` is `major`, `minor`, `patch` or `none`. The body's `###` headings are the
  existing Keep a Changelog section names the CHANGELOGs already use (`Added`, `Changed`, `Fixed`,
  `Removed`, `Security`, `Deprecated`).
- **Opt-out:** a pull request that changes a plugin's shipped files but needs no release adds a
  fragment with `bump: none` and a body of one line saying why. The opt-out sits in the diff, so a
  reviewer sees it; a label would not. A release deletes `none` fragments without bumping or
  writing a CHANGELOG entry for them.
- A fragment may be edited or deleted by a later pull request until a release consumes it.

### The release pull request

- **Workflow:** a new `.github/workflows/release-plugins.yml` with `concurrency` set to one group
  and `cancel-in-progress: true`.
- **Trigger and cadence:** `schedule`, `workflow_dispatch`, and `push` to main filtered to
  `.changes/**`. It does not rebuild on every push to main: at the measured commit rate,
  regenerating on every push would force-push the release branch faster than its CI completes, and
  it would never merge. On each run:
  - With no release pull request open, it builds one from main's current fragments.
  - With one open, it rebuilds it from main only when main holds a fragment the release pull
    request did not consume for a plugin that release pull request bumps, or when the release pull
    request has a merge conflict (a consumed fragment was edited or deleted on main). Otherwise it
    leaves it alone, so its CI can finish. A fragment for a plugin the release does not bump waits
    for the next release; that plugin's version does not move, so its newer code ships under no
    wrong version.
  - A rebuild is the same `createCommitOnBranch` write and ref update described below, so it restarts
    the release pull request's CI. Rebuilds happen only as often as fragments for the plugins in
    the open release land, not on every main commit.
- **Release check:** a `check-changelog-fragments.sh --check-release <base>` step, run only on the
  `release/plugins` pull request, fails when the base holds an unconsumed fragment for a plugin the
  release bumps. Every rebuild re-runs it. The gates recognize the release pull request by its head
  branch alone: CI passes `CHANGELOG_HEAD_REF`, the head branch of a pull request from this
  repository (empty for a fork), and the scripts compare it to `release/plugins`. A path-based
  exemption could not tell a release from a hand-written bump, which is the change the gates must
  reject. That alone does not stop a stale merge: main's status
  checks are not strict (see Context), so a green result from before a fragment landed still allows
  a merge while the push-triggered rebuild is in flight. The merge path closes that gap (next
  bullet).
- **Merge path:** the release pull request merges only through the workflow's own `merge` step,
  never the merge button. The step runs `--check-release` against main's live tip, then queues the
  release head SHA it checked (`enqueuePullRequest` with `expectedHeadOid`; `mergePullRequest`
  with the same pin only when main has no merge queue); a failing check starts a rebuild instead of
  a merge. Main's merge queue went live on 2026-10-03 (ruleset 24422263, squash), so
  `--check-release` also runs on every `merge_group` commit with `HEAD^1` as its base: the tree the
  queued squash commit lands on, which is main plus every entry ahead of it. `merge_group.base_sha`
  alone would miss a fragment queued ahead of the release. A queued commit that bumps no plugin
  with pending fragments passes, so the step needs no release detection there.
- **Aggregation**, by a new `scripts/release-plugins.sh` the workflow runs:
  1. Group the fragments under `.changes/<plugin>/`.
  2. The new version is the manifest's current version raised once at the highest `bump` among
     that plugin's fragments. One release is one version, however many fragments it consumes. A
     plugin whose fragments are all `bump: none` gets no new version.
  3. Write one `## [<new>] - <date>` entry above the newest heading, merging the non-`none`
     fragments' bodies section by section, in fragment commit order.
  4. Set `version` in `plugin.json` only. No marketplace entry carries a version, and the bot does
     not add one.
  5. Delete the consumed fragments.

  When no plugin gets a new version (every pending fragment is `bump: none`), the workflow opens
  no release pull request: one titled `release 0 plugins` would only delete files. The `none`
  fragments wait and go with the next release.
- **Token and signed commits:** a GitHub App installation token, not `GITHUB_TOKEN`. Pull request
  events that `GITHUB_TOKEN` causes start no workflow runs or start them waiting for approval
  (`pr-bump-plugin-version.yml:15-20`), and the release pull request needs `ci-status` to run.
  The bot writes its one commit through `createCommitOnBranch` with `expectedHeadOid` (the
  pattern at `pr-bump-plugin-version.yml:85-111`) on a staging branch,
  `release/plugins-next`, cut from main's tip, then moves `release/plugins` to that commit in one
  ref update. A run cut short therefore never leaves the open release pull request with an empty
  head. GitHub signs that commit, which satisfies main's
  `required_signatures` rule.
- **Title and merge:** `chore(release): release <n> plugins`, which passes the Conventional Commits
  title check. Its body lists each plugin's old and new version and the fragments consumed. Until
  the phase 2 pilot proves the merge step, a person starts it by `workflow_dispatch`; after that the
  workflow runs it itself (see Resolved decisions).

### Gates

| Gate | Change |
|---|---|
| `check-changelog-parity.sh --check`, `--check-preserved`, `--check-order` | Kept as they are. They guard CHANGELOG integrity, which now changes only in release pull requests |
| `--check-bump` | Kept for the release pull request. Its "bump without change" rule (`check-changelog-parity.sh:93-96`) counts a consumed fragment as the change. For a plugin in fragment mode, any other pull request that changes its `version` or adds a CHANGELOG heading fails with a message pointing at `.changes/` |
| New `check-changelog-fragments.sh` | Validates every added or modified fragment: path names an existing plugin, front matter has a valid `bump`, the body has at least one known `###` section (a `bump: none` fragment needs only a non-empty reason line instead), and an added fragment's path is new on the base |
| New `check-changelog-fragments.sh --check-required <base>` | For each fragment-mode plugin whose shipped files (anything under `plugins/<name>/`) the pull request changes, requires an added or modified fragment for that plugin, `bump: none` included. Only the release pull request's own writes (the root `CHANGELOG.md` and a version-only `plugin.json` edit) are exempt; the same edits in any other pull request need a fragment |
| New `check-changelog-fragments.sh --check-release <base>` | Runs on the release pull request only. Fails when the base holds an unconsumed fragment for a plugin the release bumps (see The release pull request) |
| `check-vendor-version-bump.sh` and the `sync-*.sh --check-bump` steps | One shared predicate in `scripts/lib/` replaces "manifest version moved" with "manifest version moved, or a fragment for that plugin with a `bump` other than `none` was added". The version-moved branch stays so legacy plugins pass during the dual mode |
| `check-stale-base-overlap.sh` | Unchanged. It stops firing on version files because pull requests no longer touch them |
| `pr-bump-plugin-version.yml` and `scripts/dependabot-plugin-bump.sh` | For a plugin in fragment mode, `dependabot-plugin-bump.sh` writes a `patch` fragment (`### Changed` with the dependency lines), named the way `new-changelog-fragment.sh` names one, instead of the bump; the workflow commits it through the same `createCommitOnBranch` call. Legacy plugins keep the bump |
| `resolve-version-bump-conflict.sh` | Kept in the `source-control` plugin, which other repositories install and which may still bump per pull request. This repository stops calling it once every plugin is in fragment mode, and the four skill documents above say it applies only to repositories that bump per pull request |

### How installed users see updates

Nothing changes on the consuming side. The manifest `version` stays the update cache key, and a
plugin's version changes only when a release pull request merges, so installed users receive
changes in release-sized batches at the release cadence. A plugin with pending fragments on main
still carries its last released version.

## Alternatives considered

- **Changesets as-is.** `changesets/action` keeps one "Version Packages" pull request updated from
  pending changesets and can commit through the GitHub API so commits are signed
  (<https://github.com/changesets/action>, fetched 2026-10-03). Rejected as a dependency: it reads
  versions from `package.json` workspaces, and these plugins are not npm packages. Its model is the
  one adopted here: per-change fragment files carrying a bump level, and a single release pull
  request.
- **Towncrier.** Fragments named `<id>.<type>` in a news directory; `towncrier build` writes them
  into the changelog and runs `git rm` on them, with a documented monorepo layout
  (<https://towncrier.readthedocs.io/en/stable/tutorial.html>, fetched 2026-10-03). Rejected as a
  dependency: a fragment declares a change type, not a semver bump level, and it needs a Python
  toolchain in the release job. The fragment-per-change layout is the same idea.
- **release-please (manifest mode).** Tracks per-package versions in
  `.release-please-manifest.json` and computes the bump from Conventional Commits since the last
  release, with one combined release pull request or one per package
  (<https://github.com/googleapis/release-please/blob/main/docs/manifest-releaser.md>, fetched
  2026-10-03). Rejected: this repository squash-merges and writes one Conventional Commits title
  per pull request, often spanning several plugins, so the title cannot carry a per-plugin bump
  level or per-plugin release notes, and the hand-written CHANGELOG prose would be lost.
- **Omit `version`.** With `version` absent from both the manifest and the marketplace entry, a
  relative-path plugin in a Git-hosted marketplace takes "the commit SHA of the installed
  directory" as its version (<https://code.claude.com/docs/en/plugins/loading#how-claude-code-computes-the-version>,
  fetched 2026-10-03). Deferred: it removes the race entirely, but the docs do not say whether that
  SHA is the last commit touching the plugin directory or the marketplace HEAD. If it is HEAD,
  every merge to main would refresh all 85 plugins for every user. The probe under Resolved
  decisions settles it before phase 2.
- **Compute the version at merge time.** A post-merge job bumps on main. Rejected: main requires a
  pull request for every change, so a direct push needs a ruleset bypass for the bot, which widens
  who can write to main without review.
- **Status quo with the resolver.** Rejected: it repairs each collision after it happens, costs a
  merge, a commit and a CI run per collision, leaves unrecognized shapes to a human, and cannot run
  inside a merge queue.

## Consequences

- Pull requests in fragment mode no longer conflict on `plugin.json` or `CHANGELOG.md`, and no
  longer trip `check-stale-base-overlap.sh` on those files.
- Release latency rises from "at merge" to "at the next release merge". A fix waits for the
  release cadence before installed users get it.
- Between releases, main's plugin files differ from what the released version string describes. A
  user who installs or reinstalls a plugin from main in that window gets main's files in a cache
  directory named after the last released version, and a later release replaces them. Today every
  merge bumps, so this window does not exist.
- One GitHub App, its secret and the release workflow become new infrastructure to keep running.
  If the bot stops, changes still merge but stop reaching users, with nothing failing visibly; the
  release workflow needs an alert on a stale open release pull request or on fragments older than a
  threshold.
- Contributor instructions change: `AGENTS.md:19-21` ("shared version bump and CHANGELOG line"),
  `docs/migration-playbook.md:493-496`, ADR 0019's bump wording (lines 14-20, 101-103) and the
  four resolver references all describe the per-PR bump and need rewording for fragment mode.
- The standards sync writes `plugins/guardrails/lib/path-detection/machine-path-patterns.sh`
  (the standards repository's `sync-manifest.yml`). Once `guardrails` is in fragment mode, a sync
  pull request that changes that file fails `--check-required` with MISSING FRAGMENT until a
  maintainer adds one on the sync branch with `scripts/new-changelog-fragment.sh guardrails patch`.
  Having the standards sync write that fragment itself is a follow-up in the standards repository.

## Rollout

Each phase has its own rollback, and no phase removes the previous path until the next one is
proven.

1. **Tooling, no plugin opted in.** Land `release-plugins.sh`, `new-changelog-fragment.sh`,
   `check-changelog-fragments.sh` with its `--check-required` and `--check-release` modes, the
   shared bump predicate and their tests, with an opt-in list `scripts/fragment-plugins.txt` that is
   empty. Rollback: revert the commit; nothing reads the list yet.
2. **Pilot one plugin.** Add one low-traffic plugin to the list, create the GitHub App, and run the
   release workflow by `workflow_dispatch` only. Done when one release pull request merges with a
   signed commit, a green `ci-status`, and a bumped version that `claude plugin update` picks up.
   Rollback: remove the plugin from the list and hand-write any pending fragments into its
   CHANGELOG with a normal bump.
3. **Dual mode, high-traffic plugins.** Add the ten plugins whose `plugin.json` changed most in
   the 7 days to 2026-10-04: `planning` (102), `source-control` (92), `disk-hygiene` (80),
   `guardrails` (65), `testing` (63), `session-flow` (61), `harness-ops` (57, plus 73 as
   `claude-ops` before its rename to `harness-ops`), `playbooks` (53), `instruction-placement` (53)
   and `context-guard` (50). Turn on the schedule and the `.changes/**` push trigger; those runs
   merge a current, green release pull request themselves. Switch `pr-bump-plugin-version.yml`
   to fragments for listed plugins, because `harness-ops` takes Dependabot updates. Convert
   open pull requests that hand-bump a newly listed plugin with
   `plugins/source-control/scripts/convert-bump-to-fragment.sh`. Legacy plugins keep the per-PR
   bump and the resolver. Rollback: as in phase 2, per plugin.
4. **Fleet.** Add every remaining plugin, let `new-changelog-fragment.sh` write one fragment for
   every plugin that carries an edited shared library, update `docs/migration-playbook.md` and
   ADR 0019, and update the contributor instructions listed under Consequences. Rollback: empty
   the list; Dependabot and the per-PR gates fall back to the bump for listed-out plugins.
5. **Retire the per-PR path in this repository.** Replace the opt-in list with "all plugins", drop
   the version-moved branch of the shared predicate, and reword the resolver references. Rollback:
   revert this phase's commit, which restores phase 4.

## Resolved decisions

1. **Release pull request merging.** The workflow's `merge` step merges it automatically once the
   phase 2 pilot proves that step. Until then a person starts the step by `workflow_dispatch`, never
   the merge button.
2. **Cadence.** The schedule fires every 3 hours.
3. **Fragment scope.** Every change to a plugin's shipped files needs a fragment. A change that
   needs no release opts out with a `bump: none` fragment, and `--check-required` enforces both.
4. **GitHub App.** A new dedicated release App, separate from the standards-sync App. The pilot
   still confirms that main's `require_extra_approval_for_unattributed_changes: true` does not
   block the bot's pull request.
5. **Version-omission probe.** Run it before phase 2: a disposable Git marketplace with two
   relative-path plugins and no `version` anywhere; install both, commit a change to one, run
   `claude plugin update` for each, and see which reports a new version. If only the changed
   plugin updates, revisit this ADR before continuing.
