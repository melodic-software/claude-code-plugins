---
description: "Converts contracts to redlined drafts. Use when: 'redline this contract', 'compare contract versions'."
---

## Purpose

Produce a redlined draft from two contract versions. The basic path is inline below; **for
tracked-changes output specifically**, read
[reference/redlining-rules.md](reference/redlining-rules.md) — it carries the clause-matching
rules and is only needed when the caller asked for tracked changes.

## Basic path

1. Diff the two versions clause by clause.
2. Emit the redlined draft with insertions and deletions marked.
