# Peer-list fixtures

Outputs of the programs `peer-list.mjs` runs, which `peer-list.test.mjs` feeds to its parser and
failure classifier. User names, host names, folders, session names and session ids are replaced
with placeholders; everything else is byte for byte what the program printed.

## WSL command reference

Read 2026-11-25. Microsoft's
[Basic commands for WSL](https://learn.microsoft.com/en-us/windows/wsl/basic-commands#list-installed-linux-distributions)
page (updated 2026-06-02) documents the list options:

> Additional options that can be used with the list command include: `--all` to list all
> distributions, `--running` to list only distributions that are currently running, or `--quiet`
> to only show distribution names.

That page and
[Working across file systems](https://learn.microsoft.com/en-us/windows/wsl/filesystems#run-linux-tools-from-a-windows-command-line)
do not document `--exec`. The tool's own usage text does, from `wsl.exe --help` on WSL 2.7.14.0
(Windows 10.0.26300.9974):

```text
Usage: wsl.exe [Argument] [Options...] [CommandLine]

Arguments for running Linux binaries:

    If no command line is provided, wsl.exe launches the default shell.

    --exec, -e <CommandLine>
        Execute the specified command without using the default Linux shell.

    --
        Pass the remaining command line as-is.

Options:
    --distribution, -d <DistroName>
        Run the specified distribution.

    --list, -l [Options]
        Lists distributions.

        Options:
            --running
                List only distributions that are currently running.

            --quiet, -q
                Only show distribution names.
```

## Files

Claude Code 2.1.331, OpenSSH 10.2p1, WSL 2.7.14.0, captured 2026-11-25 on a WSL lane.

| File | Source | Command |
| --- | --- | --- |
| `agents-interactive.json` | captured | `claude agents --json` on a WSL lane with five interactive sessions; one row carries `waitingFor`, a property the parser does not read |
| `agents-background.json` | hand-built: no background session was running | a `background` row and an interactive row without `status`, in the captured rows' field set |
| `agents-injection.json` | hand-built | rows whose name holds a newline, ANSI escapes and 500 characters, whose kind is outside the allowlist, and whose status holds a newline |
| `transport.json` | per record, in its `source` field | each record names its command, exit code or spawn error, and the raw stdout and stderr bytes in base64 |

`transport.json` records:

- `ssh-name-lookup`, `ssh-refused` (`-p 1` to localhost), `ssh-timeout` (TEST-NET address with
  `ConnectTimeout=1`), `ssh-host-key-unknown` (localhost, absent from known hosts): the peer
  list's hardened ssh option list, captured.
- `ssh-permission-denied`: captured against localhost with a throwaway known-hosts file and no key,
  so the server refuses the sign-in.
- `remote-shell-missing-binary`: the command line a remote login shell runs, captured locally
  through `/usr/bin/bash -c`, since no reachable ssh host was available to run a missing path.
- `wsl-exe-missing-binary`, `wsl-exe-unknown-distro`, `wsl-list-running-quiet`: `wsl.exe` run from
  WSL through interop, captured. `wsl.exe`'s own messages and its list output are UTF-16LE; a
  Linux program's output it relays is that program's own bytes.
- `local-missing-binary`, `ssh-missing-transport`: a spawn of an absent file, which fails with
  `ENOENT` before any output.
- `ssh-no-route`: hand-built in the OpenSSH message format of `ssh-refused` and `ssh-timeout`.

No fixture covers an expired Claude sign-in: no documented message was found, and an unknown
message classifies as `unexpected output`, which prints the same way.
