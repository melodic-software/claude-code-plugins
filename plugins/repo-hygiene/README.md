# repo-hygiene

A Claude Code plugin that returns a repository toward a known-good state.
`/repo-hygiene:clean` is an action-router: it inventories reclaimable space,
removes tool caches and build artifacts, prunes stale git metadata, and, as a
deliberately-gated destructive tier, realigns the working tree to a fresh-pull
state. Every mutating path is **dry-run-first**, and the destructive tiers are
gated behind explicit confirmation plus a session-scoped destructive-command
guard.

## Actions

`/repo-hygiene:clean <action>` routes every action below. Bare invocation infers
intent from the conversation, or presents a menu and falls back to the safe `scan`.
`/repo-hygiene:setup` is the separate, read-only prerequisite check. It verifies
`git`, `node`, the optional `ghq`, and the effective destructive-guard toggle, and cleans
nothing.

| Action | What it does | Risk |
|--------|--------------|------|
| `scan` | Read-only inventory of reclaimable caches, build output, and stale git refs | Safe |
| `caches` | Remove tool / linter caches (`.pytest_cache`, `.ruff_cache`, `__pycache__`, `.turbo`, `.vs`, …) | Low |
| `build` | Remove build artifacts (`bin`/`obj`/`build`/`dist`/`out`/`target`/`TestResults`, `*.binlog`), includes caches | Low |
| `git` | Prune stale worktree/remote metadata and gc; audit branches (merged / PR-merged / stale) and delete only on per-branch opt-in | Low |
| `tree` | Reset the working tree like a fresh pull. `git reset --hard` + `git clean -fdx` | **Destructive** |
| `tree-batch` | Run `tree` across many repos (`ghq list`, a glob, or an explicit list) behind one confirmation gate, with a separator-agnostic skip list and a dirty-by-default guard | **Destructive** |
| `all` | Sweep `caches` + `build` + `git`. **never** the `tree` reset | Medium |

Tiers are cumulative (`build` includes `caches`; `all` is `build` plus `git`), and
neither `tree` nor `tree-batch` is composed into `all`. One mistaken sweep cannot
trigger a `reset --hard`.

### Multi-repo reset (`tree-batch`)

`tree-batch` is the supported way to reset a fleet of repos to a fresh-pull state
without hand-rolling a loop. It skips any repo with uncommitted/untracked changes
or unpushed commits **by default** (opt in with `--include-dirty`). Its skip
list is matched separator-agnostically, so a `\`-path skip entry reliably protects
a repo enumerated with `/` paths, the failure that lost an uncommitted edit in an
ad-hoc loop. A skip entry that matches nothing is reported, never silently ignored.

```shell
# Dry-run the whole ghq tree, skipping one repo (the agent shows the plan first):
ghq list -p | /repo-hygiene:clean tree-batch --repos-from - --skip melodic-software/standards
```

### Multi-repo audits

The branch and stash audits take the same repo selection as the batch tiers
(`--repo`, `--repos-from`, `--skip`, `--skip-from`) and print one `Repo: <path>`
block per repository. Linked worktrees of one repository are audited once, a
failing repo is reported without stopping the rest, and each repo writes its own
branch-tip capture (`--capture-file` is refused with more than one repo).
The audits delete no branch and change no working-tree file. Besides the
capture, the branch audit's landed-proof squash check writes one unreferenced
loose object per branch it reaches, which `git gc` prunes.
Deletion is not batched: run the delete from inside the audited repo, with that
repo's `TipCapture:` path. A branch audit across a fleet of repositories is
`/repo-fleet-hygiene:audit`. Per repository, add `--read-only` to write no capture
and no object (the squash check runs in a throwaway object directory), or `--remote`
to audit the live `origin` branches against merged PRs (a tip that differs from its
merged PR's head is `MERGED-DRIFT`).

```shell
ghq list -p | bash ${CLAUDE_PLUGIN_ROOT}/skills/clean/scripts/git-branch-audit.sh --repos-from -
```

## Safety model

- **Dry-run-first, always.** No tier applies on the first invocation; the agent
  shows the plan and requires confirmation before `--apply`.
- **Preserved by default across every tier**, including `tree`: **secrets /
  local config** (`.env*`, `*.local.json`/`.jsonc`/`.md`, IDE + cloud + Codex
  config), **runtime dependencies** (`node_modules/`, `.venv/`, `vendor/`), and
  **skill-owned `data/`** directories. `tree` widens deletion only with the
  explicit `--include-deps` / `--include-secrets` flags, and `--include-secrets`
  demands its own separate confirmation because it is unrecoverable.
- **Any git-tracked file is off-limits** to selective deletion; a tracked file
  deleted by reparse-point (junction/symlink) traversal during a `tree` clean is
  auto-restored from the index.
- **Session-scoped destructive guard.** While a mutating clean run is open (a
  per-session run marker under the plugin data directory, written by the
  mutating tiers and never by `scan` or `scan-batch`, cleared when the run ends,
  with an idle timeout as a fallback), a PreToolUse hook blocks bare `rm -rf`, `git clean -f*`, `git reset --hard`,
  `git checkout --`, recursive `Remove-Item`, bare `git branch -D`/`-d`/`--delete`,
  `git push --delete` and `git push origin :ref` (also `+:ref`), the clean scripts when the
  command contains `--apply`, and `git worktree remove` with a force flag. A
  dry-run (including a dry-run push) is not blocked. The confirmed command runs
  only through the skill's own gate, and the ack-prefixed spelling is the
  documented way to run a bare `git branch -D` during a clean session. The guard
  is a best-effort net over command words, not a security boundary; on the Bash tool destructive
  text inside one quoted argument does not match. The skill deletes local
  branches with `git-branch-delete.sh` after the confirmation gate, which uses
  `git update-ref -d` and so does not go through the branch patterns. Kill switch: the `clean_destructive_guard_enabled`
  userConfig option set to `false` (`/plugin configure repo-hygiene@<marketplace>`, or
  `claude plugin install repo-hygiene@<marketplace> --config clean_destructive_guard_enabled=false`),
  both user-scoped. To disable per repository, disable the plugin in that project's
  `enabledPlugins`.
- **Autonomous sessions abort** the destructive tiers rather than deleting
  unattended.

## Works in any repo

- Self-contained: the path registry, tier scripts, destructive guard, and the
  reference tables all ship inside the plugin under `${CLAUDE_PLUGIN_ROOT}`.
- No baked layout. Ecosystem targets are generic (universal `bin`/`obj`/… globs,
  common cache dirs) and the .NET solution is detected at runtime. Nothing
  assumes a specific repo's directory structure.
- Conservative by default: the protected-path and preserve lists err toward
  keeping a consumer's dependencies, credentials, and IDE state.

## Requirements

- `git` on PATH.
- Node.js on PATH. Every hook row runs `node hooks/exec-bash.mjs`, and a Claude Code install does
  not guarantee Node, so without it the destructive guard does not launch and is not enforced.
  - **Pointer**: whether an install brings Node is in
    [Install with npm](https://code.claude.com/docs/en/setup#install-with-npm). **As of**:
    2026-10-11. **Recheck trigger**: that section changes whether the native binary ships or uses
    Node, or is renamed.
- `bash`: found on PATH, then `/bin/bash` and `/usr/bin/bash`; on Windows, Git Bash.
- `ghq` (optional) for the fleet batch actions' repository enumeration.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install repo-hygiene@<marketplace>
```

## Configuration

One `userConfig` option, `clean_destructive_guard_enabled`, documented below.
The protected-path list is enforced by the bundled bash scripts
(which do not read `CLAUDE.md`); a consumer relies on the git-tracked guarantee
and the `tree` tier's default-preserve classes to keep additional paths safe. A
declared per-consumer override for the script-enforced protected list is a known
extension point, not yet exposed as configuration.

<!-- BEGIN GENERATED: plugin options. Edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. Every option Claude Code
will prompt for when the plugin is enabled, with the environment variable each hook
reads it from.

| Option | Type | Default | Environment variable | Description |
| --- | --- | --- | --- | --- |
| `clean_destructive_guard_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_CLEAN_DESTRUCTIVE_GUARD_ENABLED` | Session-scoped PreToolUse guard that blocks destructive Bash and PowerShell commands while the clean skill is active. On by default. |

### How to set these

Three supported routes:

1. **Interactively.** Open this plugin's options dialog ([`/plugin` in a session](https://code.claude.com/docs/en/plugins/cli-reference#plugin-in-a-session)):
   `/plugin configure repo-hygiene@<marketplace>`.
2. **Headless.** Save the values with [`claude plugin configure`](https://code.claude.com/docs/en/plugins/cli-reference#plugin-configure),
   run from the project the plugin is installed in. Replace
   `<marketplace>` with the marketplace you installed this plugin from:

   ```shell
   claude plugin configure repo-hygiene@<marketplace> --values-stdin < values.json
   ```

   `values.json` holds a JSON object of strings, booleans included:

   ```json
   {"clean_destructive_guard_enabled": "<value>"}
   ```

   This is the preferred headless route in the [plugin-reconfiguration convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/contracts/plugin-reconfiguration/README.md), which records its
   limits: the Claude Code version it needs, which install it finds, how it rejects a bad
   value, and why a session started before the change keeps the old value until a fresh
   session starts. Do **not** `claude plugin uninstall` to reconfigure: see
   [What an uninstall deletes and keeps](https://code.claude.com/docs/en/plugins/cli-reference#what-an-uninstall-deletes-and-keeps).

   The fallback the convention names, for a Claude Code release without
   `plugin configure`, reruns the install with the new value, passing the scope
   `claude plugin list` reports for this plugin:

   ```shell
   claude plugin install repo-hygiene@<marketplace> -s <scope> --config clean_destructive_guard_enabled=<value>
   ```

3. **By hand, in settings.** Add the value under `pluginConfigs` in your **user**
   settings (`~/.claude/settings.json`):

   ```json
   {
     "pluginConfigs": {
       "repo-hygiene@<marketplace>": {
         "options": {
           "clean_destructive_guard_enabled": <value>
         }
       }
     }
   }
   ```

   The [`pluginConfigs`](https://code.claude.com/docs/en/settings-reference#pluginconfigs)
   entry names the settings scopes Claude Code reads this key from.

Do not set the `CLAUDE_PLUGIN_OPTION_*` variables yourself; set the value through one
of the routes above.

### Upstream documentation

- [User configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration): the `userConfig` schema and the `CLAUDE_PLUGIN_OPTION_<KEY>` export
- [Plugin configure](https://code.claude.com/docs/en/plugins/cli-reference#plugin-configure): the `--values-stdin` flag's reference entry
- [Plugin install options](https://code.claude.com/docs/en/plugins/cli-reference#plugin-install): the `--config` flag's reference entry
- [Plugins and skills settings](https://code.claude.com/docs/en/settings-reference#plugins-and-skills): `enabledPlugins`, `extraKnownMarketplaces`, `pluginConfigs`
- [Settings files and who they affect](https://code.claude.com/docs/en/settings#settings-files-and-who-they-affect): user vs project vs local precedence
- [Manage installed plugins](https://code.claude.com/docs/en/plugins/install#manage-installed-plugins): enabling, disabling, `/plugin list`

<!-- END GENERATED: plugin options -->

## License

MIT (SPDX-License-Identifier: MIT).
