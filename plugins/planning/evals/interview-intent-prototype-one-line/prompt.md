---
description: "Stated throwaway prototype that reads one external store: the intent question is one line, and no quality requirement (performance, availability, security, scaling, monitoring) is asked; they are named as deferred. The prompt starts past the intake round, so the variation-intent question, a decision question, comes in round 2"
tags: [interview, intent, quality-bar, prototype, engineering-defaults, scaffold, no-network]
runs: 3
max_turns: 20
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "Round 2 asks one one-line question on whether other stores or platforms are expected (or confirms keeping it specific), asks no quality-requirement question, and names quality requirements as deferred for a prototype"
---

/planning:interview I want a throwaway prototype that pulls last month's Shopify orders into a CSV, so I can show finance a report idea on Friday. It will never ship and only I will run it. Use the topic slug `orders-csv`.

Round 1, the intake round, is answered and recorded in .work/orders-csv/interview-checklist.md: Q1, the report must show finance last month's order count and revenue per day; Q2, I start from nothing in this repository and already have a Shopify Admin API access token.

Ask me round 2 now, then stop for my answers.
