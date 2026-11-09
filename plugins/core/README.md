# core

One install for the vital lifecycle plugins, from planning a change through its pull request and
the session handoff, plus the `guardrails` safety hooks, for a setup that does not already enable
them. `core` has no skills, agents or hooks of its own: its manifest lists those plugins in
`dependencies`, so installing it installs and enables each of them. `core` itself is off by default
(`"defaultEnabled": false`), so taking the default-on set never installs it; installing it is an
explicit choice.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install core@melodic-software
```

## Members

| Member | Lifecycle step |
|---|---|
| `planning` | brief, plan and design |
| `discovery` | explore the code and research outside it |
| `verification` | prove a change achieved its outcome |
| `toolchain` | build, test and lint the changed files |
| `review` | quality gate and review agents |
| `source-control` | commits and pull requests |
| `session-flow` | handoff and resume |
| `work-items` | track, claim and work tracker items |
| `guardrails` | guard hooks that block secret leaks and destructive commands at every step |

The list is in [`.claude-plugin/plugin.json`](.claude-plugin/plugin.json). The dependencies carry
no version constraint, so each member tracks the version the marketplace publishes.

Every member is also in the catalog's default-on set, the
`.claude-plugin/marketplace.json` entries whose `defaultEnabled` is absent or `true`; most
default-on plugins are not members. `scripts/validate-plugin-contracts.mjs` fails when a member is
missing from the catalog or set `"defaultEnabled": false`, or when the `core` entry is not
`"defaultEnabled": false`.

No member declares a dependency on another member, so each member also installs and loads on its
own.

## Turning a member off

`core` needs every member enabled:

- Disabling a member while `core` is enabled is refused, with a command that disables both in
  order.
- A member turned off another way, such as `false` in a settings file, keeps `core` disabled with a
  `Dependency "<name>" is disabled` error until the member is enabled again.
- Uninstalling `core` leaves the members installed. `claude plugin prune` then removes the members
  `core` installed that no other plugin needs; a member you installed yourself stays.

To run without a member, disable `core` and keep the members you want.

- **Pointer**: [Plugins with dependencies](https://code.claude.com/docs/en/plugins/install#plugins-with-dependencies),
  [Dependency errors](https://code.claude.com/docs/en/plugins/troubleshooting#dependency-errors),
  [plugin prune](https://code.claude.com/docs/en/plugins/cli-reference#plugin-prune) and
  [Bundle plugins for a team](https://code.claude.com/docs/en/plugins/dependencies#bundle-plugins-for-a-team).
  **As of**: 2026-10-27. **Recheck trigger**: those sections change what install, disable,
  uninstall or prune does to a plugin's dependencies.
