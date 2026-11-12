# bash-format

A Claude Code plugin that formats shell scripts with [shfmt](https://github.com/mvdan/sh) and
checks them with [ShellCheck](https://www.shellcheck.net/) in two places: shfmt once per batch of
tool calls in a Claude Code session, and shfmt plus ShellCheck again at git pre-commit for every
author. ShellCheck findings are reported by the pre-commit entry, on the lines the commit adds; they
no longer reach Claude on each edit.

It uses **your repository's own configuration**, `.shellcheckrc` for linting and `.editorconfig`
for formatting. It ships no rules of its own.

## Behavior

- **One format run per batch, silent.** A `PostToolBatch` row runs after the tool calls of a turn
  step resolve. It takes the `.sh` and `.bash` files that `Write`, `Edit` or `MultiEdit` calls in
  the batch named, and runs shfmt once over each. It prints nothing and exits `0`: no finding and no
  notice goes to Claude or the user. A file that `Read` named is never rewritten.
  - The row has no matcher or `if` (neither applies to `PostToolBatch`). Its launcher skips the
    script unless the payload holds a string ending in `sh` (which both extensions do), so a batch
    without a shell file costs one `node` process.
  - **Pointer**: when deciding what filters a `PostToolBatch` row, fetch
    [hooks: PostToolBatch](https://code.claude.com/docs/en/hooks#posttoolbatch) live.
- **Format is opt-in.** shfmt runs **only when an `.editorconfig` section names shell files**: a
  shell glob such as `[*.sh]`, `[*.bash]`, or `[*.{sh,bash}]` (including path-prefixed forms like
  `[**/*.sh]`), found by walking up from the file to the repository root. A bare `[*]` catch-all is
  **not** an opt-in: most repos only set line-ending / charset properties there, and treating that
  as a format gate would rewrite shell files to shfmt's built-in defaults. A repo whose
  `.editorconfig` only configures other languages (or has none) likewise leaves shell files
  untouched. Path-only sections like `[scripts/**]` are also excluded; use an explicit shell glob.
  shfmt runs with no parser/printer flags and with `--apply-ignore`, so your `.editorconfig`
  sets the style and an `ignore = true` section (e.g. for generated or vendored scripts) excludes
  a file. For what each does, see the DESCRIPTION section and the `--apply-ignore` entry of the
  [shfmt manual page](https://github.com/mvdan/sh/blob/master/cmd/shfmt/shfmt.1.scd), which the
  [mvdan/sh README: shfmt](https://github.com/mvdan/sh#shfmt) section links.
- **Pre-existing drift is rewritten whole.** The batch payload carries no pre-edit bytes, so a file
  that already drifted from your style is formatted in full, as the pre-commit entry would.
- **A rewrite that would change an array subscript is put back.** shfmt parses an unquoted
  subscript as arithmetic and spaces it, because it cannot know the array is associative, so
  `${m[a-b]}` would become the different key `${m[a - b]}` (see the Caveats section of the
  [mvdan/sh README](https://github.com/mvdan/sh#caveats) and
  [mvdan/sh#956](https://github.com/mvdan/sh/issues/956); checked 2026-10-04 against shfmt
  v3.14.1; recheck when a shfmt release changes how it reads subscripts). When shfmt rewrites the
  file, both passes compare every subscript's source text before and after, including the blanks
  inside the brackets, since `${m[ key ]}` is a different key from the `${m[key]}` shfmt prints. If
  any differs, the file is restored byte for byte. The pre-commit entry names each changed
  subscript and its line on stderr; the batch row stays silent. Quote the key (`${m["a-b"]}`) if
  the array is associative; if it is indexed, write it as shfmt prints it, which depends on the
  release: v3.13.0 printed `${a[i+1]}` where the releases around it print `${a[i + 1]}` (reverted
  in v3.13.1, per the [mvdan/sh changelog](https://github.com/mvdan/sh/blob/master/CHANGELOG.md)).
  To keep a file's keys unquoted, give it an `ignore = true` section in `.editorconfig`. The tree is
  read with `--to-json`, or with `-tojson` on a shfmt older than 3.8, since 3.4 and 3.5 have no
  `--to-json`. When the tree cannot be read, the rewrite is put back, because an unchecked rewrite
  may have changed a key. A file shfmt leaves unchanged reads no tree and costs no extra process.
- **Config from the consumer.** Both tools read their configuration from your repository:
  `.shellcheckrc` for ShellCheck and `.editorconfig` for shfmt. For how each file is found, see
  [ShellCheck manual: RC FILES](https://github.com/koalaman/shellcheck/blob/master/shellcheck.1.md#rc-files)
  and the shfmt manual page linked above. Files under `.githooks/` (installed copies) are skipped.
- **Gitignored files are skipped by default in the session.** The batch row does not rewrite a file
  the repository gitignores, silently, since a rewrite of an ignored file has no git checkout to
  undo it. Set `bash_format_lint_gitignored` to `true` to act on them too. A tracked file that
  matches an ignore pattern stays in scope, and when git cannot decide (absent, no repository, an
  error) the hook acts as before.
- **Scope: files inside the current project, when `CLAUDE_PROJECT_DIR` is set.** With
  `CLAUDE_PROJECT_DIR` set, the batch row acts only on shell files under it (symlink-resolved): a
  `.sh`/`.bash` file written *outside* the project, e.g. to a temp or scratchpad directory, is
  silently skipped, deliberate defense-in-depth scoping inherited from the shared hook library. The
  OS temp tree (`TMPDIR`/`TMP`/`TEMP` and the POSIX defaults) is outside the project even when it
  sits *under* `CLAUDE_PROJECT_DIR`, the shape a home-directory project dir takes, where Claude
  Code's own session scratchpad would otherwise prefix-match as project content. The one exception
  is a project root that itself lives under temp (a fixture checkout built with `mktemp -d`), whose
  files are project content. Membership recognizes Windows 8.3 short-name spellings
  (`KYLESE~1`) of in-project paths, a per-volume concern: only volumes with 8.3 generation enabled
  produce such paths. If `CLAUDE_PROJECT_DIR` is **unset** (e.g. some headless `-p` sessions), the
  membership check is skipped and any existing edited file is processed.

## Git pre-commit entry

The plugin ships one git-hook entry, `shell-check` (`git-hooks/entries.json`), which rewrites. At
commit it refuses a partly staged shell script that an `.editorconfig` section governs, untouched;
runs shfmt over the staged `.sh` and `.bash` files that section governs and re-stages what
changed; then runs ShellCheck (`warning` severity and above) over the staged shell files and blocks
the commit only on a finding on a line the commit adds, printed as `<path>:<line>: <message>`. A
script no section governs is never rewritten but is still checked. It reaches every author, not only
Claude, once `/bash-format:setup apply install-git-hooks [scope=local|shared]` registers it with
the repository's hook manager (lefthook, husky or plain git hooks). Local scope stays in this
clone; shared scope commits the copy under `.githooks/bash-format/`. `/bash-format:setup check`
reports drift, and the SessionStart probe prints one line when the entry is missing, stale or
edited.

When a tool is missing, an agent's commit fails with the install route; a person's commit gets a
one-line notice and goes through. A skipped or missing tool drops only its own half (no shfmt: no
rewrite; no ShellCheck: no findings). `git -c checks.skipmissing=shellcheck commit ...` skips the
check while the tool is absent. The placement rules are the check-placement convention in the
marketplace repository.

An opt-in Stop row (`bash_format_end_of_turn`) runs the ShellCheck half over the uncommitted changes
at the end of a turn, without rewriting, and hands findings back to Claude once per turn.

## Requirements

- **Bash.** The hook scripts are Bash scripts, and run on Bash 3.2+. On native Windows, install
  [Git for Windows](https://code.claude.com/docs/en/setup#set-up-on-windows) so Claude Code can
  run them under Git Bash.
- **Node.js** on `PATH`. Every hook row runs through `node hooks/exec-bash.mjs`, so without `node`
  the hook does not launch and shell edits are not formatted. We do not assume a Claude Code
  install brings Node. Pointer: when deciding whether it does, fetch
  [setup: Install with npm](https://code.claude.com/docs/en/setup#install-with-npm) and
  [System requirements](https://code.claude.com/docs/en/setup#system-requirements) live. A missing `node` shows no notice from this plugin. Check it with
  `/bash-format:setup check`. [Install Node.js](https://nodejs.org/en/download).
- **jq** on `PATH`. Reads the file paths from the `PostToolBatch` payload and the syntax tree for
  the subscript guard. Absent: the batch row does nothing, the pre-commit entry skips its rewrite,
  and the SessionStart probe reports it. [Install jq](https://jqlang.org/download/).
- **ShellCheck** on `PATH` for the pre-commit findings.
- **shfmt** on `PATH` for formatting (and an `.editorconfig` section naming shell files in your
  repo to opt in). Without the opt-in, shfmt is never needed. The repo chose not to format.

A SessionStart probe reports a missing `shfmt` or `shellcheck` once per session, from
`prerequisites.json`, and a drifted git-hook entry. Run `node "<plugin root>/lib/prerequisites.mjs" check "<plugin root>"`
to see which binaries resolve; it is read-only and installs nothing.

### Hook budget accounting

Per [`docs/contracts/hook-budget/README.md`](../../docs/contracts/hook-budget/README.md),
the `PostToolBatch` row is always-on: the event has no matcher, so it fires on every batch of every
session. Its launcher flag `--skip-unless-stdin-contains 'sh"'` closes before bash starts when the
payload holds no string ending in `sh`. Measured on WSL2 Ubuntu (bash 5.3.9, shfmt v3.14.1,
node 24) on 2026-10-15, with the row launched as `hooks.json` registers it, ten fires per case;
spawns are from `scripts/hook-census.sh`:

| Batch | Median wall | Min-max | Spawns |
| --- | --- | --- | --- |
| No shell file in the payload | 0.068 s | 0.060-0.087 s | 1 (the `node` launcher) |
| A `Read` of a `.sh` file, nothing to rewrite | 0.065 s | 0.058-0.086 s | 6 |
| One `Edit` of a `.sh` file that needs a rewrite | 0.098 s | 0.089-0.122 s | 23 |

The ceiling for a per-batch formatter row is 1 s median per fire. Fences:
`.performance/ratchets.json` holds the no-shell-file row at 1 spawn, and the Stop row with
`bash_format_end_of_turn` off (its default) at 1 spawn.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install bash-format@melodic-software
```

Then verify prerequisites with `/bash-format:setup check`.

## Configuration

The linting and formatting rules come from the `.shellcheckrc` and
`.editorconfig` already in your repository, which the plugin reads automatically.
To change the rules, edit those files.

Three `userConfig` options tune the hooks themselves:

| Option | Default | Effect |
|--------|---------|--------|
| `bash_format_enabled` | `true` | Kill switch. Set `false` for a clean no-op. |
| `bash_format_lint_gitignored` | `false` | Set `true` to format files the repository gitignores; by default the batch row skips them. |
| `bash_format_end_of_turn` | `false` | Set `true` to run the pre-commit ShellCheck pass over the uncommitted changes when a turn ends; findings go back to Claude once per turn so they are fixed before it stops. Nothing is rewritten. |

Set them interactively with `/plugin configure bash-format@<marketplace>`, or headless on the
install command:

```shell
claude plugin install bash-format@<marketplace> --config bash_format_enabled=false
```

<!-- BEGIN GENERATED: plugin options. Edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. For how Claude Code asks for
these and hands them to the plugin, see [User configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration).

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `bash_format_enabled` | boolean | `true` | After each batch of tool calls, run shfmt over the shell scripts it wrote, where the repository's .editorconfig opts in |
| `bash_format_lint_gitignored` | boolean | `false` | By default the hook leaves a file the repository gitignores alone: it is not rewritten or linted, since a rewrite of an ignored file has no git checkout to undo it. Set true to act on gitignored files too. A tracked file that matches an ignore pattern is always in scope. |
| `bash_format_end_of_turn` | boolean | `false` | At the end of each turn, run the pre-commit ShellCheck pass over the lines changed since the last commit and hand any findings back so they are fixed before the turn ends, at most once per turn. Nothing is rewritten. Off by default. |

### How to set these

Set the options above for `bash-format@<marketplace>`, replacing `<marketplace>` with the
marketplace you installed this plugin from:

- **In a session or headless:** [`/plugin` in a session](https://code.claude.com/docs/en/plugins/cli-reference#plugin-in-a-session) or
  [`claude plugin configure`](https://code.claude.com/docs/en/plugins/cli-reference#plugin-configure). The configure command is the preferred
  headless route in the [plugin-reconfiguration convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/contracts/plugin-reconfiguration/README.md), which records its limits.
- **By hand:** under [`pluginConfigs`](https://code.claude.com/docs/en/settings-reference#pluginconfigs) in your **user** settings.

Do **not** uninstall the plugin to reconfigure it: see [What an uninstall deletes and keeps](https://code.claude.com/docs/en/plugins/cli-reference#what-an-uninstall-deletes-and-keeps).
For a Claude Code release without `plugin configure`, see [Plugin install](https://code.claude.com/docs/en/plugins/cli-reference#plugin-install).

### Upstream documentation

- [User configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration)
- [Plugin configure](https://code.claude.com/docs/en/plugins/cli-reference#plugin-configure)
- [Plugin install options](https://code.claude.com/docs/en/plugins/cli-reference#plugin-install)
- [Plugins and skills settings](https://code.claude.com/docs/en/settings-reference#plugins-and-skills)
- [Settings files and who they affect](https://code.claude.com/docs/en/settings#settings-files-and-who-they-affect)
- [Manage installed plugins](https://code.claude.com/docs/en/plugins/install#manage-installed-plugins)

<!-- END GENERATED: plugin options -->

## License

MIT (SPDX-License-Identifier: MIT).
