# Command reference

Distilled from upstream `@playwright/cli@0.1.17` SKILL.md. For verbatim upstream, see `vendor/SKILL.md` beside this skill.

## Core interaction

```bash
playwright-cli open [url]               # open browser, optionally navigate
playwright-cli goto <url>               # navigate an open browser
playwright-cli click <ref> [button]     # left/right/middle click
playwright-cli dblclick <ref>
playwright-cli fill <ref> <text>        # fill an input
playwright-cli fill <ref> <text> --submit   # fill + press Enter
playwright-cli type <text>              # type into the focused element
playwright-cli press <key>              # Enter, ArrowDown, etc.
playwright-cli hover <ref>
playwright-cli select <ref> <value>     # dropdown
playwright-cli check <ref>              # checkbox/radio
playwright-cli uncheck <ref>
playwright-cli drag <fromRef> <toRef>
playwright-cli upload <file>
playwright-cli resize <w> <h>
playwright-cli close
```

On Windows, `cmd.exe` and PowerShell treat `&` as a command separator, so a `goto`/`open` URL with multiple `&`-joined query params gets truncated before it reaches `playwright-cli` unless escaped:

```powershell
playwright-cli --% goto "https://example.com/?a=1&b=2"    # PowerShell: stop-parsing token
```

```batch
playwright-cli goto "https://example.com/?a=1^&b=2"        # cmd.exe: caret-escape
```

## Snapshots & eval

```bash
playwright-cli snapshot                        # writes .playwright-cli/page-<ts>.yml
playwright-cli snapshot --filename=after-x.yaml
playwright-cli snapshot --depth=4              # limit depth for efficiency
playwright-cli snapshot e34                    # partial — one element
playwright-cli eval "document.title"           # JS on page
playwright-cli eval "el => el.id" e7           # JS on an element by ref
playwright-cli find "Sign in"                  # search a large snapshot for text, with surrounding context
playwright-cli find --regex "Sign (in|up)"
playwright-cli find --regex "/sign (in|up)/i"  # wrap in slashes for flags, e.g. case-insensitive
```

`find` is cheaper than a full `snapshot` when you only need to locate one or two elements on a large page — it returns matching nodes with a few lines of context, like `grep -C`.

See [snapshots-and-refs.md](snapshots-and-refs.md) for ref system.

## Navigation + keyboard/mouse

```bash
# History navigation (one of):
playwright-cli go-back
playwright-cli go-forward
playwright-cli reload

# Keyboard (one of):
playwright-cli press Enter
playwright-cli press ArrowDown
playwright-cli press Escape

# Hold a modifier across other commands:
playwright-cli keydown Shift && playwright-cli keyup Shift

# Mouse:
playwright-cli mousemove <x> <y>
playwright-cli mousewheel 0 100                               # scroll
```

## Save-as

```bash
playwright-cli screenshot                      # writes .playwright-cli/page-<ts>.png
playwright-cli screenshot e5                   # element-scoped
playwright-cli screenshot --filename=evidence.png
playwright-cli screenshot --hires              # higher pixel density, larger file
playwright-cli pdf --filename=page.pdf
```

## Tabs

```bash
playwright-cli tab-list
playwright-cli tab-new [url]
playwright-cli tab-close [index]
playwright-cli tab-select <index>
```

## Dialogs

```bash
playwright-cli dialog-accept ["prompt text"]
playwright-cli dialog-dismiss
```

## Raw mode — pipe into jq, diff, and similar

The global `--raw` flag strips status/code blocks from stdout and emits only the result value. Makes command output composable with Unix pipes.

```bash
playwright-cli --raw eval "JSON.stringify(performance.timing)" | jq '.loadEventEnd'
playwright-cli --raw snapshot > before.yml
playwright-cli click e5
playwright-cli --raw snapshot > after.yml
diff before.yml after.yml
TOKEN=$(playwright-cli --raw cookie-get session_id)
```

## Open parameters

```bash
playwright-cli open --browser=chrome|firefox|webkit|msedge
playwright-cli open --headed                   # visible window (default: headless)
playwright-cli open --persistent               # profile to disk (default: in-memory)
playwright-cli open --profile=/path/to/profile
playwright-cli open --config=cli.config.json
playwright-cli open --mobile                   # generic mobile device (Pixel 10 / iPhone 17); lighter pages, cheaper snapshots
playwright-cli open --device="iPhone 15"       # specific device profile
playwright-cli attach --cdp=chrome             # attach to running Chrome
playwright-cli attach --cdp=http://localhost:9222
playwright-cli attach --extension              # via Playwright MCP Bridge extension
```

See [sessions.md](sessions.md) for `-s=<name>` session isolation; [windows-quirks.md](windows-quirks.md) for `--headed` on Windows.

## Examples

**Form submission**

```bash
playwright-cli open https://example.com/form
playwright-cli snapshot
playwright-cli fill e1 "user@example.com"
playwright-cli fill e2 "password"
playwright-cli click e3
playwright-cli snapshot
playwright-cli close
```

**DevTools inspection**

```bash
playwright-cli open https://example.com
playwright-cli click e4
playwright-cli console          # list console messages
playwright-cli network          # list network requests since load
playwright-cli close
```

## Help

```bash
playwright-cli --help                     # full command list
playwright-cli --help <subcommand>        # per-command flags, e.g., --help open
playwright-cli --version
```
