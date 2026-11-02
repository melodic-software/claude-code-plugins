# Resolve `medium` first

On the HTML mockup substrate, resolve the `rendered-views` preference (`auto`, `terminal`, `file`,
`artifact`, `hosted`) before the design-canvas offer. A `--medium` argument naming one decides; it
is not part of the scope. Otherwise read whichever layers exist, in order: user-global
`~/.claude/rendered-views.md`, team `<root>/.claude/rendered-views.md`, overlay
`<root>/.claude/rendered-views.local.md`. `<root>` is `${CLAUDE_PROJECT_DIR}` when set, else
`git rev-parse --show-toplevel`; outside a work tree, read only the user-global layer. The last
layer that sets `medium` wins. Count the overlay only when `git ls-files` does not list it and
`git check-ignore` matches it; otherwise report it and ignore it. This plugin has no `medium`
option, so no rung sits between the argument and the layers. `auto`, an empty value or no value
leaves the shipped default, the mockup plus the offer; any other value is reported and read as
`auto`.

- `terminal` or `file` keeps the run on this machine: build the mockup and make no design-canvas
  offer, since the canvas is published. Under `terminal`, say the mockup is still a local file
  because a layout is judged by looking at it.
- `artifact` or `hosted` keeps the shipped default: this skill publishes nothing itself.

Name the source of `medium` in the handover: the argument, the layer's path, or "shipped default".
