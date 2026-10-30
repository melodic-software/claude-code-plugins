# core

One install for the marketplace's default-on plugins. `core` has no skills, agents or hooks of its
own: its manifest lists those plugins in `dependencies`, so installing it installs and enables each
of them. `core` itself is off by default (`"defaultEnabled": false`), so taking the default-on set
never installs it; installing it is an explicit choice.

```bash
claude plugin install core@melodic-software
```

## Members

The members are the catalog's default-on set: each `.claude-plugin/marketplace.json` entry other
than `core` whose `defaultEnabled` is absent or `true`. The list is in
[`.claude-plugin/plugin.json`](.claude-plugin/plugin.json). The dependencies carry no version
constraint, so each member tracks the version the marketplace publishes.

When a plugin turns default-on or default-off, update the list in the same change:
`scripts/validate-plugin-contracts.mjs` fails when the list differs from the catalog's default-on
set, or when the `core` entry is not `"defaultEnabled": false`.

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
