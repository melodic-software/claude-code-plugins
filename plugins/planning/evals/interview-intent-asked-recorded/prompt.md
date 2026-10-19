---
description: "Engineering task with one external provider and nothing said about others: the interview asks the intent question (is a second variant known, a category, or speculative) with a recommendation, and registers it in the ledger at ask-time"
tags: [interview, intent, engineering-defaults]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "Round 1 asks whether a second address-validation provider or per-client variation is known, expected as a category, or speculative, with a recommendation, and the ledger .work/address-validation/interview-checklist.md carries that question as an open register row"
---

/planning:interview Add delivery-address validation to checkout using the Loqate API, so an undeliverable address is caught before payment. This goes to production. Use the topic slug `address-validation`.
