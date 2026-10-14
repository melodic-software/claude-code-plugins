---
description: "With no approved plan, a request for a new module behind a public interface that other modules will call is not quick to review or cheap to retry, so implement suggests locking the contract with an interview or a plan first and writes no code."
tags: [implement, concise-rollout, prerequisite, write-gated]
runs: 3
max_turns: 15
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit]
expected_outcome: "The model finds no approved plan, judges the change (new module, public NotificationSender contract, shared retry policy) not quick to review, suggests /planning:interview or another interview or plan step before code, and calls neither Write nor Edit."
---

/implementation:implement feature Add a notifications module to this service: a public `NotificationSender` interface that the `orders` and `billing` modules will call, email and webhook adapters behind it, and a retry policy shared by both adapters. The working directory is the root of a git repository on branch `feat/notifications` with a clean tree.
