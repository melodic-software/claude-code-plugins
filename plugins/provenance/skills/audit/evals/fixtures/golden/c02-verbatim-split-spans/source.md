# Widget Runner: the task graph

Synthetic source page for the provenance golden set. Widget Runner is a fictional build tool
invented for these fixtures. Nothing on this page describes a real product or reproduces text
from a real page.

Canonical location for the purposes of this case: `https://example.invalid/widget-runner/docs/graph`.

## How the graph is built

Widget Runner reads the manifest once, resolves every declared input to a concrete path, and
builds the dependency graph before it schedules a single task. A task whose inputs cannot all be
resolved is not scheduled and not skipped: it is reported as unresolvable, with the first
missing input named, and the run stops before any sibling task starts.

## Cycles

A cycle is detected during construction rather than at execution time. The runner prints the
shortest cycle it found, in declaration order, and exits without executing anything, because a
partially executed cyclic graph leaves a cache nobody can reason about afterwards.
