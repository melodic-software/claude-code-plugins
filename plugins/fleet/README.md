# fleet

A Claude Code plugin for agent-to-agent reach across the machines you own. One skill, one job: from
Claude Code on any host and platform, get work to happen on any other, with no human copying prompts
between terminals.

| Skill | What it does |
|---|---|
| `/fleet:reach` | Resolve a target host and platform from the fleet manifest, then run a script, prompt, query and wait, message a session, or start a named session there: the other platform on this machine (WSL or native Windows) or either platform on another machine |

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install fleet@melodic-software
```

## Why not the peer tools

A **host** is one machine you own. A **platform** is where Claude Code runs on a host: a WSL distro
or native Windows (windows, wsl, linux or macos in general). Each platform on each host is one Claude
Code install with its own sign-in. When each signs into its own Claude account, which keeps one
platform's usage limits off another's, the built-in peer tools see only their own host and platform:

- WSL and native Windows on one machine register sessions under different homes and sockets, so
  neither lists the other.
- Remote Control lists only the signed-in account's sessions, so another account's sessions never
  appear, even with Remote Control connected.

What works is starting a headless `claude -p` turn on the target platform: over WSL interop for
native Windows on this machine, `wsl.exe` for WSL on this machine, and SSH for another machine. That
turn runs under the target platform's own account, config and limits, and its peer tools are local
there, so it can list and message the target's sessions.

```shell
/fleet:reach          # resolve a target, then compose the route for it
/fleet:reach relay    # the per-route detail: hops, named receiver, replies, verification
```

## What it expects

A rendered fleet manifest at `~/.config/fleet/FLEET.md` naming each host's reach paths: ssh alias,
port, account and shell. The skill reads it before composing anything, and treats a host that is
absent from it as not a fleet host. Machines are addressed by hostname over the tailnet, never by
session name.

## Peer list at session start

A SessionStart hook adds the live Claude Code sessions on every fleet lane to the session's
context on startup, resume, `/clear`, compaction and fork, at no model-turn cost. It reads
`~/.config/fleet/fleet.json` (contract: [fleet-manifest](../../docs/contracts/fleet-manifest/README.md))
and runs each lane's `claude agents --json`: on this lane directly, through WSL interop or
`wsl.exe -d <distro> --exec`, or over ssh in batch mode with strict host keys and no forwarding (from WSL, the Windows OpenSSH
client, since the distro holds no fleet key).
It starts no local shell and runs no other program itself; ssh still follows your ssh config.

- The list opens with a line saying it is data, that same-lane peers take SendMessage by name and
  other lanes take `/fleet:reach`; it is at most 25 lines.
- With no live peer and no broken lane it prints nothing.
- A session that is not attended (`claude -p`, `--bg`, the SDK) lists only its own lane, as does
  a timeout of 0. With no `fleet.json` it lists only its own lane, through the binary that started
  the session.
- A lane that cannot be reached prints `not reached: <host> <OS> (<reason>)`: always for a broken
  lane (name lookup failed, sign-in expired, claude not found, unsafe manifest entry), and only
  inside a printed list for one that is away (timed out, no route, refused, distro stopped).

To see what the hook would print, run it yourself; `--manifest <file>` reads another manifest:

```shell
node <plugin root>/hooks/peer-list.mjs --preview [--manifest <file>]
```

## Posture

Starting an agent on another host or platform is a state change nobody is watching, so it is outside the
auto-mode classifier and prompts by design. The reach skill requests no tool grants and never
proposes an ssh allow rule to quiet the prompt. The peer-list hook runs without a prompt because it
only reads: each lane's `claude agents --json`, with names and paths from `fleet.json` that pass a
safe-character check.

## Boundaries

`repo-fleet-hygiene` also says "fleet" and means fleets of REPOSITORIES. Different subject, no
overlap. Messaging a session on the same host and platform belongs to the built-in peer tools. Delegation inside
one session belongs to subagents and `session-flow:orchestrate`; a detached session on this platform
belongs to `session-flow:continue-in-background`. Interactive human use of a platform's session, from a
phone or the web, is the built-in Remote Control feature, under that platform's own account.

<!-- BEGIN GENERATED: plugin options. Edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. For how Claude Code asks for
these and hands them to the plugin, see [User configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration).

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `converge_docs_url` | string | *(none)* | URL of your own documentation for the fleet-converge command, which reach names when converging dotfiles comes up. Unset: reach names the command with no link. |
| `peer_query_timeout_seconds` | number<br>*min 0, max 10* | `3` | Seconds the session-start peer list waits for each fleet lane's claude agents --json, from 0 to 10. 0 lists only the lane the session runs on. Empty or out of range: 3. |

### How to set these

Set the options above for `fleet@<marketplace>`, replacing `<marketplace>` with the
marketplace you installed this plugin from:

- **In a session or headless:** [`/plugin` in a session](https://code.claude.com/docs/en/plugins/cli-reference#plugin-in-a-session) or
  [`claude plugin configure`](https://code.claude.com/docs/en/plugins/cli-reference#plugin-configure). The configure command is the preferred
  headless route in the [plugin-reconfiguration convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/contracts/plugin-reconfiguration/README.md), which records its limits.
- **By hand:** under [`pluginConfigs`](https://code.claude.com/docs/en/settings-reference#pluginconfigs) in your **user** settings.

Do **not** uninstall the plugin to reconfigure it: see [What an uninstall deletes and keeps](https://code.claude.com/docs/en/plugins/cli-reference#what-an-uninstall-deletes-and-keeps).
For a Claude Code release without `plugin configure`, see [Plugin install](https://code.claude.com/docs/en/plugins/cli-reference#plugin-install).

### Upstream documentation

- [User configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration)
- [Plugin configure](https://code.claude.com/docs/en/plugins/cli-reference#plugin-configure)
- [Plugin install options](https://code.claude.com/docs/en/plugins/cli-reference#plugin-install)
- [Plugins and skills settings](https://code.claude.com/docs/en/settings-reference#plugins-and-skills)
- [Settings files and who they affect](https://code.claude.com/docs/en/settings#settings-files-and-who-they-affect)
- [Manage installed plugins](https://code.claude.com/docs/en/plugins/install#manage-installed-plugins)

<!-- END GENERATED: plugin options -->
