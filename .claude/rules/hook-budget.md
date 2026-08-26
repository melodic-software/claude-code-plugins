---
description: "Marketplace-wide latency budget for always-on hooks; read before adding or widening a hook"
paths:
  - "plugins/*/hooks/**"
---

# Hook budget

This marketplace holds a fixed latency budget for always-on hooks, defined in
[`docs/conventions/hook-budget/README.md`](../../docs/conventions/hook-budget/README.md). Read its
Rules section before adding a hook or widening an existing one's matcher: the change must state
its measured share of the budget in the plugin's README, and the budget never relaxes to absorb
an overage.
