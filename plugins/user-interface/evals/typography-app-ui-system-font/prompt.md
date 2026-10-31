---
schema_version: "1.1"
name: typography-app-ui-system-font
description: "Hard (the model tends to reach for a web font): Written from MB:plugins/user-interface/reference/types/web.md:30-31, with the escape clause of MB:plugins/user-interface/reference/principles.md:10-12 (replace a default with the project's choice, or with a reason). With no project fonts, application UI uses the platform's system font stack, or a typeface chosen for a stated reason. Head keeps the system stack as the app UI default, so both versions share the outcome. A new case because typography-article-text never names its font."
tags: [web, typography, hard]
runs: 5
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The body font-family is the platform's system font stack, or a named typeface the reply gives a reason for; never an unexplained web font"
---

Set up the base typography for our internal inventory app: body text, table text, form labels and
page headings. The project has no fonts or type tokens yet. Plain CSS. This run cannot write files,
so put the CSS in your reply.
