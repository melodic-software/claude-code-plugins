# Widget Runner: cache keys

Synthetic source page for the provenance golden set. Widget Runner is a fictional build tool
invented for these fixtures. Nothing on this page describes a real product or reproduces text
from a real page.

Canonical location for the purposes of this case: `https://example.invalid/widget-runner/docs/cache-keys`.

## What goes into a key

The cache key for a task is the hash of its resolved inputs, its command line, and the runner's
own version. Changing any one of the three produces a different key, which is why a runner
upgrade invalidates every entry at once. Keys are never reused across workspaces, even when the
inputs are byte identical, because a workspace can carry local overrides the key does not see.

## Eviction

Entries are evicted least-recently-used, and the runner never evicts an entry an in-flight task
still depends on.
