# Chat surface: mobile

Read only when `lib/chat-surface.sh` prints `mobile`. These rules change how output is drawn on the
Claude phone app, never what it says; a skill's own `reference/chat-surface/mobile.md` adds shapes
only that skill prints.

- Fenced blocks: wrap prose lines at 38 characters. Keep a path, URL, session id or command line
  whole on its own line.
- Lists: plain lines instead of a bulleted list when items are short; the app draws a large gap
  between list items.
- Commands longer than a few words go in a fenced block, not inline code, which wraps mid-command.
- No raw HTML or collapsible blocks: the app shows them as tags.
- Tables: at most three short columns; otherwise one plain line per row.
