---
schema_version: "1.1"
name: touch-sign-in-input-zoom
description: "Hard (the prompt carries a zoom lock someone added to hide the bug): a sign-in page whose email field zooms the page on an iPhone gets 16px input text on touch and the zoom lock removed"
tags: [web, touch, hard]
runs: 5
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The email input's computed font size is at least 16px on touch devices, set in CSS or utility classes, with any smaller desktop size gated on the pointer rather than on screen width, and the viewport meta tag no longer carries maximum-scale or user-scalable, so people can still pinch to zoom"
---

Our sign-in page has one email field and a "Send me a one-time password" button. On an iPhone,
tapping the email field zoomed the whole page in and it stayed zoomed, so someone added
`maximum-scale=1` to the viewport tag. Now a user on Android says they can't pinch to zoom. Fix it
properly; the design wants the field's text to look small on desktop.

```html
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1" />
```

```css
html { font-size: 87.5%; }
.signin input[type="email"] { font-size: 0.875rem; padding: 0.5rem 0.75rem; }
```

This run cannot write files, so put the corrected tag and CSS in your reply.
