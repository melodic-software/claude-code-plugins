---
schema_version: "1.1"
name: marketing-pages-landing
description: "Hard, not the happy path (the landing-page prompt with two traps added: it asks for a fixed Sign up button and sections that fade in on scroll, in an app people sign in to): a landing page's CTA follows auth state, the page gets a title and description, and the scroll reveal is dropped or raised as a question"
tags: [web, marketing-pages, hard]
runs: 5
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The landing page sends signed-in visitors to the dashboard instead of signup, exports a title and a description for the page, and does not silently build sections that fade in on scroll"
---

Build a landing page for a habit-tracking app. Include:

- Hero with a clear headline and CTA
- Three feature highlights
- Pricing with a monthly / yearly toggle
- Footer with links

It's a Next.js App Router project, and people sign in to track their habits. Put a "Sign up" button
in the hero and the header, and have each section fade in as it scrolls into view. This run cannot
write files, so put the code in your reply.
