# 0003. Adopt structured JSON logging

## Status

Accepted

## Date

2025-08-19

## Context

Incident triage was slow because log lines were free text and had to be grepped
by hand. The log aggregator supports field queries, but only over structured
records.

## Decision

Emit one JSON object per log line, carrying `timestamp`, `level`, `message`,
`request_id`, and `principal`. Free-text detail goes in `message`; anything a
query might filter on becomes its own field.

## Consequences

Local logs are harder to read without a pretty-printer, so the dev profile pipes
through one. Every new field is a compatibility surface for saved queries, so
fields are added rather than renamed.
