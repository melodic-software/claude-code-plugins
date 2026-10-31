# The control panel

A switcher answers "which direction"; the panel answers "which value". Add it whenever the brief
contains a number you'd otherwise pick for the user: duration, easing, spring bounce, stagger,
blur, radius, spacing, opacity, scale, offset. Every one of those is a decision that hasn't been
made yet. Hardcode it and the user gets one guess and has to prompt you again to see the next; put
it on a slider and they settle it in ten seconds with their eyes.

Why it pays: binding a variable such as an X offset to a slider lets the person try variations of
an interaction just by dragging it, which shortens the feedback loop and speeds up iteration.

## What goes on the panel

- **Every number the variant would shrug at.** If you found yourself typing `200ms` because it
  seemed about right, that's a slider.
- **Ranges wide enough to be wrong.** A duration slider that stops at 300ms hides the fact that
  400ms is too slow. Bracket the plausible answer on both sides.
- **Easing as a curve, not a text field.** A bezier or spring editor if the tooling has one,
  otherwise a select of the project's named easing curves (the motion tokens
  `/user-interface:write-animation` builds from).
- **A speed multiplier on anything that moves**: 1x, 0.5x, 0.25x. Most motion problems are
  invisible at full speed and obvious at a quarter of it. Implement it as a multiplier on the
  duration so the curve is the same shape, just stretched.
- **Nothing else.** A panel with twenty controls is a second interface to learn. If a value isn't
  in question, leave it in the code.

[DialKit](https://github.com/joshpuckett/dialkit) is the default panel in a React project; its
README lists the controls it ships. Plain `<input type="range">` is fine everywhere else. Don't build a custom panel.

## Two implementation rules

**1. In a DOM or CSS prototype, controls write to CSS variables, not React state.**

```jsx
<div
  ref={root}
  style={{ "--duration": `${duration * speed}ms`, "--ease": ease, "--blur": `${blur}px` }}
>
```

A slider that re-renders the whole tree on every input stutters, and the user reads that stutter
as the animation feeling bad, then spends ten minutes fixing an animation that was fine all along.
Outside React, set them imperatively on the prototype root:

```js
root.style.setProperty('--duration', `${value}ms`);
```

A canvas generator has no CSS to bind: each control change re-renders the canvas from the current
values.

**2. The number is visible, and copyable.**

Show each control's current value next to it, and give the panel a button that copies the whole
config:

```text
duration: 180ms · ease: cubic-bezier(0.32, 0.72, 0, 1) · scale: 0.96
```

A slider on its own gives a feeling. The number is what survives the prototype getting deleted,
and it's what the recorded answer (the discipline's "When done") is written from.

## Placement

Top-right, fixed, clear of the switcher's bottom-center bar when the prototype has one. Give it the
same posture as the switcher: harness chrome, not part of the design being judged; neutral,
unbranded, no project tokens. If a variant occupies the top-right (a toast stack, a menu), move the
panel to top-left rather than shrinking it.

## Replay

When the prototype carries the variant switcher, it already ships a replay button (`R`) that
re-mounts the current variant. Don't build a second one in the panel. Changing a control re-applies
the value live; re-triggering the entrance is the switcher's job.
