---
description: "Eval cases in this public repository never hold a raw session or product transcript; a one-to-one rewrite with every identifying detail changed is allowed after the identifying-details review"
paths:
  - "plugins/*/evals/**"
  - "plugins/*/skills/*/evals/**"
---

# Eval case transcripts

This repository is public. No eval case here holds a raw Claude Code session transcript or a raw
product transcript (a chat log, support ticket, or log line from a real user), in a prompt, an
expected output, a grader, or a fixture.

A one-to-one rewrite of a transcript is allowed: one case per original, with every sensitive or
identifying detail changed. Before it lands, a person approves it through the input approval in
`/evals:design`, which carries the identifying-details checklist. That approval is the review; there
is no second pass.
