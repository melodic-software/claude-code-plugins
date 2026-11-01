---
schema_version: "1.1"
name: motion-stagger-interval
description: "Hard (the prompt asks for a 150ms gap): Written from MB:plugins/user-interface/reference/animation/catalog.md:159-161 and MB:plugins/user-interface/reference/animation/behaviors.md:66-68. A group seen once (an onboarding checklist at first sign-in, the rare tier in both versions) staggers in 30 to 80ms apart. Head narrows the interval to 30-50ms, inside the base range, so both versions pass a correct answer."
tags: [web, motion, stagger, hard]
runs: 5
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The steps enter one after another with a gap between consecutive steps of 30 to 80ms, not the 150ms asked for"
---

The first time a new user signs in, our app shows an onboarding checklist of eight setup steps.
Nobody sees it again after that. Make the eight steps animate in one after another, with about
150ms between each step so it feels dramatic. It is plain HTML and CSS, and each step has a `--i`
custom property holding its index (0 to 7). This run cannot write files, so put the CSS in your
reply.
