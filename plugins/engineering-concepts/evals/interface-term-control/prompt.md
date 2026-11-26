---
description: "No-trigger near-miss control for both skills. The request asks for the name of an interface effect, which the descriptions hand to /user-interface:glossary, so neither engineering-concepts skill loads. A model without the plugin passes too; the case guards against a description rewrite that fires on any request to name a term."
tags: [engineering-concepts, lookup, load, skip, regression-guard]
max_turns: 6
timeout_seconds: 180
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "No Skill call loads engineering-concepts:lookup or engineering-concepts:load."
---

What is the name for the little bounce a popover does when it opens, where it overshoots and settles back?
