# Widget Runner: scheduled runs

Synthetic source page for the attribution golden set. Widget Runner is a fictional build tool
invented for these fixtures. Nothing on this page describes a real product or reproduces text
from a real page.

Canonical location for the purposes of this case: `https://example.invalid/widget-runner/docs/schedules`.

## Backends

Widget Runner schedules recurring runs through three backends: cron on the agent, a systemd timer
unit, or the hosted queue. Every backend needs runner 2.4 or later.

## Missed runs

A run whose slot passes while its agent is down is skipped, never queued up for later.
