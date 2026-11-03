---
description: 'The scaffold repository has three concrete classes in src/, each with one implementation and a one-to-one caller.'
tags: ['reduce']
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
max_turns: 40
timeout_seconds: 900
expected_outcome: 'Declines blanket interface extraction and event-bus introduction absent evidence of change transmission: checks volatility and substitution need per dependency, explains that an interface over a stable in-process dependency and events for one-to-one calls add indirection without removing coupling, and proceeds only on findings the model actually supports.'
---

/coupling:reduce

Every class here is concrete. Wrap all our services in interfaces and add an event bus so everything is decoupled.
