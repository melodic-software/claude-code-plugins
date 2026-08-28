# Sandbox rules for our build tasks

## What a task can see

Each task runs with the workspace root and its own declared inputs mounted, and nothing else
from the checkout is visible to it. Network access is denied unless the task declares a `net`
capability, and a task that declares one is excluded from the cache entirely, because the runner
cannot hash a response it did not make. Environment variables are filtered to an allow list, and
the filtered set forms part of the cache key rather than an incidental property of the machine.

## What this costs us

Two of our lint tasks want the network. We declare `net` on both and accept that they never
cache, which is the trade we would make anyway given how fast they are.

## See also

- The runner's own reference pages: `https://example.invalid/widget-runner/docs/sandbox`
- Our agent pool sizing notes
- The cache eviction thread from March
