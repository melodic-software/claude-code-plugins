# ADR-007: Cache session tokens in Redis

## Context

Every request revalidated its session token against the identity provider, which
added a network round trip to the hot path and made the service unavailable
whenever the provider was.

## Decision

Cache validated tokens in Redis, keyed by token hash, with a TTL of the shorter
of the token expiry and five minutes. A cache miss falls back to the provider.

## Status

Accepted, 2025-04-30.
