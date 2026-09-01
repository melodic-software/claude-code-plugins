# Plugin Reconfiguration Convention

The single owned source for how a consumer changes a plugin's native `userConfig` options after
install — the guidance every setup skill used to restate (with drift) and now cites. Setup skills
print the short form and cite this doc; the version-verification record below lives ONLY here, so
a re-verification against a newer Claude Code release is a one-file edit.

## Boundary

This doc owns the **reconfiguration routes and their caveats** for options stored in Claude Code's
native plugin-configuration surface (`pluginConfigs`). Which options a plugin has, and what they
mean, belong to that plugin's own README Options reference. The rule that no setup skill ever
writes `pluginConfigs`, user settings, or the plugin cache is PLUGIN-PHILOSOPHY's (Setup is
explicit and repeatable); this doc restates it only as the reason both routes below are
consumer-run.

## The two routes

- **Interactive, any time:** `/plugin configure <plugin>@<marketplace>`.
- **Headless:** rerun the install with the new value:

  ```shell
  claude plugin install <plugin>@<marketplace> -s <scope> --config KEY=VALUE
  ```

  (`--config` repeatable per key.) Against an already-installed plugin it prints
  `already installed` **and still writes the value** — the short-circuit is about the install, not
  the config write.

## Verified-version record

The `already installed`-still-writes claim was verified on **Claude Code 2.1.240**: a
non-sensitive option at `user` scope — a non-default value written to an installed plugin, then
restored. Not covered: a `sensitive` option, and `project`/`local` scope. Re-verify before relying
on the claim outside the covered conditions, and update this section (only here) when a newer
release is verified.

## Caveats every setup skill's short form carries

1. **Never uninstall to reconfigure.** Uninstalling drops the plugin's entire stored
   `pluginConfigs` entry, resetting every option in its README Options reference to its manifest
   default — customized values are simply gone, with nothing left to read the old values from.
2. **Scope.** `-s` defaults to `user`; pass the scope `claude plugin list` reports for the plugin,
   and run from that project's directory for a `project`/`local` scope, or the write lands at a
   scope that does not load.
3. **Observation is next-session.** The rendered `${user_config.*}` is injected at skill load and
   each hook receives its `CLAUDE_PLUGIN_OPTION_*` from an environment fixed at session start, so
   a same-session `check` still reports the OLD value — that is not a failed write. Verify the
   effective value by rerunning the plugin's setup `check` in a **fresh session**, and never claim
   an unobserved change.

## The short form setups print

A setup skill states, in its own words but without restating the verified-version record: the two
routes, the three caveats above, and a citation of this doc as the owner of the verification
record. Canonical citation (installed plugins cannot read this repository's working tree, so cite
the published URL):

<https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/plugin-reconfiguration/README.md>

The setup contract's other fixed step — retired-conventions detection in `check` and gated cleanup
in `apply` — is conditional on the plugin shipping `retirements.yaml`, and its canonical text lives
in the [retired-conventions convention](../retired-conventions/README.md#the-two-fixed-setup-lines).
