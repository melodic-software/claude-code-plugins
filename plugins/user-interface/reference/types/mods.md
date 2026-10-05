# Claude Code mods: bands, status lines, toasts, log lines, panes

A mod draws inside Claude Code's own interface, in the terminal and the Desktop app, which do not
offer all the same surfaces. Everything in
`terminal.md` applies; this file adds what a shared screen needs. Anthropic owns the surfaces and
their limits: read the interface page for what each one is and where it renders, and load the
built-in `plugin-authoring` skill before writing one. How this repository packages a mod is
`docs/conventions/mod-authoring/README.md` in the marketplace repository.

- **Pointer**: <https://code.claude.com/docs/en/plugins/mods/interface>
- **As of**: 2026-10-04
- **Recheck trigger**: the interface page adds, removes or renames a render surface, or changes
  which surfaces the Desktop app draws.

## Pick the surface by the kind of message

| The message is | Use | Not |
|---|---|---|
| State the user glances at while working (a level, a zone, a count) | the status line or the above-prompt band | a toast that repeats on every change |
| A one-off event the user should notice now | a toast | a band row that stays after the event is over |
| History the user may scroll back to | a transcript log line | a band or toast, which do not keep history |
| Detail the user opens on purpose | a pane | an always-visible band |

Use one surface per message. A state shown in the band is not repeated as a toast.

## A shared screen

Every enabled plugin may draw on the same band and status line, so each mod draws as little as it
can.

- **Rows.** One band row per mod by default; a second only while something needs action.
- **Width.** Fit the narrowest terminal the user is likely to run. Put the deciding word first and
  truncate the rest, so the line still reads when cut.
- **Label.** Start with the plugin's short name, so the user can tell whose row it is.
- **Color.** Named theme colors only, color on the status word only, and the status also in words,
  per the terminal rules. Do not color a row just to stand out among other plugins.
- **Quiet by default.** Show nothing while all is well, unless the user asked to see a steady state.
- **Off switch.** Every element can be hidden or turned off through the plugin's options, and the
  row or log line names how.

## Wording

- A log line states the event and the action taken, past tense: `guard: blocked rm -rf on /`.
- A toast says what happened and what to do, in one line: `context at 80%: /compact or /clear`.
- Commands a user can run appear exactly as typed, so they can be copied.
