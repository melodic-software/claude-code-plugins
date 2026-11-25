# Fleet manifest: the hosts and lanes the peer list queries

`~/.config/fleet/fleet.json` lists the machines in one person's fleet and how to reach the Claude
Code lanes on each. The fleet plugin's SessionStart peer list reads it to run
`claude agents --json` on every lane. Schema: [schema.json](schema.json) (JSON Schema draft
2020-12). Decision: [ADR 0135](../../adr/0135-read-the-fleet-from-a-rendered-manifest-whose-contract-this-repository-owns.md).

## Who writes and reads it

- **Writer:** the owner's own config, rendered once per lane (a WSL lane and the Windows lane on
  the same machine each get their own file, under their own home folder). No plugin writes it.
- **Reader:** the fleet plugin's peer-list hook, which reads only this path. With no file, the
  hook lists only the lane it runs on.

## Shape

```json
{
  "version": 1,
  "self": "host-b",
  "hosts": [
    {
      "key": "host-a",
      "os": "windows",
      "role": "server",
      "lanes": [
        { "kind": "windows", "route": "ssh", "alias": "host-a", "claudePath": "C:\\Tools\\claude\\claude.exe" },
        { "kind": "wsl", "route": "ssh", "alias": "host-a-wsl", "claudePath": "/opt/claude/bin/claude" }
      ]
    },
    {
      "key": "host-b",
      "os": "windows",
      "role": "server",
      "lanes": [
        { "kind": "wsl", "route": "local", "claudePath": "/opt/claude/bin/claude" },
        { "kind": "windows", "route": "interop", "claudePath": "/mnt/c/Tools/claude/claude.exe" }
      ]
    },
    { "key": "host-c", "os": "linux", "role": "client", "lanes": [] }
  ]
}
```

This is the file as rendered on host-b's WSL lane.

| Field | Meaning |
| --- | --- |
| `version` | Contract version, `1`. |
| `self` | `key` of the host the file was rendered on. The reader finds its own lane by `self` plus its own kind. |
| `hosts[].key` | Host name the peer list prints. |
| `hosts[].os` | `windows`, `linux` or `macos`. |
| `hosts[].role` | `client` is never queried; any other value is. |
| `lanes[].kind` | `wsl`, `windows`, `linux` or `macos`. |
| `lanes[].route` | How this lane reaches that lane: `local` (the same lane), `interop` (WSL to Windows on the same machine), `wsl-exe` (Windows to WSL on the same machine, with `distro`), `ssh` (another machine, with `alias`). |
| `lanes[].alias` | ssh host alias, resolved by the reader's ssh config. Required for `ssh`. |
| `lanes[].distro` | WSL distribution name. Required for `wsl-exe`. |
| `lanes[].claudePath` | Absolute path of the claude binary, as seen from the reading lane for `local`, `interop` and `wsl-exe`, and from the remote lane for `ssh`. |

Every object rejects unknown properties. `linux` and `macos` lanes take route `local` or `ssh`.

## Safe sets

The reader builds every command itself, so a value that could change the command is refused, not
quoted:

- `self`, `key`, `alias` and `distro` match `^[A-Za-z0-9][A-Za-z0-9._-]*$`.
- `claudePath` starts with `/` or a drive letter and `:\`, and holds only letters, digits and
  `. _ / \ : -`: no space, no `~`, no leading `-`.

Over ssh the remote login shell parses the command line, so these sets keep each value one word
with nothing for that shell to expand. A lane whose value fails its set is never run; the peer
list prints it as `not reached (unsafe manifest entry)`.

## Trust

The file holds no secrets and no SSH host keys. Host-key pinning stays in the ssh client's own
known-hosts configuration, and sign-in stays with ssh.

## Versioning

A reader that finds a `version` it does not know, or a file it cannot parse, ignores the file and
lists only its own lane. Any change to a field's name, meaning or allowed values raises `version`
by one.
