<!-- markdownlint-disable MD024 -->
<!-- The repeated "Outbound webhooks" heading is the fixture. This file exists so a run can be
     pointed at a heading whose full ancestry is not unique, and the duplicate is what makes the
     ancestry collide. Deduplicating it would delete the case. -->

# Delivery guarantees

The queue retries a failed job three times before parking it.

## Outbound webhooks

Delivery is at-least-once, so a receiver has to tolerate a repeat.

### Rationale

Exactly-once delivery across a network partition is not available to us, and pretending otherwise
pushes duplicate handling into every receiver's blind spot instead of stating it here.

## Inbound callbacks

A callback received twice is dropped on its idempotency key.

## Outbound webhooks

Retries back off exponentially and stop at twenty-four hours.

### Rationale

A receiver that has been down for a day has a bigger problem than this queue, and holding the job
longer turns our retention into their outage.
