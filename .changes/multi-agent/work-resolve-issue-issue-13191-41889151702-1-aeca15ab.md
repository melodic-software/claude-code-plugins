---
bump: minor
---

### Changed

- The config cascade's personal layer, `.claude/multi-agent.local.yaml`, is now called the personal
  override ([#13191](https://github.com/melodic-software/claude-code-plugins/issues/13191)).
  `resolve-roles.sh` names it `personal-override` in each role's `source`, in `layers` and in
  `notes`, and `/multi-agent:setup check` prints its gitignore row as `personal-override`. A
  caller that matched the old label must match the new one.
