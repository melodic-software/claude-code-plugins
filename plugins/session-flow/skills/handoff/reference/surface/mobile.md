# Handoff on the mobile surface

Read only when the `surface` probe resolves `mobile`. The output order and every other rule in
`SKILL.md` hold; this file changes only how the parts are drawn. The phone gives each list item a
large gap and cuts code blocks at about 38 characters, so the panel and checklist share two lines
and the prompt's prose wraps.

- **Prompt**: `save_point.py emit --format mobile` (or `amend --format mobile`), pasted verbatim
  ([engine doc, "Markdown surfaces"](../../../../reference/save-point.md#markdown-surfaces)). On the
  prompt-only path, each region prints as a fenced `text` block under the markdown copy lines,
  its prose lines wrapped to 38 characters by the same rule, the `@` path, any URL and each
  remaining-work line kept whole.
- **Position panel**: one line, `**Step <n> of <total>: <current unit>.** <done> done, <blocked>
  blocked (<unit>, <reason>).`, no list. A rail that would not resolve says so in that line; the
  completeness count, its unverified share and the three blocks follow as one short line each.
- **Enforcement checklist**: on the line under the panel, `Checklist <ticked>/<total> pass`, then
  ` · ` and each box not ticked and each `validate` WARN or FAIL line, joined by ` · `, never a
  list.
