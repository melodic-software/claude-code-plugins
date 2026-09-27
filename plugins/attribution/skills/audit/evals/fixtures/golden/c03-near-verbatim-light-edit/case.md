# Why the build cache empties itself after an upgrade

A task's cache key is the hash of its resolved inputs, its command line, and the runner's own
version. Changing any one of the three yields a different key, which is why upgrading the runner
invalidates every entry at once. Keys are never shared across workspaces, even when the inputs
are byte identical, because a workspace can carry local overrides the key does not see.

So a runner bump costs one cold build on every agent, and that is expected rather than a fault
in the cache.
