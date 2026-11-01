---
schema_version: "1.1"
name: motion-dropdown
description: "Happy path: a dropdown's enter and exit scale in from near 0.95 out of its trigger, within the medium role, on an ease-out curve with no ease-in entrance and no transition on every property"
tags: [web, motion, happy-path]
runs: 5
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The menu fades and scales in from a scale between 0.9 and 0.97 (never 0) with its transform origin at the trigger (a fixed origin, since no component library exposes one), the entrance lasts at most 250ms on an ease-out or custom decelerating curve, the transition names its properties, and the exit lasts at most 0.8 of the entrance, the default exit_factor"
---

Add an enter and exit animation to this dropdown. The menu opens below the button, aligned to its
left edge, when the wrapper gets `data-open`.

```html
<div class="account">
  <button class="account-trigger">Options</button>
  <div class="account-menu" role="menu">
    <a role="menuitem" href="/settings">Account settings</a>
    <a role="menuitem" href="/billing">Billing</a>
    <button role="menuitem">Log out</button>
  </div>
</div>
```

```css
.account { position: relative; }
.account-menu { position: absolute; top: calc(100% + 4px); left: 0; display: none; }
.account[data-open] .account-menu { display: block; }
```

This run cannot write files, so put the CSS in your reply.
