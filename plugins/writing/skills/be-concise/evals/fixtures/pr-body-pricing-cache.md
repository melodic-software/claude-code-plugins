Closes #123

## Summary

So the basic situation here is that the pricing service has a cache in front
of the tier lookup, and what we have been seeing for a while now, really ever
since the tier import job was changed back in July, is that the cache does not
always get invalidated when an import lands. What that means in practice is
that a customer whose tier changed can carry on seeing the old price for quite
a long time, and in the worst case that we have actually observed in
production it was somewhere in the region of fifteen minutes, which is
obviously not great from a trust point of view and it has generated a
reasonable number of support tickets over the last few weeks.

## Fix

What this change does is fairly straightforward once you see it. The import
job now publishes a `pricing.tier.imported` event at the end of its run, and
the cache layer subscribes to that event and evicts the affected keys rather
than waiting for them to age out naturally. We also went ahead and dropped
`PRICE_CACHE_TTL_SECONDS` from 3600 to 900, mostly as a belt-and-braces thing
so that even if the event is somehow missed the blast radius of a stale entry
is a lot smaller than it used to be. There is no schema change involved here
and nothing needs to be backfilled.

## Verification

I ran `pytest tests/pricing/test_cache.py` locally and everything passes,
including the two new tests that cover the eviction path and the missed-event
path. I also deployed the branch to staging and manually pushed a tier import
through, and confirmed that the price a customer sees updates within about two
seconds rather than the old behaviour. The load test was run as well and there
was no measurable change in p99 latency.

## Related

This is basically the follow-up to #118, which is where the stale-price
behaviour was first reported by the support team, and it also unblocks #131
because that one needs reliable invalidation before the per-region pricing
work can start. The original design discussion, for anyone who wants the
background, is in the pricing channel thread from 2026-08-14.
