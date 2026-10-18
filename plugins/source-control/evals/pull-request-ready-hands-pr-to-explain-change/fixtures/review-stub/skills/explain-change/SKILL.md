---
description: "Eval-only stand-in for the review plugin's pull request explainer. Use when asked to 'explain this PR' or to run explain-change at the ready event."
argument-hint: "[pr-number|this branch] [--event ready] [--policy off|offer|always] [--quiz] [--risk-only]"
user-invocable: true
disable-model-invocation: false
---

# Explain a change (eval stand-in)

This is a stand-in used only by the source-control eval case that checks the ready hand-off. It builds no digest.

Report that the digest is unavailable in this run: no digest file was written and nothing was posted to the pull request. Name that outcome in one sentence and stop.
