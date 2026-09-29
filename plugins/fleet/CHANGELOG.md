# Changelog

All notable changes to the `fleet` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.2.0] - 2026-09-29

### Added

- `reach` covers same-machine cross-lane reach: WSL to native Windows by running `claude.exe` over
  interop, and Windows to WSL through `wsl.exe -d <distro> --exec`, with the distro read from
  `wsl.exe -l -q`. Apostrophe quoting follows the origin shell: `'\''` in bash and Git Bash,
  `''` in pwsh.
- A route matrix at the top of `reach`: every origin lane against every target lane, each row
  carrying its command shape and whether it was tested.
- A Verbs section: run a script, prompt, multi-turn (`--session-id` then `--resume`), one open
  stream-json pipe, list sessions, message a session, a named headless receiver (`-n <name>` with
  `crossSessionInbound: accept`), and background sessions (`claude --bg --name`, trusted directory
  only). Each verb is marked tested or untested. Every verb but running a script starts an agent,
  prompts under auto mode, and costs about $0.22 to $0.31 per one-line turn, so a script is
  preferred where it does the job; `--bare` cuts the cost but cannot receive messages.
- Query and wait polls `claude agents --json` or reads the receiver: `notify_when_idle` from a `-p`
  sender does not arrive before its turn ends. Remote Control stays out of headless recipes, since
  `-p --remote-control` does not connect.
- `reference/relay.md` lists the mechanisms the skill does not use (Remote Control, cloud sessions,
  Channels, the raw inbox socket, agent teams) and why, and documents the signed-out Windows lane
  check (`Failed to authenticate: OAuth session expired`, fixed by `/login` at that console), the
  receiver's nested quoting and lifetime, and a verification record for each route.
- Evals for the cross-lane routes, query and wait, the named receiver, the signed-out lane, and the
  run-a-script verb.

### Changed

- The account model is per lane, not per machine: WSL and native Windows on one machine can sign
  into different accounts, and the built-in peer tools reach only the current lane. Description,
  Boundary and README now say so, and the peer tools own same-lane messaging only.
- Commands address targets by their FLEET.md ssh alias through the Windows OpenSSH client.

## [0.1.3] - 2026-09-27

### Fixed

- `reach`'s Boundary table routes repository fleets to `repo-fleet-hygiene:audit` instead of the bare plugin name (#4119).

## [0.1.2] - 2026-09-23

### Changed

- `reach`: a one-shot remote prompt states what done looks like and what should make the remote
  turn stop and report, since nobody answers its questions.

## [0.1.1] - 2026-09-21

### Changed

- American spellings throughout this plugin's prose, ahead of the `en-us` locale the
  shared typos config adopts. Wording only: no behavior, option, default, or identifier
  changes. Released sections were corrected in place on the same terms.

## [0.1.0]

### Added

- Initial release. One skill, `reach`: run a Claude Code agent turn on another machine in the
  fleet over SSH on the tailnet.
- Target resolution from the rendered fleet manifest at `~/.config/fleet/FLEET.md`, addressing
  machines by hostname over the tailnet rather than by session name.
- Verification, one-shot and multi-turn (`--output-format json` plus `--resume`) headless recipes
  for the WSL hop, and the reason port 22 is not an agent lane. The recipes and a Gotchas entry
  carry the apostrophe rule: a `'` in `<prompt>` closes the local shell's outer single quote
  before ssh runs, so replace each `'` with `'\''` or wrap the remote command in `$'...'`.
- The Windows-side relay, in `reference/relay.md`: reaching a target's own native-Windows sessions
  through the same SSH hop, since a WSL session and a native Windows session on one computer
  cannot see each other. The relay command carries the same apostrophe rule as the hub recipes.
- The account model: why the accounts are split per machine and why that puts the built-in peer
  tools out of reach across machines.
- The permission posture: remote agent launches are outside the auto-mode classifier and prompt by
  design, with no ssh allow rule and no `bypassPermissions` on either side.
