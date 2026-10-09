# bash-format

A Claude Code plugin that lints and formats shell scripts the moment you edit
them. On every `Write` or `Edit` of a `.sh` or `.bash` file it runs
[ShellCheck](https://www.shellcheck.net/) and (opt-in)
[shfmt](https://github.com/mvdan/sh), surfacing findings back to Claude as
advisory context.

It uses **your repository's own configuration**, `.shellcheckrc` for linting
and `.editorconfig` for formatting. It ships no rules of its own.

## Behavior

- **Spawned only for shell files.** The hook is registered with the `if` filters
  `Edit(*.sh)` and `Edit(*.bash)`, so a Write/Edit of any other file never starts a
  hook process for it; the extension check inside the script is unchanged.
- **Lint on edit (always).** ShellCheck (`warning` severity and above) runs on
  every edit. It is non-mutating; it only reports.
- **Format on edit (opt-in).** `shfmt` runs **only when an `.editorconfig`
  section names shell files**: a shell glob such as `[*.sh]`, `[*.bash]`, or
  `[*.{sh,bash}]` (including path-prefixed forms like `[**/*.sh]`), found by
  walking up from the file to the repository root. A bare `[*]` catch-all is
  **not** an opt-in: most repos only set line-ending / charset properties there,
  and treating that as a format gate would rewrite shell files to shfmt's
  built-in defaults. A repo whose `.editorconfig` only configures other
  languages (or has none) likewise leaves shell files untouched. Path-only
  sections like `[scripts/**]` are also excluded; use an explicit shell glob.
  It runs with no parser/printer flags, so your `.editorconfig` is authoritative,
  and with `--apply-ignore` so an `ignore = true` section (e.g. for generated or
  vendored scripts) is honored even on a single edited file.
- **Pre-existing drift is left alone.** shfmt runs only when the file was already
  shfmt-clean under your `.editorconfig` before the edit: the hook checks the
  pre-edit bytes (the Write/Edit `tool_response.originalFile`) with
  `shfmt -d --filename`. A file that drifted from your style, for example
  flush-left `case` arms written before `switch_case_indent = true` was added,
  keeps its existing layout, so a small edit stays a small diff. A new file is
  formatted. The check costs one `jq` and one `shfmt` on an edit to an existing
  file under the opt-in.
- **A rewrite that would change an array subscript is put back.** shfmt parses an
  unquoted subscript as arithmetic and spaces it, because it cannot know the
  array is associative, so `${m[a-b]}` would become the different key
  `${m[a - b]}` (see the Caveats section of the
  [mvdan/sh README](https://github.com/mvdan/sh#caveats) and
  [mvdan/sh#956](https://github.com/mvdan/sh/issues/956); checked 2026-10-04 against
  shfmt v3.14.1; recheck when a shfmt release changes how it reads subscripts). When
  shfmt rewrites the file, the hook compares every subscript's source text before
  and after, including the blanks inside the brackets, since `${m[ key ]}` is a
  different key from the `${m[key]}` shfmt prints. If any differs, the hook
  restores the file byte for byte and names each changed subscript and its line in
  one notice to Claude. Quote the key (`${m["a-b"]}`) if the array is associative; if it is
  indexed, write it as shfmt prints it, which depends on the release: v3.13.0
  printed `${a[i+1]}` where the releases around it print `${a[i + 1]}` (reverted in
  v3.13.1, per the [mvdan/sh changelog](https://github.com/mvdan/sh/blob/master/CHANGELOG.md)).
  To keep a file's keys unquoted, give it an `ignore = true` section in
  `.editorconfig`; the hook passes `--apply-ignore` (shfmt 3.8+), so shfmt leaves
  the file alone. The hook reads the syntax tree with `--to-json`, or with
  `-tojson` on a shfmt older than 3.8, since 3.4 and 3.5 have no `--to-json`. When
  the tree cannot be read, the rewrite is put back and the notice says so, because
  an unchecked rewrite may have changed a key. A file shfmt leaves unchanged reads
  no tree and costs no extra process.
- **Advisory, never blocking.** The hook always exits `0`. Findings are reported
  via `additionalContext`; they never reject the edit. Make a commit hook or CI
  your hard gate. A finding set is reported once per file: an unchanged set on a
  re-edit sends nothing, and it is sent again after a clean run or after the
  context is compacted or cleared.
- **Config from the consumer.** ShellCheck discovers `.shellcheckrc` by walking
  up from the file's directory; shfmt reads `.editorconfig` the same way. No
  working-directory assumptions. The tools are anchored to the edited file.
- **Gitignored files are skipped by default.** A file the repository gitignores is not
  linted or rewritten, silently (no notice), since a rewrite of an ignored file has no git
  checkout to undo it. Set `bash_format_lint_gitignored` to `true` to act on them too. A
  tracked file that matches an ignore pattern stays in scope, and when git cannot decide
  (absent, no repository, an error) the hook acts as before.
- **Scope: files inside the current project, when `CLAUDE_PROJECT_DIR` is set.**
  With `CLAUDE_PROJECT_DIR` set, the hook acts only on shell files under it
  (symlink-resolved): a `.sh`/`.bash` file written *outside* the project, e.g. to
  a temp or scratchpad directory, is silently skipped (no lint, no format, no
  notice), deliberate defense-in-depth scoping inherited from the shared hook
  library. The OS temp tree (`TMPDIR`/`TMP`/`TEMP` and the POSIX defaults) is
  outside the project even when it sits *under* `CLAUDE_PROJECT_DIR`, the shape a
  home-directory project dir takes, where Claude Code's own session scratchpad
  would otherwise prefix-match as project content. The one exception is a project
  root that itself lives under temp (a fixture checkout built with `mktemp -d`),
  whose files are project content. Membership recognizes Windows 8.3 short-name
  spellings (`KYLESE~1`) of in-project paths, a per-volume concern: only volumes
  with 8.3 generation enabled produce such paths. If `CLAUDE_PROJECT_DIR` is **unset** (e.g. some
  headless `-p` sessions), the membership check is skipped and any existing edited
  file is processed. Either way, to lint a file the hook skipped, run `shellcheck`
  on it directly.

## Requirements

Each missing-tool notice appears once per session and agent; the `shellcheck` and `shfmt` notices carry
the install route on your copy only.

- **Bash.** The hook is a Bash script. On native Windows, install
  [Git for Windows](https://code.claude.com/docs/en/setup#set-up-on-windows) so
  Claude Code can run it under Git Bash.
- **Node.js** on `PATH`. Every hook row runs through `node hooks/exec-bash.mjs`, so
  without `node` the hook does not launch and shell edits are neither linted nor formatted.
  Claude Code's native installer does not ship or use Node.js; only its npm package needs it
  ([setup docs](https://code.claude.com/docs/en/setup), checked 2026-09-29; recheck when a
  Claude Code release note changes the installer or its runtime requirements). Unlike the tool
  notices below, a missing `node` shows no notice from this plugin. Check it with
  `/bash-format:setup check`. [Install Node.js](https://nodejs.org/en/download).
- **jq** on `PATH`. Parses the hook payload. Absent: the hook skips with a
  visible notice. [Install jq](https://jqlang.org/download/).
- **ShellCheck** on `PATH` for the lint pass. Absent: the lint pass skips with
  a visible notice.
- **shfmt** on `PATH` for the format pass (and an `.editorconfig` in your repo
  to opt in). Absent while the repo opts in: the format pass skips with a
  visible notice. Without the `.editorconfig` opt-in the
  format pass stays quiet. The repo chose not to format.

A SessionStart probe reports a missing `shfmt` or `shellcheck` once per session, from
`prerequisites.json`, and the PostToolUse notices name the same install route. The probe and the
PostToolUse notice for a tool share one latch: the probe's notice is yours, and Claude hears at the
hook's first skip. Run `/bash-format:check` to see which
binaries resolve; it is read-only and installs nothing.

Each pass is independent: when a tool is absent its pass is skipped (visibly)
and the other still runs.

The hook itself runs on Bash 3.2+. Telemetry timing uses `EPOCHREALTIME`
(Bash 5.0+); on older bash the telemetry envelope is skipped while linting and
formatting still run.

### Hook budget accounting

Per [`docs/conventions/hook-budget/README.md`](../../docs/conventions/hook-budget/README.md),
this hook is always-on for every `Write` and `Edit` of a `.sh` or `.bash` file (every handler in
`hooks/hooks.json` carries one of the two `if` rows, which keep every other extension from
spawning it, and the suite pins the whole handler set to the script's own extension set), so its
cost on a clean shell file is the figure that counts. Measured on Linux x86_64 under bash 5.2 in
a container with `HOOK_TELEMETRY_SINK` and `CLAUDE_PROJECT_DIR` unset, twelve interleaved trials
against an interleaved `bash -c :` floor S of about 4 ms, with a kernel census from
`strace -f -e trace=clone,clone3,fork,vfork,execve` (2026-09-07, 0.7.44):

| Event | Fires | Wall | Spawn-equivalents | Kernel census |
| --- | --- | --- | --- | --- |
| PostToolUse `Write`, clean `.sh`, no `.editorconfig` shell section | 1 | 45 ms | 10.5 | 14 process creations, 6 execs: `shellcheck`, two `git rev-parse` (the working-tree probe and the root resolver), `jq`, `realpath`, the hook's own `bash` |
| PostToolUse `Write`, clean `.sh`, `.editorconfig` `[*.sh]` present | 1 | 55 ms | 14.1 | 31 to 32 process creations (the tools' own threads vary), 12 execs: the row above plus two `shfmt` and the disclosure snapshot's `mktemp`, `cp`, `cmp`, `rm` |
| PostToolUse `Write`, `.sh` that shfmt rewrites, `.editorconfig` `[*.sh]` present | 1 | about 7.5 ms more than the same rewrite on 0.10.3 (see below) | about 11 more, at that run's S of 0.7 ms | the census of a rewrite on 0.10.3 plus two `shfmt` and two `jq`: the subscript guard reads the syntax tree before and after |
| PostToolUse `Write`, any other extension | 0 | none | 0 | no process; the `if` rows drop the handler before a spawn |

At a 4 ms floor the spawn-equivalent column mostly measures the tools' own run time rather
than spawns, so the census column is the number that transfers to the Windows 11 Git Bash
reference host the convention calls binding; that host's figure for this plugin has not been
taken. The residual is ShellCheck and shfmt themselves plus the shared library's payload reader
(`jq`), working-tree probe and root resolver (`git` twice, `realpath`) and the disclosure
snapshot.

The rewrite row comes from a separate run (2026-10-04, 0.10.4, Linux x86_64, bash 5.2, shfmt
v3.12.0): 41 interleaved trials of the 0.10.3 and 0.10.4 hooks on the same fixture, repeated
three times, with medians 7.0 to 7.9 ms apart. The census is
`strace -f -e trace=execve`. A clean file measured the same on both versions, so the two
clean-file rows stand.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install bash-format@<marketplace>
```

Then verify prerequisites with `/bash-format:setup check`.

## Configuration

The linting and formatting rules come from the `.shellcheckrc` and
`.editorconfig` already in your repository, which the plugin reads automatically.
To change the rules, edit those files.

Two `userConfig` options tune the hook itself:

| Option | Default | Effect |
|--------|---------|--------|
| `bash_format_enabled` | `true` | Toggle for the bash-format hook; set `false` for a clean no-op. |
| `bash_format_lint_gitignored` | `false` | Set `true` to lint and format files the repository gitignores; by default the hook skips them. |

Set it interactively with `/plugin configure bash-format@<marketplace>`, or headless on the
install command:

```shell
claude plugin install bash-format@<marketplace> --config bash_format_enabled=false
```

<!-- BEGIN GENERATED: plugin options. Edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. Every option Claude Code
will prompt for when the plugin is enabled, with the environment variable each hook
reads it from.

| Option | Type | Default | Environment variable | Description |
| --- | --- | --- | --- | --- |
| `bash_format_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_BASH_FORMAT_ENABLED` | Lint and format shell scripts on edit via ShellCheck + shfmt |
| `bash_format_lint_gitignored` | boolean | `false` | `CLAUDE_PLUGIN_OPTION_BASH_FORMAT_LINT_GITIGNORED` | By default the hook leaves a file the repository gitignores alone: it is not rewritten or linted, since a rewrite of an ignored file has no git checkout to undo it. Set true to act on gitignored files too. A tracked file that matches an ignore pattern is always in scope. |

### How to set these

Three supported routes, in the order most people want them:

1. **Interactively.** Claude Code prompts for declared options when you enable the
   plugin. To change them later: `/plugin configure bash-format@<marketplace>`.
2. **Headless.** Repeat `--config` for each option. Replace
   `<marketplace>` with the marketplace you installed this plugin from:

   ```shell
   claude plugin install bash-format@<marketplace> -s <scope> --config bash_format_enabled=<value>
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
       "bash-format@<marketplace>": {
         "options": {
           "bash_format_enabled": <value>
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

- [User configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration): the `userConfig` schema and the `CLAUDE_PLUGIN_OPTION_<KEY>` export
- [Plugin install options](https://code.claude.com/docs/en/plugins/cli-reference#plugin-install): the `--config` flag's reference entry
- [Plugins and skills settings](https://code.claude.com/docs/en/settings-reference#plugins-and-skills): `enabledPlugins`, `extraKnownMarketplaces`, `pluginConfigs`
- [Settings files and who they affect](https://code.claude.com/docs/en/settings#settings-files-and-who-they-affect): user vs project vs local precedence
- [Manage installed plugins](https://code.claude.com/docs/en/plugins/install#manage-installed-plugins): enabling, disabling, `/plugin list`

<!-- END GENERATED: plugin options -->

## License

MIT (SPDX-License-Identifier: MIT).
