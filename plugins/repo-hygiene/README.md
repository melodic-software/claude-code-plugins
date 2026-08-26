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
`git`, the optional `ghq`, and the effective destructive-guard toggle, and cleans
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
or unpushed commits **by default** (opt in with `--include-dirty`), and its skip
list is matched separator-agnostically, so a `\`-path skip entry reliably protects
a repo enumerated with `/` paths, the failure that lost an uncommitted edit in an
ad-hoc loop. A skip entry that matches nothing is reported, never silently ignored.

```shell
# Dry-run the whole ghq tree, skipping one repo (the agent shows the plan first):
ghq list -p | /repo-hygiene:clean tree-batch --repos-from - --skip melodic-software/standards
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
  `git checkout --`, and recursive `Remove-Item`; the confirmed command runs only
  through the skill's own gate. Kill switch: the `clean_destructive_guard_enabled`
  userConfig option set to `false` (`/plugin configure repo-hygiene@<marketplace>`, or
  `claude plugin install repo-hygiene@<marketplace> --config clean_destructive_guard_enabled=false`;
  user-scoped. Per-repository disable means disabling the plugin in that
  project's `enabledPlugins`).
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

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install repo-hygiene@<marketplace>
```

## Configuration

No `userConfig`. The protected-path list is enforced by the bundled bash scripts
(which do not read `CLAUDE.md`); a consumer relies on the git-tracked guarantee
and the `tree` tier's default-preserve classes to keep additional paths safe. A
declared per-consumer override for the script-enforced protected list is a known
extension point, not yet exposed as configuration.

<!-- ai-slop-ignore-start: generated options block; source is plugin.json + scripts/sync-plugin-options-docs.py -->
<!-- BEGIN GENERATED: plugin options — edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. Every option Claude Code
will prompt for when the plugin is enabled, with the environment variable each hook
reads it from.

| Option | Type | Default | Environment variable | Description |
| --- | --- | --- | --- | --- |
| `clean_destructive_guard_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_CLEAN_DESTRUCTIVE_GUARD_ENABLED` | Session-scoped PreToolUse guard blocking destructive Bash commands while the clean skill is active |

### How to set these

Three supported routes, in the order most people want them:

1. **Interactively** — Claude Code prompts for declared options when you enable the
   plugin. To change them later: `/plugin configure repo-hygiene@<marketplace>`.
2. **Headless** — repeat `--config` for each option. Replace
   `<marketplace>` with the marketplace you installed this plugin from:

   ```shell
   claude plugin install repo-hygiene@<marketplace> -s <scope> --config clean_destructive_guard_enabled=<value>
   ```

   The same command reconfigures a plugin that is **already installed**: it prints
   `already installed` and still writes the value — verified on Claude Code 2.1.240,
   for a non-sensitive option at `user` scope, by writing a non-default value to an
   installed plugin and restoring it. The short-circuit message is about the install,
   not the config write. That has not been verified for a `sensitive` option or for
   `project`/`local` scope. Do **not** `claude plugin uninstall` to
   reconfigure: uninstalling drops this plugin's whole stored `pluginConfigs` entry,
   resetting every option in the table above to its default. `-s` defaults to `user`,
   so pass the scope `claude plugin list` reports for this plugin.

   The value is stored immediately; the session you are in does not change. Hooks are
   handed their `CLAUDE_PLUGIN_OPTION_*` when the session starts, so start a fresh
   Claude Code session before expecting new behavior — a check run in the old session
   still reports the old value, and that is not a failed write.

3. **By hand, in settings** — add the value under `pluginConfigs` in your **user**
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
   only — **not** from a project's `.claude/settings.json`. To vary behavior per
   repository, enable or disable the plugin in that project's `enabledPlugins`
   instead of setting an option there.

Do not set the `CLAUDE_PLUGIN_OPTION_*` variables yourself. They are how Claude Code
hands a configured value to a hook process; the value comes from the routes above.

### Upstream documentation

- [User configuration](https://code.claude.com/docs/en/plugins-reference#user-configuration) — the `userConfig` schema and the `CLAUDE_PLUGIN_OPTION_<KEY>` export
- [Plugin install options](https://code.claude.com/docs/en/plugins-reference#plugin-install) — the `--config` flag's reference entry
- [Plugins and skills settings](https://code.claude.com/docs/en/settings-reference#plugins-and-skills) — `enabledPlugins`, `extraKnownMarketplaces`, `pluginConfigs`
- [Settings files and who they affect](https://code.claude.com/docs/en/settings#settings-files-and-who-they-affect) — user vs project vs local precedence
- [Manage installed plugins](https://code.claude.com/docs/en/discover-plugins#manage-installed-plugins) — enabling, disabling, `/plugin list`

<!-- END GENERATED: plugin options -->
<!-- ai-slop-ignore-end -->

## License

MIT (SPDX-License-Identifier: MIT).
