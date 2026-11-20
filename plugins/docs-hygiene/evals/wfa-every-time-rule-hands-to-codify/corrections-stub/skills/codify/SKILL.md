---
description: "Counts how often a described mistake recurs in recent commits and the session, picks the strongest enforcement-ladder rung that can catch it, places the lesson by scope, and proposes a check proven to fail on the old code and pass on the current code; also takes a review findings file or merged pull requests' review comments as the source. Use when: 'codify this', 'this keeps happening', 'stop us making this mistake again', 'turn this correction into a check', 'what rung catches this', 'prove this check', 'turn this rule into a check'."
argument-hint: "<<description> [#PR]|findings <file>|reviews|rules <file>|note [--applied] <observation>|group…>"
user-invocable: true
disable-model-invocation: false
---

# Codify (eval stand-in)

Proposes, never applies: a proposed check or instruction line is written for the person to accept,
and no file is edited. This stand-in runs no count. For a described rule or mistake, say what it
would propose and hand control back to the caller, which goes on with its own steps.
