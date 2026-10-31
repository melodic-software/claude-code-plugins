---
schema_version: "1.1"
name: web-layout-flat-dashboard
description: "Hard (the request names only hierarchy and spacing): a flat dashboard's revised CSS spaces siblings with gap on the parent, takes z-index from a defined token scale with no 9999 left, and makes the decorative glow over the buttons inert"
tags: [web, web-layout, hard]
runs: 5
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The revised CSS uses gap on the parent instead of per-child margin-bottom, defines named z-index tokens (--z-*) and leaves no z-index: 9999, and sets pointer-events: none on the absolutely positioned glow"
---

This dashboard feels flat, tighten up the hierarchy and spacing. Keep the glow over the actions; the brand team wants it. This run cannot write files, so put the revised CSS and any markup changes in your reply.

```html
<header class="topbar">Acme</header>
<section class="stats">
  <div class="stat">Revenue <strong>$12,480</strong></div>
  <div class="stat">Orders <strong>318</strong></div>
  <div class="stat">Refunds <strong>4</strong></div>
</section>
<div class="actions">
  <button class="btn-primary">Export</button>
  <button class="btn-primary">Invite</button>
  <button class="btn-primary">New report</button>
  <div class="hero-glow"></div>
</div>
<div class="modal">...</div>
<div class="toast">Saved</div>
```

```css
.topbar { position: sticky; top: 0; z-index: 50; }
.stat { margin-bottom: 13px; padding: 9px; }
.actions { position: relative; }
.hero-glow { position: absolute; inset: -20px; background: radial-gradient(#7c3aed55, transparent); }
.modal { position: fixed; z-index: 1000; }
.toast { position: fixed; z-index: 9999; }
```
