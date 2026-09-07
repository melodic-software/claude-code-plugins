# ADR-008: Pin the Node runtime to LTS

## Context

Two builds picked up a new Node major on the same week the base image moved, and
a native dependency stopped compiling. Nothing declared which runtime the service
was expected to run on.

## Decision

Pin the runtime to the current LTS line in the Dockerfile, the CI matrix, and
`.nvmrc`, and move the pin deliberately once per LTS cycle.

## Status

Accepted, 2025-07-21.
