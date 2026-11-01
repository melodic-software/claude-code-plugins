---
schema_version: "1.1"
name: motion-toast-stack
description: "Hard (toasts arrive in bursts and are usually written as restarting keyframes): a toast stack enters, restacks and is dismissed with motion that retargets, moves stacked toasts by transform, and exits faster than it entered on an accelerate curve"
tags: [web, motion, hard]
runs: 5
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "Toasts enter from the bottom edge with a short translate and fade, existing toasts shift up by transform rather than by animating layout properties, every motion uses transitions or springs that retarget from the current value instead of keyframes that restart, and a dismissed toast leaves toward its edge faster than it entered on an accelerating curve"
---

Animate the toast stack in this app. Toasts stack at the bottom right, newest at the bottom. They
often arrive three or four at once, and the user can dismiss one with its close button. I need the
enter, the restack when a toast is added or removed, and the dismissal.

```css
.toaster { position: fixed; right: 16px; bottom: 16px; }
.toast { position: absolute; right: 0; bottom: 0; width: 320px; }
```

Each toast gets `--index` (0 for the newest) and `data-state="open"` or `data-state="closing"`; the
app removes the element 300ms after it sets `closing`. This run cannot write files, so put the CSS
in your reply.
