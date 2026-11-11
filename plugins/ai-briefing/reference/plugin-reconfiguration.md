<!-- GENERATED from docs/contracts/plugin-reconfiguration/README.md by scripts/sync-shared-copies.sh. Do not edit this copy:
edit the canonical source, then rerun the script. -->

# Plugin Reconfiguration Convention

The single owned source for how a consumer changes a plugin's native `userConfig` options after
install, the guidance every setup skill used to restate (with drift) and now cites. Setup skills
print the short form and cite this doc; the version-verification record below lives ONLY here, so
a re-verification against a newer Claude Code release is a one-file edit.

## Boundary

This doc owns the **reconfiguration routes and their caveats** for options stored in Claude Code's
native plugin configuration (`pluginConfigs`). Which options a plugin has, and what they
mean, belong to that plugin's own README Options reference. The rule that no setup skill ever
writes `pluginConfigs`, user settings, or the plugin cache is plugin-philosophy's (Setup is
explicit and repeatable); this doc restates it only as the reason every route below is
consumer-run.

## The routes

- **Interactive, any time:** `/plugin configure <plugin>@<marketplace>`.
- **Headless, preferred (Claude Code 2.1.285 or later):** save a JSON object of single-line
  strings with `claude plugin configure`, run from the project the plugin is installed in:

  ```shell
  claude plugin configure <plugin>@<marketplace> --values-stdin < values.json
  ```

  PowerShell reserves `<`, so pipe the file there instead:
  `Get-Content values.json | claude plugin configure <plugin>@<marketplace> --values-stdin`.
  `values.json` holds `{"KEY": "VALUE"}`; every value is a string, booleans included (`"true"`,
  `"false"`), and keys left out keep their saved values. Without `--values-stdin` the command
  lists each option as `set` or `not set` and prints no values; `--json` adds the option schema
  and the saved non-sensitive values. It takes only the full `name@marketplace` id, and it does
  not set a bundled MCP server's `<server>.<key>` settings
  ([plugin CLI reference § plugin configure](https://code.claude.com/docs/en/plugins/cli-reference#plugin-configure),
  as of 2026-10-28). Measured limits, in the record below: it has no scope flag, it finds only
  installs visible from the working directory, and it adds no install record and enables nothing.
- **Headless fallback (before 2.1.285, or a bundled MCP server's settings):** rerun the install
  with the new value:

  ```shell
  claude plugin install <plugin>@<marketplace> -s <scope> --config KEY=VALUE
  ```

  (`--config` repeatable per key.) The rerun is the fallback because it saves the value on an
  already-installed plugin, as the [record below](#claude-plugin-install---config-rerun) measured.
  A bundled MCP server's setting takes the key form `<server>.<key>`; the record below did not
  measure that form.

  - **Pointer**: when checking what the rerun prints for an installed plugin, or which `--config`
    key forms a release takes, fetch
    [plugin CLI reference § plugin install](https://code.claude.com/docs/en/plugins/cli-reference#plugin-install)
    live.
  - **As of**: 2026-11-03
  - **Recheck trigger**: that section changes what an install of an already-installed plugin does,
    or the `--config` key forms.

## Verified-version record

### `claude plugin configure --values-stdin`

Measured on **Claude Code 2.1.312** (sandbox probe, 2026-10-28,
[probe record](https://github.com/melodic-software/claude-code-plugins/issues/6761#issuecomment-6460407570)):

- **Non-sensitive values land in user settings.** They went to the user
  `settings.json` `pluginConfigs.<id>.options` for `project`, `local` and `user` installs.
- **The working directory picks the install.** For a `project` or `local` install, running it
  from another directory (the home directory included) printed `No installed plugin has the id`,
  exited 1 and wrote nothing. A `user` install resolved from a project directory.
- **No install side effects.** `installed_plugins.json` and every `enabledPlugins` entry stayed
  byte-identical across each write, at all three scopes.
- **Sensitive options are accepted.** On a Linux host with no OS keychain the value went to
  `~/.claude/.credentials.json` under `pluginSecrets.<id>.<key>`, never to `settings.json` or
  `~/.claude.json`. `--json` lists the key under `configured` without echoing the value.
- **Validation fails closed.** An unknown key, a value outside `options`, a non-boolean string for
  a `boolean`, a multi-line value, a non-string JSON value and non-JSON input each exited 1 with a
  message. An object with one valid and one invalid key wrote nothing.
- **Booleans are strings.** `"true"`, `"false"` (also 1/0, yes/no, on/off) were stored as JSON
  `true`/`false`.

Not covered by that probe: a host with an OS keychain (macOS, or Linux with a secret service),
which may store a sensitive value there instead; whether `""` (accepted and stored as `""`)
clears an option or sets it empty; and `number`, `directory`, `file` or `multiple` options.

### `claude plugin install --config` rerun

Measured on **Claude Code 2.1.283** (sandbox probe, 2026-09-27):

- **A same-scope rerun writes the value.** Rerun at the scope the plugin was installed at, the
  command printed `already installed` and wrote the value while the install record stayed
  byte-identical and only the named option keys changed. Measured for a `string` option at `user`
  and `project` scope, and for `boolean` and `directory` options at `local` scope.
- **A scope mismatch adds an install.** A rerun at a scope other than the installed one added an
  install record at that scope and enabled the plugin there, measured both ways: a `-s user` rerun
  of a plugin installed at `project` and `local` enabled it machine-wide, and a `-s project` rerun
  of a `user`-installed plugin added a project install record and `enabledPlugins` entry.
- **Home directory, one file, two labels.** When the working directory is the home directory,
  project scope resolves to the same settings file as user scope, so `claude plugin list` can
  show that one file as both `user` and `project`. Pass `user`. This is not part of the 2026-09-27
  sandbox probe.

Not covered by that probe: a `sensitive` option, a same-scope `string` rerun at `local` scope,
and same-scope `boolean` or `directory` reruns at `user` or `project` scope. Re-verify before
relying on a claim outside the covered conditions, and update this section (only here) when a
newer release is verified.

## Caveats every setup skill's short form carries

1. **Never uninstall to reconfigure.** Change a value through one of the routes above; an
   uninstall is not a reconfiguration route.
2. **Scope.** Run `claude plugin configure` from the project the plugin is installed in; it has no
   scope flag. For the `--config` rerun, pass the scope `claude plugin list` reports for the
   plugin: a rerun at another scope adds an install record at that scope and enables the plugin
   there (measured in both directions, user over project/local and project over user). When the
   working directory is the home directory, project scope and user scope are the same settings
   file, so the list can label that one file as both `user` and `project`: pass `user`.
3. **Observation is next-session.** A same-session `check` can still report the old value, and
   that is not a failed write. Verify the effective value by rerunning the plugin's setup `check`
   in a **fresh session**, and never claim an unobserved change.
4. **Check each route's own failure signal.** Read both the exit code and the output of the route
   that ran before reporting a value saved; the two routes do not signal a rejected value the same
   way.

- **Pointer**: when a caveat above needs the upstream specifics, fetch them live: what an
  uninstall deletes, at
  [plugin CLI reference § What an uninstall deletes and keeps](https://code.claude.com/docs/en/plugins/cli-reference#what-an-uninstall-deletes-and-keeps);
  which settings file holds a saved value and what `-s` places, at
  [plugins manifest reference § Where values are stored](https://code.claude.com/docs/en/plugins/manifest-reference#where-values-are-stored)
  and [§ plugin install](https://code.claude.com/docs/en/plugins/cli-reference#plugin-install);
  when a saved value reaches skills and hooks, at
  [plugins manifest reference § Reference a saved value](https://code.claude.com/docs/en/plugins/manifest-reference#reference-a-saved-value);
  how each route reports a rejected value, at
  [§ plugin configure](https://code.claude.com/docs/en/plugins/cli-reference#plugin-configure)
  and [§ plugin install](https://code.claude.com/docs/en/plugins/cli-reference#plugin-install).
- **As of**: 2026-11-03
- **Recheck trigger**: one of those sections changes what an uninstall deletes, where a saved value
  is stored, what `-s` places, when a saved value takes effect, or how a route reports a
  rejection.

## The short form setups print

A setup skill states the decisions in its own words: reconfigure through the native flow
(naming `/plugin configure <plugin>@<marketplace>`), never uninstall to reconfigure, never write
user settings or `pluginConfigs`, and recheck in a fresh session, reporting only an observed
value. For the headless routes and the scope and failure-signal caveats it cites
[The routes](#the-routes) and
[Caveats every setup skill's short form carries](#caveats-every-setup-skills-short-form-carries)
by heading, tells the agent to read them and print what they give (the fallback route, its
behavior on an already-installed plugin and the scope to pass included) rather than only name
them, leaving out the verified-version record, and it carries a pointer record to
[plugin CLI reference § plugin configure](https://code.claude.com/docs/en/plugins/cli-reference#plugin-configure).
It restates neither the commands' flags and version floor nor the verified-version record.
Installed plugins cannot read this repository's working tree, and an agent may have no network,
so each plugin whose setup skill cites this doc carries a generated copy at
`reference/plugin-reconfiguration.md` (registered in `scripts/shared-copies.txt`), and the skill
links that copy by a relative path such as `../../reference/plugin-reconfiguration.md#the-routes`.
Human-facing text cites the published URL:
<https://github.com/melodic-software/claude-code-plugins/blob/main/docs/contracts/plugin-reconfiguration/README.md>

The setup contract's other fixed step, retired-conventions detection in `check` and gated cleanup
in `apply`, is conditional on the plugin shipping `retirements.yaml`, and its canonical text lives
in the [retired-conventions convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/contracts/retired-conventions/README.md#the-two-fixed-setup-lines).
