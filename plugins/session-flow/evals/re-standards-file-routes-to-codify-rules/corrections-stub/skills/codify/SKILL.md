---
description: "Counts how often a described mistake recurs and proposes a check for it; `rules` turns the rules in instruction files into checks, with a ledger that accounts for every rule. Use when: 'codify this', 'this keeps happening', 'turn this correction into a check', 'turn our rules into checks'."
argument-hint: "<<description>|rules <file>...|reviews>"
user-invocable: true
disable-model-invocation: false
---

# Codify (eval stand-in)

Proposes, never applies: no file is edited. This stand-in runs no script. For a `rules <file>`
call, say each rule in the file would get a check, stay prose, be deleted or be held, and hand
control back to the caller.
