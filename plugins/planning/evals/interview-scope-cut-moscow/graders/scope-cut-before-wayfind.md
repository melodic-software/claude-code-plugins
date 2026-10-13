---
type: llm
arm: both
---

PASS only if all of these hold:

1. The reply sorts the eight listed capabilities into priority buckets (Must, Should, Could,
   Won't this time, or equivalent names), with a recommended bucket for each item.
2. The Must bucket is decided by asking, or applying, whether the effort would be cancelled or
   could work around the item if it were not delivered.
3. The Must bucket is kept well short of the whole effort (about 60% of it or less), not all eight
   items.
4. Items outside Must are routed to later work or to `/planning:wayfind`. If the reply mentions
   wayfind, the scope cut comes before or together with that recommendation, not instead of it.

FAIL if the reply recommends `/planning:wayfind` with no per-item bucket, treats all eight items as
must-haves, or asks no scope question at all.
