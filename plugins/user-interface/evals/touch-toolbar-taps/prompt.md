---
schema_version: "1.1"
name: touch-toolbar-taps
description: "Hard (the prompt names symptoms, not fixes): Written from MB:plugins/user-interface/reference/types/touch-web.md:20-21 and MB:plugins/user-interface/reference/types/touch-web.md:32-33. The tap highlight is removed only with a pressed state on every tappable element, controls that never zoom are marked with touch-action, and each target meets the WCAG 2.5.8 minimum with spacing. Head raises the target to 44px, which passes the 24px floor graded here. The prompt's complaint that every tap flashes a gray box asks for the highlight to go in both versions, so the grader fails a reply that leaves it on; both versions share the outcome."
tags: [web, touch, hard]
runs: 5
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The CSS sets touch-action: manipulation on the controls, removes the tap highlight only alongside an :active state on every button and the link, and gives each icon control a hit area of at least 24px with no overlapping hit areas"
---

Our mobile web app has a bottom toolbar of icon controls. On phones, every tap flashes a gray box,
taps feel laggy, and people keep hitting the wrong icon. Fix the CSS. This run cannot write files,
so put the CSS in your reply.

```html
<nav class="toolbar">
  <button class="icon-btn" aria-label="Home"><svg width="20" height="20" aria-hidden="true"></svg></button>
  <button class="icon-btn" aria-label="Search"><svg width="20" height="20" aria-hidden="true"></svg></button>
  <button class="icon-btn" aria-label="New post"><svg width="20" height="20" aria-hidden="true"></svg></button>
  <a class="icon-btn" href="/profile" aria-label="Profile"><svg width="20" height="20" aria-hidden="true"></svg></a>
</nav>
```

```css
.toolbar { display: flex; justify-content: center; gap: 4px; }
.icon-btn { display: inline-flex; width: 20px; height: 20px; padding: 0; border: 0; background: none; }
```
