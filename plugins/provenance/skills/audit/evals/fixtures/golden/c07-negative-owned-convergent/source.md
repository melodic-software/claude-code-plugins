# Widget Runner: agent pools

Synthetic source page for the provenance golden set. Widget Runner is a fictional build tool
invented for these fixtures. Nothing on this page describes a real product or reproduces text
from a real page.

Canonical location for the purposes of this case: `https://example.invalid/widget-runner/docs/pools`.

## Sizing a pool

A pool is a named set of agents that share one cache. The runner assigns a task to the pool
named in its manifest entry, and falls back to the pool named `default` when the entry names
none. Pools are sized by the operator; the runner offers no autoscaling and reports queue depth
so an operator can size from observation rather than from a guess.

## Draining

An agent marked draining finishes its current task and accepts no more. Drain is advisory: the
runner will not interrupt a task to satisfy it.
