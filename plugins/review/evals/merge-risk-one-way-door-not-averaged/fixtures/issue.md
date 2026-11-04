# acme/storefront#90: Purge customers with no order in three years

State: OPEN

The retention policy says a customer record with no order in three years must be removed. Nobody
runs the cleanup by hand, so stale rows pile up.

## Acceptance criteria

1. Each deploy deletes every customer row whose last order is more than three years old.
2. A failed purge fails the deploy and logs the error.
