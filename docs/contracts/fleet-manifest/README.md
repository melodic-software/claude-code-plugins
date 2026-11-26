# fleet.json: the hosts and lanes the peer list queries

`~/.config/fleet/fleet.json` lists the machines in one person's fleet and how to reach the Claude
Code lanes on each. The fleet plugin's SessionStart peer list reads it to run
`claude agents --json` on every lane it can reach. Schema: [schema.json](schema.json) (JSON Schema
draft 2020-12). Decision: [ADR 0135](../../adr/0135-read-the-fleet-from-a-rendered-manifest-whose-contract-this-repository-owns.md).

This is not `~/.config/fleet/FLEET.md`, the prose fleet description `/fleet:reach` reads.

## Who writes and reads it

- **Writer:** the owner's own config, rendered once per lane: a WSL lane and the Windows lane on
  the same machine each get their own file, under their own home folder. No plugin writes it. A
  renderer that validates against this schema vendors `schema.json` at a named commit and records
  that commit beside the copy.
- **Reader:** the fleet plugin's peer-list hook, which reads only this path. With no file, the
  hook lists only the lane it runs on.

## Shape

The file as rendered on host-b's WSL lane:

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
        { "kind": "windows", "route": "ssh", "alias": "host-a-wsl", "claudePath": "/opt/claude/bin/claude-windows" },
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

On host-b's Windows lane, host-b's entry instead reads:

```json
{
  "key": "host-b",
  "os": "windows",
  "role": "server",
  "lanes": [
    { "kind": "windows", "route": "local", "claudePath": "C:\\Tools\\claude\\claude.exe" },
    { "kind": "wsl", "route": "wsl-exe", "distro": "Ubuntu-24.04", "claudePath": "/opt/claude/bin/claude" }
  ]
}
```

| Field | Meaning |
| --- | --- |
| `version` | Contract version, `1`. |
| `self` | `key` of the host the file was rendered on. |
| `hosts[].key` | Host name the peer list prints. |
| `hosts[].os` | `windows` (lanes of kind `wsl` and `windows`), `linux` (kind `linux`) or `macos` (kind `macos`). |
| `hosts[].role` | `client` is never queried; any other value is. |
| `lanes[].kind` | `wsl`, `windows`, `linux` or `macos`. |
| `lanes[].route` | How the reading lane reaches that lane: `local` (itself), `interop` (WSL to the same machine's Windows lane), `wsl-exe` (Windows to the same machine's WSL lane, with `distro`), `ssh` (another machine, with `alias`). Another machine's Windows lane is reached over ssh to that machine's WSL lane, which runs `claude.exe` through interop: the account ssh reaches on the Windows side need not be the one signed into Claude. |
| `lanes[].alias` | ssh host alias, resolved by the reading lane's ssh config. Required for `ssh`. |
| `lanes[].distro` | WSL distribution name. Required for `wsl-exe`. |
| `lanes[].claudePath` | Absolute path of the claude binary, as the program that runs it reads it: the reading lane for `local` and `interop` (a `/mnt/<drive>/...` path for `interop`), the target lane for `wsl-exe` (`wsl.exe --exec` runs it inside the distro) and `ssh` (the remote shell runs it; for a `windows` lane, a path on the target's WSL lane that resolves to `claude.exe`, such as a symlink, so the file names no Windows account). A drive-letter path for a `windows` lane on `local`; a `/` path everywhere else. |

The schema also holds these, which it cannot express:

- Each `hosts[].key` is unique, and `self` names one of them.
- A host has at most one lane per kind.
- The `self` host has exactly one lane with route `local`, and its kind is the reading lane's own:
  `windows` on native Windows, `wsl` inside WSL, `linux` or `macos` otherwise. That lane is the
  reader's own.

`linux` and `macos` lanes take route `local` only, so a Linux or macOS host is queried only by its
own lane; other hosts' files list it with `lanes: []`.

Every object rejects unknown properties.

## Safe sets

The reader builds every command itself, so a value that could change the command is refused, not
quoted:

- `alias` and `distro` match `^[A-Za-z0-9][A-Za-z0-9._-]*$`. `self` and `key` match the same
  set, because the peer list prints them into the session's context.
- A `/` `claudePath` holds only letters, digits and `. _ / -`. A drive-letter `claudePath` is a
  letter, `:\`, then only letters, digits and `. _ \ -`. Neither allows a space, `~`, `$`, a quote
  or a leading `-`.

Over ssh the remote shell, always a WSL lane's POSIX shell, parses the command line. A `/` path
holds no backslash, which that shell treats as an escape, and nothing it expands, so every value
reaches the remote side as one unchanged word. A drive-letter path is only ever run locally, with
no shell.

## What the reader does with a bad file

- An unparsable file, a `version` other than `1`, or a broken rule outside `lanes[]`: the reader
  ignores the file and lists only its own lane.
- A lane that breaks any lane rule (a safe set, a missing `alias` or `distro`, an unknown value or
  property): that lane is never run, and the peer list prints it as
  `not reached (unsafe manifest entry)`. The other lanes are still queried.

## Trust

The file holds no secrets and no SSH host keys. Host-key pinning stays in the ssh client's own
known-hosts configuration, and sign-in stays with ssh.

## Versioning

Any change to the fields, including a new one, raises `version` by one, since every object rejects
unknown properties.
