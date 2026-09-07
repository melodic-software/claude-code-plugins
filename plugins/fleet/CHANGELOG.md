# Changelog

All notable changes to the `fleet` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.1.0]

### Added

- Initial release. One skill, `reach`: run a Claude Code agent turn on another machine in the
  fleet over SSH on the tailnet.
- Target resolution from the rendered fleet manifest at `~/.config/fleet/FLEET.md`, addressing
  machines by hostname over the tailnet rather than by session name.
- Verification, one-shot and multi-turn (`--output-format json` plus `--resume`) headless recipes
  for the WSL hop, and the reason port 22 is not an agent lane.
- The Windows-side relay, in `reference/relay.md`: reaching a target's own native-Windows sessions
  through the same SSH hop, since a WSL session and a native Windows session on one computer
  cannot see each other.
- The account model: why the accounts are split per machine and why that puts the built-in peer
  tools out of reach across machines.
- The permission posture: remote agent launches are outside the auto-mode classifier and prompt by
  design, with no ssh allow rule and no `bypassPermissions` on either side.
