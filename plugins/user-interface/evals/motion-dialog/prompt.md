---
schema_version: "1.1"
name: motion-dialog
description: "Happy path: a confirm dialog and its backdrop open and close on one shared duration and easing, the dialog scales in centered from near 0.95 with no slide or bounce, closes on an accelerate curve, and under reduced motion only the fade remains"
tags: [web, motion, happy-path]
runs: 5
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The dialog fades and scales in from a scale between 0.9 and 0.97 and stays centered, never sliding in from off-screen, bouncing or starting at scale 0; closing it is a permanent exit, so the close runs on the in curve or an equivalent accelerate cubic-bezier, never the bare ease-in keyword; the backdrop uses the dialog's exact duration and easing; under prefers-reduced-motion the scale is removed and a short fade stays"
---

Animate this confirm dialog opening and closing. It is a native `<dialog>` opened with
`showModal()`, and the backdrop should animate with it.

```html
<dialog class="confirm">
  <p>Delete this project? This can't be undone.</p>
  <form method="dialog">
    <button value="cancel">Cancel</button>
    <button value="delete">Delete</button>
  </form>
</dialog>
```

This run cannot write files, so put the CSS in your reply.
