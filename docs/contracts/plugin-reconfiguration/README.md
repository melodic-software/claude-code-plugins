# Plugin Reconfiguration Convention

The single owned source for how a consumer changes a plugin's native `userConfig` options after
install, the guidance every setup skill used to restate (with drift) and now cites. Setup skills
print the short form and cite this doc; the version-verification record below lives ONLY here, so
a re-verification against a newer Claude Code release is a one-file edit.

## Boundary

This doc owns the **reconfiguration routes and their caveats** for options stored in Claude Code's
native plugin-configuration surface (`pluginConfigs`). Which options a plugin has, and what they
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

  (`--config` repeatable per key.) Against an already-installed plugin it prints
  `already installed` **and still writes the value**. The short-circuit is about the install, not
  the config write. A bundled MCP server's setting takes the key form `<server>.<key>`, which
  needs Claude Code 2.1.285 or later; the record below did not measure that form.

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
- **Uninstall drops the values.** `claude plugin uninstall` removed the plugin's `pluginConfigs`
  entry and its `pluginSecrets` entry.

Not covered by that probe: a host with an OS keychain (macOS, or Linux with a secret service),
which may store a sensitive value there instead; whether `""` (accepted and stored as `""`)
clears an option or sets it empty; and `number`, `directory`, `file` or `multiple` options.

### `claude plugin install --config` rerun

Measured on **Claude Code 2.1.283** (sandbox probe, 2026-09-27):

- **A same-scope rerun writes the value.** Rerun at the scope the plugin was installed at, the
  command printed `already installed` and wrote the value while the install record stayed
  byte-identical and only the named option keys changed. Measured for a `string` option at `user`
  and `project` scope, and for `boolean` and `directory` options at `local` scope.
- **The value always lands in user settings.** `--config` wrote `pluginConfigs` to the user
  `settings.json` whatever `-s` said, measured on first installs at `project` and `local` scope;
  `-s` governed only the install record and the `enabledPlugins` entry in that scope's settings
  file.
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

1. **Never uninstall to reconfigure.** Uninstalling drops the plugin's stored `pluginConfigs`
   entry and its stored sensitive values, resetting every option in its README Options reference
   to its manifest default. Customized values are simply gone, with nothing left to read the old
   values from.
2. **Scope.** A non-sensitive value always lands in user settings, whichever route writes it.
   Run `claude plugin configure` from the project the plugin is installed in; it has no scope flag.
   For the `--config` rerun, pass the scope `claude plugin list` reports for the plugin: `-s`
   places the install record and `enabledPlugins`, and a rerun at another scope adds an install
   record at that scope and enables the plugin there (measured in both directions, user over
   project/local and project over user). When the working directory is the home directory,
   project scope and user scope are the same settings file, so the list can label that one file
   as both `user` and `project`: pass `user`.
3. **Observation is next-session.** The rendered `${user_config.*}` is injected at skill load and
   each hook receives its `CLAUDE_PLUGIN_OPTION_*` from an environment fixed at session start, so
   a same-session `check` still reports the OLD value. That is not a failed write. Verify the
   effective value by rerunning the plugin's setup `check` in a **fresh session**, and never claim
   an unobserved change.
4. **Check each route's own failure signal.** `claude plugin configure --values-stdin` rejects a
   bad value with exit 1 and saves nothing, but it accepts an empty string and stores `""`. The
   `--config` rerun prints a warning for a rejected value (wrong type, unknown key, empty value,
   or a value outside a declared `options` list) and does not write it, yet still exits 0, so
   read its output, not the exit code.

## The short form setups print

A setup skill states, in its own words but without restating the verified-version record: the
routes, preferred headless route first, the four caveats above, and a citation of this doc as the
owner of the verification record. Canonical citation (installed plugins cannot read this
repository's working tree, so cite the published URL):

<https://github.com/melodic-software/claude-code-plugins/blob/main/docs/contracts/plugin-reconfiguration/README.md>

The setup contract's other fixed step, retired-conventions detection in `check` and gated cleanup
in `apply`, is conditional on the plugin shipping `retirements.yaml`, and its canonical text lives
in the [retired-conventions convention](../retired-conventions/README.md#the-two-fixed-setup-lines).
