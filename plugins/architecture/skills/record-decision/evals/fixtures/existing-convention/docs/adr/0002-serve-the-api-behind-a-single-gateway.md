# 0002. Serve the API behind a single gateway

## Status

Accepted

## Date

2025-05-02

## Context

Three clients call the service directly, each with its own auth handling. Adding
a fourth would mean a fourth copy of the token-validation code, and rate limits
could only be enforced per client rather than in aggregate.

## Decision

Put every external caller behind one gateway that terminates TLS, validates
tokens, and applies aggregate rate limits. The service itself trusts the
gateway-supplied principal header and refuses requests that arrive without it.

## Consequences

Token validation lives in one place. The gateway becomes a single point of
failure, so it runs in two zones behind a health-checked load balancer. Local
development needs a gateway stub, which ships in the compose file.
