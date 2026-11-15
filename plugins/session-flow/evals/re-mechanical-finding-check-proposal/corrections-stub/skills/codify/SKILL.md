---
description: "Counts how often a described mistake recurs in recent commits and the session, picks the strongest enforcement-ladder rung that can catch it, places the lesson by scope, and proposes a check proven to fail on the old code and pass on the current code; `preferences` proposes user-scope lines for what a person keeps typing across sessions; also takes a review findings file or merged pull requests' review comments as the source. Use when: 'codify this', 'this keeps happening', 'stop us making this mistake again', 'turn this correction into a check', 'what rung catches this', 'prove this check', 'can we stop re-finding this', 'mine our review comments', 'put what I keep repeating into my instructions'."
argument-hint: "<<description> [#PR]|findings <file>|reviews|note [--applied] <observation>|preferences|group…>"
user-invocable: true
disable-model-invocation: false
---

# Codify (eval stand-in)

Proposes, never applies: a proposed check or instruction line is written for the person to accept,
and no file is edited. This stand-in runs no count, keeps no findings buffer, and runs, writes and
proves nothing; the caller does not try the check out in its place either. For a `group` or
`note` call, say the buffer holds no rows and hand control back to the caller, which goes on with
its own steps. For a described mistake, say which check it would propose (the rung and the rule),
then hand control back the same way: the hand-off is the caller's own recommendation row naming
this skill, which the person approves before any check is written.
