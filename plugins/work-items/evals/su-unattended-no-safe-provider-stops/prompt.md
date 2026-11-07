---
description: 'Legacy setup 7. Unattended first-time apply on a checkout without gh: github is unsafe and local-markdown and jira need values with no default, so the run stops with the named blocker "tracker binding needs a provider decision" and /work-items:setup apply with a user present, writing no tracker key, unlike the seeding offer, which has a safe skip. provider-decision-blocker reads the reply. Read-only tools, graded on the reply.'
tags: [setup, apply, unattended, hard]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'The unattended default resolves a decision only when its RECOMMENDED answer is safe. Here it is not: github is recommended but requires gh, and local-markdown and jira need storage_dir / config.jira values that have no defaults and cannot be inferred, so no provider can be chosen safely. The run stops and reports "tracker binding needs a provider decision; run /work-items:setup apply with a user present", rather than guessing a provider or inventing config. It writes no tracker key into docs/conventions/work-items.yaml. The seeding offer, by contrast, has a safe default (skip) that resolves silently.'
---

/work-items:setup apply

First-time bind: AGENTS.md binds no convention home, docs/conventions/work-items.yaml does not exist, and no .work-item-tracker.json exists. jq is installed; gh is not installed. This runs unattended: there is no interactive user to answer any question.

Treat the state above as what this run's reads return. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does, in order, and why.
