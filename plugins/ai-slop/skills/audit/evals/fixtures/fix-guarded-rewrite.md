# Cache invalidation

It is worth noting that the cache invalidates on write — the reader never sees
a stale entry. Due to the fact that writes are rare, the extra round trip costs
little.

The eviction policy is least-recently-used — a choice made when the working set
was small, and one the team has not revisited since.
