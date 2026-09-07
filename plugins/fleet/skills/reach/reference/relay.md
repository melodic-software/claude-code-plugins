# The Windows-side relay

Read this when the ask needs the TARGET's own live sessions: listing them, messaging one, or
waiting for a reply. For a plain agent turn on another machine, the hub's one-shot and multi-turn
recipes are enough and this file is unnecessary.

## Why a relay is needed at all

A headless turn over port 2222 lands inside the WSL distro. A WSL session and a native Windows
session on the same computer register under different home directories and listen on different
socket types, so neither appears in the other's listing. The desktop's real sessions, including the
one the Remote Control logon task runs, are all on the Windows side. A WSL-side turn therefore
reports an empty or WSL-only peer list, which looks like a permissions problem and is not.

The relay closes that gap by starting a turn on the target's Windows side, through the SSH hop you
already have. That turn runs as the target's Windows console account, so its peer tools are
same-account and behave normally.

## The command

```console
ssh -p 2222 <wsl-user>@<host> 'cd /mnt/c/Users/<user>/claude-lane-sandbox && /mnt/c/Users/<user>/.local/bin/claude.exe -p "<prompt>" < /dev/null'
```

Three parts, each load-bearing:

- **Absolute paths.** WSL interop answers by absolute path inside an sshd session even though
  `$WSL_INTEROP` is unset there. Do not probe with `cmd.exe /c`, which prints nothing in that
  session and reads as "interop is broken" when it is not.
- **The working directory.** The target's Remote Control task runs from a scratch checkout under
  the console account's profile, and the relay turn uses the same directory. Never point it at a
  repository that defines the fleet's accounts, firewall scope or tailnet policy.
- **`< /dev/null`.** Same reason as every other headless turn: `claude -p` reads stdin.

`~/.config/fleet/FLEET.md` renders this with the target's real profile path substituted, so prefer
copying it from there over expanding `<user>` by hand.

## Verbs

| Ask | Prompt to give the relay turn |
|---|---|
| List | `List the sessions you can reach` |
| Send | `Send <text> to the session named <name>` |
| Wait for a reply | Ask the turn to wait for the peer to go idle before returning |

Session names are the target's, not yours. List first, then send to a name from that list rather
than a name you assumed.

## Getting a reply back

The relay turn is a single headless turn: it returns when it is done, and a peer's answer that
arrives later is not in its output. Two options:

- Ask the relay turn itself to wait for the peer to finish before returning, so the answer is in
  the same output.
- Make a second relay turn that lists the sessions again, or resumes the first turn by its
  `session_id`, and reads what came back.

Both cost a second SSH round trip. Prefer the first when the peer's answer is the whole point.

## What the relay does not change

- It does not merge accounts. The relay turn is same-account with the target's sessions because it
  IS on the target, under the target's account. Nothing about it makes this machine's account able
  to see them.
- It does not bypass permissions. It starts an agent on another machine, so it prompts under auto
  mode like any other turn here, and neither side runs `bypassPermissions`.
- It does not make port 22 usable for agent work. That hop is a different Windows account with no
  Claude sign-in, and the relay deliberately goes through 2222 to land as the console account.

## Noise in the output

The relay session's `SessionEnd` hooks print `Hook cancelled` on stdout. It is cosmetic. When the
turn ran with `--output-format json`, extract the JSON object before parsing, for example
`grep '^{' | jq -r .session_id`, rather than handing the whole stream to a parser.
