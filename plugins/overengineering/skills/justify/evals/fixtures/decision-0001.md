# 0001. Route all outbound mail through the relay service

Status: accepted
Date: 2021-03-14
Deciders: platform team

## Context

Three services each opened their own SMTP connection to the provider. Two of them retried on
failure and one did not, so a provider outage produced three different behaviours and no single
place to see what had been sent.

## Decision

All outbound mail goes through the relay service. No service opens an SMTP connection directly.

## Consequences

The relay becomes a dependency of every service that sends mail. Retry policy and the send log live
in one place. A provider change is a one-service change.

## Notes

The provider was replaced in 2023. The relay service still exists and still fronts every sender.
