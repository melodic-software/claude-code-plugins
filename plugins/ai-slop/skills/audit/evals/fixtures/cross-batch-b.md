# Profile cache notes

The profile cache holds rendered profile pages for ten minutes after the first request.

The comment above the eviction loop is load-bearing, so read it before you change how entries
expire. It explains why an entry expires on write and never on read.

## Rules

- Never clear the cache during a deploy: in-flight requests still read from it.
