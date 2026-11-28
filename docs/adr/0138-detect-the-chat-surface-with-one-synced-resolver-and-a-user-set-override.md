# Detect the chat surface with one synced resolver and a user-set override

- Status: accepted
- Date: 2026-11-28
- Related: [`lib/chat-surface.sh`](../../lib/chat-surface.sh) (the resolver);
  [`lib/chat-surface/mobile.md`](../../lib/chat-surface/mobile.md) (the shared phone rules);
  [shared copies](../../scripts/shared-copies.txt) (where each copy is registered)

## Context

Skills print tables, fenced blocks, box art and pasted script output shaped for a terminal. On the
Claude phone app the same output breaks: code blocks cut at about 38 characters, list items get
large gaps, inline code wraps mid-command, and raw HTML shows as tags. A session can be read in a
terminal, the Desktop app, a browser or the phone, and a local terminal session can be mirrored to
the phone by [Remote Control](https://code.claude.com/docs/en/remote-control), whose docs name no
variable for the viewing client. Cloud sessions set `CLAUDE_CODE_REMOTE=true`, and the entrypoint
variable records the device a cloud session was started from (`remote_mobile` observed).

## Decision

- One resolver, `lib/chat-surface.sh` with its data file `lib/chat-surface.env`, synced into each
  consuming plugin, prints exactly one of `terminal`, `desktop`, `web`, `mobile` and always exits 0.
- Order: an explicit request in the session, then the `CHAT_SURFACE` environment variable when it
  holds one of the four values, then detection; anything unreadable is `terminal`, and a mirrored
  terminal session stays `terminal`.
- `CHAT_SURFACE` and its four values are a user-facing contract: people set them in their own
  settings, so renaming either breaks those settings.
- A visual skill runs the resolver as a body step and, on anything but `terminal`, reads its
  plugin's `reference/chat-surface/<value>.md` and its own spoke of the same name. Nothing loads at
  session start and nothing on the terminal.

## Alternatives considered

- **(a) A `chat_surface` setting in every plugin.** One key per plugin, so the same preference is
  set many times. Not chosen.
- **(b) A team convention file.** A checked-in value forces one person's device on a whole team,
  against consumer-agnostic plugins. Not chosen.
- **(c) Inject the rules at session start.** Loads in every session, needed or not, and reaches only
  consumers who install the injecting plugin. Not chosen.
- **(d) A node resolver.** A plain skill run may not have node. Not chosen.
- **(e) A pre-computed injected line.** A failing injected command aborts the skill. Not chosen.

## Consequences

- Each plugin that adopts the resolver registers its copies in `scripts/shared-copies.txt`.
- Web and Desktop rules files are added by their own passes; until then those surfaces read none.
- Recheck when Claude Code documents a variable naming the viewing client, or changes the
  entrypoint values.
