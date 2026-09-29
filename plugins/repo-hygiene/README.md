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

Tiers are cumulative (`build` includes `caches`; `all` = `build` + `git`), and
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

### Multi-repo audits (read-only)

The branch and stash audits take the same repo selection as the batch tiers
(`--repo`, `--repos-from`, `--skip`, `--skip-from`) and print one `Repo: <path>`
block per repository. Linked worktrees of one repository are audited once, a
failing repo is reported without stopping the rest, and each repo writes its own
branch-tip capture (`--capture-file` is refused with more than one repo).
Deletion is not batched: run the delete from inside the audited repo, with that
repo's `TipCapture:` path.

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
- **Session-scoped destructive guard.** While the skill is active, a PreToolUse
  hook blocks bare `rm -rf`, `git clean -f*`, `git reset --hard`,
  `git checkout --`, recursive `Remove-Item`, bare `git branch -D`/`-d`/`--delete`,
  `git push --delete` and `git push origin :ref`, the clean scripts when the
  command contains `--apply`, and `git worktree remove` with a force flag. A
  dry-run (including a dry-run push) is not blocked. The confirmed command runs
  only through the skill's own gate, and the ack-prefixed spelling is the only way
  a bare `git branch -D` runs during a clean session. The skill deletes local
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
- Node.js on PATH. Every hook row runs `node hooks/exec-bash.mjs`, and Claude Code's native binary
  neither ships nor uses Node, so without it the destructive guard does not launch and is not
  enforced.
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
| `clean_destructive_guard_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_CLEAN_DESTRUCTIVE_GUARD_ENABLED` | Session-scoped PreToolUse guard blocking destructive Bash and PowerShell commands while the clean skill is active |

### How to set these

Three supported routes, in the order most people want them:

1. **Interactively.** Claude Code prompts for declared options when you enable the
   plugin. To change them later: `/plugin configure repo-hygiene@<marketplace>`.
2. **Headless.** Repeat `--config` for each option. Replace
   `<marketplace>` with the marketplace you installed this plugin from:

   ```shell
   claude plugin install repo-hygiene@<marketplace> -s <scope> --config clean_destructive_guard_enabled=<value>
   ```

   The same command reconfigures a plugin that is **already installed**: it prints
   `already installed` and still writes the value. The short-circuit message is
   about the install, not the config write. Do **not** `claude plugin uninstall` to
   reconfigure: uninstalling drops this plugin's whole stored `pluginConfigs` entry,
   resetting every option in the table above to its default. `-s` defaults to `user`,
   so pass the scope `claude plugin list` reports for this plugin. The verified-version
   record lives in the [plugin-reconfiguration convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/plugin-reconfiguration/README.md).

   The value is stored immediately; the session you are in does not change. Hooks are
   handed their `CLAUDE_PLUGIN_OPTION_*` when the session starts, so start a fresh
   Claude Code session before expecting new behavior. A check run in the old session
   still reports the old value, and that is not a failed write.

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

   Plugin option values are read from **user**, `--settings`, and managed settings
   only, **not** from a project's `.claude/settings.json`. To vary behavior per
   repository, enable or disable the plugin in that project's `enabledPlugins`
   instead of setting an option there.

Do not set the `CLAUDE_PLUGIN_OPTION_*` variables yourself. They are how Claude Code
hands a configured value to a hook process; the value comes from the routes above.

### Upstream documentation

- [User configuration](https://code.claude.com/docs/en/plugins-reference#user-configuration): the `userConfig` schema and the `CLAUDE_PLUGIN_OPTION_<KEY>` export
- [Plugin install options](https://code.claude.com/docs/en/plugins-reference#plugin-install): the `--config` flag's reference entry
- [Plugins and skills settings](https://code.claude.com/docs/en/settings-reference#plugins-and-skills): `enabledPlugins`, `extraKnownMarketplaces`, `pluginConfigs`
- [Settings files and who they affect](https://code.claude.com/docs/en/settings#settings-files-and-who-they-affect): user vs project vs local precedence
- [Manage installed plugins](https://code.claude.com/docs/en/discover-plugins#manage-installed-plugins): enabling, disabling, `/plugin list`

<!-- END GENERATED: plugin options -->

## License

MIT (SPDX-License-Identifier: MIT).
