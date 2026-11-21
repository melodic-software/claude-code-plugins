---
description: "Engineering task with one external provider and nothing said about others, past the intake round: the interview asks the intent question (is a second variant known, a category, or speculative) with a recommendation in the first decision round, registers it in the ledger at ask-time, and heads the round with a Scope check: line"
tags: [interview, intent, engineering-defaults]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Agent, Write, Edit]
expected_outcome: "Round 2 asks whether a second address-validation provider or per-client variation is known, expected as a category, or speculative, with a recommendation; the round header carries a Scope check: line; and the ledger .work/address-validation/interview-checklist.md carries that question as an open register row"
---

/planning:interview Add delivery-address validation to checkout using the Loqate API, so an undeliverable address is caught before payment. This goes to production. Use the topic slug `address-validation`.

Round 1 is answered: Q1, the problem is orders shipped to addresses the carrier cannot deliver to; Q2, the users are shoppers at checkout and the support team that handles returned parcels.

Ask round 2 now, then stop for my answers.
