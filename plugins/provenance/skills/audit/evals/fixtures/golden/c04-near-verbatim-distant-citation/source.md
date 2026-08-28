# Widget Runner: the task sandbox

Synthetic source page for the provenance golden set. Widget Runner is a fictional build tool
invented for these fixtures. Nothing on this page describes a real product or reproduces text
from a real page.

Canonical location for the purposes of this case: `https://example.invalid/widget-runner/docs/sandbox`.

## What a task can see

Every task runs with the workspace root and its own declared inputs mounted, and nothing else
from the checkout is visible to it. Network access is denied unless the task declares a `net`
capability, and a task that declares one is excluded from the cache entirely, because the runner
cannot hash a response it did not make. Environment variables are filtered to an allow list, and
the filtered set is part of the cache key rather than an incidental property of the machine.

## Escapes

There is no supported escape. A task that needs the whole checkout declares the checkout as an
input and pays the hashing cost.
