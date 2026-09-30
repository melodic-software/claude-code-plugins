# Widget Runner release guide: configuring the cache, scheduler and sandbox

Synthetic source page for the attribution golden set. Widget Runner is a fictional build tool
invented for these fixtures. Nothing on this page describes a real product or reproduces text
from a real page.

Canonical location for the purposes of this case: `https://example.invalid/widget-runner/docs/build-with-widget-runner/release-guide/configuring-the-cache-scheduler-and-sandbox`.

## Cache

The cache is keyed on resolved inputs, so a rebuilt dependency invalidates its dependents.
Entries are evicted least recently used.

## Scheduler

Recurring runs need runner 2.4 or later.
