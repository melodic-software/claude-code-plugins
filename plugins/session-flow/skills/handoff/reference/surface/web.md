# Handoff on the web surface

Read only when the `surface` probe resolves `web`. The output order and every other rule in
`SKILL.md` hold; this file changes only how the parts are drawn.

- **Prompt**: `save_point.py emit --format markdown` (or `amend --format markdown`), pasted
  verbatim ([engine doc, "Markdown surfaces"](../../../../reference/save-point.md#markdown-surfaces)).
  On the prompt-only path, each region prints as a fenced `text` block under the same copy lines.
- **Position panel**: a numbered list, one unit per item: ✅ for `[x]`, ▶ and bold with
  `← you are here` for the current unit, ⬜ for pending, ⛔ for blocked. The completeness line and
  the three blocks follow, and every other panel rule holds.
- **Enforcement checklist**: one line, `Checklist: <ticked>/<total> pass`, then each box not ticked
  and each `validate` WARN or FAIL line as one bullet, never a `- [x]` list, which the app draws
  struck through.
