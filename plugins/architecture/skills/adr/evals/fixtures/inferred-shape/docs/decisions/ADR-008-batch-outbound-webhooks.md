# ADR-008: Batch outbound webhooks

## Context

Each domain event fired its own webhook delivery. A bulk import produced tens of
thousands of individual POSTs, and two subscribers rate-limited us for a day.

## Decision

Batch outbound deliveries per subscriber on a one-second window, capped at 500
events per request. Subscribers that declare no batch support keep the
one-event-per-request path.

## Status

Accepted, 2025-07-14.
