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
explicit and repeatable); this doc restates it only as the reason both routes below are
consumer-run.

## The two routes

- **Interactive, any time:** `/plugin configure <plugin>@<marketplace>`.
- **Headless:** rerun the install with the new value:

  ```shell
  claude plugin install <plugin>@<marketplace> -s <scope> --config KEY=VALUE
  ```

  (`--config` repeatable per key.) Against an already-installed plugin it prints
  `already installed` **and still writes the value**. The short-circuit is about the install, not
  the config write.

## Verified-version record

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
  show that one file as both `user` and `project`. Observed on the context-budget audit
  (cwd `$HOME`). Pass `user`. This is not part of the 2026-09-27 sandbox probe.

Not covered by that probe: a `sensitive` option, a same-scope `string` rerun at `local` scope,
same-scope `boolean` or `directory` reruns at `user` or `project` scope, and uninstall dropping
the plugin's stored `pluginConfigs` entry. The uninstall caveat below is the documented install
behavior, not a 2.1.283 measurement. Re-verify before relying on a claim outside the covered
conditions, and update this section (only here) when a newer release is verified.

## Caveats every setup skill's short form carries

1. **Never uninstall to reconfigure.** Uninstalling drops the plugin's entire stored
   `pluginConfigs` entry, resetting every option in its README Options reference to its manifest
   default. Customized values are simply gone, with nothing left to read the old values from.
2. **Scope.** Pass `-s user`. `-s` places the install record and `enabledPlugins`; the option
   value always lands in user settings. Do not copy a scope from `claude plugin list`. A rerun at
   another scope adds an install record at that scope and enables the plugin there (measured in
   both directions, user over project/local and project over user). When the working directory is
   the home directory, project scope and user scope are the same settings file, so the list can
   label that one file as both `user` and `project`.
3. **Observation is next-session.** The rendered `${user_config.*}` is injected at skill load and
   each hook receives its `CLAUDE_PLUGIN_OPTION_*` from an environment fixed at session start, so
   a same-session `check` still reports the OLD value. That is not a failed write. Verify the
   effective value by rerunning the plugin's setup `check` in a **fresh session**, and never claim
   an unobserved change.
4. **Read the output, not the exit code.** A rejected value (wrong type, unknown key, empty value,
   or a value outside a declared `options` list) prints a warning and is not written, yet the
   command still exits 0.

## The short form setups print

A setup skill states, in its own words but without restating the verified-version record: the two
routes, the four caveats above, and a citation of this doc as the owner of the verification
record. Canonical citation (installed plugins cannot read this repository's working tree, so cite
the published URL):

<https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/plugin-reconfiguration/README.md>

The setup contract's other fixed step, retired-conventions detection in `check` and gated cleanup
in `apply`, is conditional on the plugin shipping `retirements.yaml`, and its canonical text lives
in the [retired-conventions convention](../retired-conventions/README.md#the-two-fixed-setup-lines).
