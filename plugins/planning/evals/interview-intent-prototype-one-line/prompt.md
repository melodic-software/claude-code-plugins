---
description: "Stated throwaway prototype that reads one external store: the intent question is one line, and no quality requirement (performance, availability, security, scaling, monitoring) is asked; they are named as deferred"
tags: [interview, intent, quality-bar, prototype, engineering-defaults]
runs: 3
max_turns: 20
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "Round 1 asks one one-line question on whether other stores or platforms are expected (or confirms keeping it specific), asks no quality-requirement question, and names quality requirements as deferred for a prototype"
---

/planning:interview I want a throwaway prototype that pulls last month's Shopify orders into a CSV, so I can show finance a report idea on Friday. It will never ship and only I will run it. Use the topic slug `orders-csv`.
