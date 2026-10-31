---
schema_version: "1.1"
name: typography-article-text
description: "Hard (the prompt proposes a fixed-pixel line height and a raw weight tag): article typography sets body leading unitless and the heading weight through font-weight rather than font-variation-settings, and caps the body column near 65ch"
tags: [web, typography, hard]
runs: 5
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The CSS sets the body line-height as a unitless number (not 24px) and the heading weight with font-weight (not font-variation-settings \"wght\"), with the body column capped near 65ch"
---

Design the typography for the article pages on our blog. It is plain CSS with a variable font loaded. I was going to set `line-height: 24px` on the body text and make the headings bolder with `font-variation-settings: "wght" 600`. This run cannot write files, so put the CSS in your reply.
