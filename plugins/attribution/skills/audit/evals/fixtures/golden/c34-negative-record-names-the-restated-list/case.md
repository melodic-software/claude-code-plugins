# Wiring recurring runs

The overnight rebuilds, the weekly cache purge and the Monday dependency sweep are all
recurring runs. This page says how each one is wired.

## Choosing a backend

Widget Runner schedules recurring runs through three backends: cron on the agent, a systemd timer unit, or the hosted queue. Every backend needs runner 2.4 or later.

Claim: the backend list and the version floor in the paragraph above. Basis:
<https://example.invalid/widget-runner/docs/schedules>, section "Backends". As of: 2026-09-20.
Recheck trigger: a runner release note that adds or drops a backend, or moves the floor,
re-derives that paragraph.

## What we run where

The rebuild and the purge use cron. The sweep uses the hosted queue, because it is the only
recurring run that outlives a reboot of its agent.
