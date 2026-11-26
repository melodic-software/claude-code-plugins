# Read the fleet from a rendered manifest whose contract this repository owns

- Status: accepted
- Date: 2026-11-25
- Related: [fleet-manifest contract](../contracts/fleet-manifest/README.md);
  [issue #19069](https://github.com/melodic-software/claude-code-plugins/issues/19069)

## Context

The fleet plugin's SessionStart peer list runs `claude agents --json` on every Claude Code lane in
the owner's fleet it can reach, unprompted, before the first prompt. It needs each lane's route, ssh alias, WSL
distribution and claude binary path in a form a hook can read without a model. The owner's fleet
data lives in their dotfiles, which also hold SSH host keys, user names and provisioning details the
hook has no use for. `/fleet:reach` reads the fleet from prose written for a model. The plugin is
public and consumer-agnostic, so it may carry no one person's topology.

## Decision

1. **The hook reads one file, `~/.config/fleet/fleet.json`**, a projection holding only what the
   hook acts on: `version`, `self`, and `hosts[]` of `{ key, os, role, lanes[] }`, each lane
   `{ kind, route, alias?, distro?, claudePath }`. The owner's config renders it once per lane.
2. **This repository owns the contract** in `docs/contracts/fleet-manifest/` (README and JSON
   Schema). The renderer validates against a vendored copy of the schema; the reader checks
   `version` first, and an unknown version or unparsable file means the hook lists only its own
   lane.
3. **Every value the hook puts in a command passes a safe set**: names match
   `^[A-Za-z0-9][A-Za-z0-9._-]*$`; `claudePath` is a `/` path with no backslash, or, for a Windows
   lane run locally, a drive-letter path; neither allows a space, `~`, `$`, a quote or a leading
   `-`. Over ssh the remote shell parses the command line, so the safe sets keep each value one
   word that shell leaves unchanged. Another machine's Windows lane is reached through that
   machine's WSL lane, which runs `claude.exe` through a path on that lane, such as a symlink, so the
   file names no Windows account: the Windows ssh account is a local admin with no Claude sign-in,
   and this way every ssh hop lands in a POSIX shell. A lane that fails is never run; any other broken
   rule makes the hook ignore the file.
4. **The file carries no secrets and no SSH host keys.** Host-key pinning stays in the ssh client's
   known-hosts configuration.

## Alternatives considered

- **(a) Read the dotfiles' fleet data directly.** The hook would parse YAML in a format the
  dotfiles repository owns and may change, and would load host keys and account details it never
  uses. Not chosen.
- **(b) Read the fleet prose `/fleet:reach` uses.** It is written for a model, so a hook would parse
  free text whose wording changes without a version. Not chosen.
- **(c) A plugin option holding the lanes.** One machine-wide option cannot differ per lane, and
  listing every host there duplicates data the owner already keeps in the dotfiles. Not chosen.

## Consequences

- A field change bumps `version`, and the renderer and reader move together across two
  repositories.
- With no manifest the peer list covers only the lane it runs on.
