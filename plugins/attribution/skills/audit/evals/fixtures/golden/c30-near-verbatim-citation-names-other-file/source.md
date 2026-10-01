# Widget Runner: job generation reference

Synthetic source page for the attribution golden set. Widget Runner is a fictional build tool
invented for these fixtures. Nothing on this page describes a real product or reproduces text
from a real page.

Canonical location for the purposes of this case: `https://example.invalid/widget-runner/docs/job-generation`.

## Baseline jobs

A **baseline job** is a minimal job that puts the workspace in the state every scenario starts
from (checkout, login, feature flags). Every generated job is written against one.

## Attaching to a baseline

Run `widget run <baseline> --debug` in the background, then `widget attach jb-XXXX` from a second
terminal. Important: do not open the dashboard URL directly. That skips the custom setup the
baseline performs, and the session you get is not the one the job will see.

## Planning

Write findings to `specs/<feature>.plan.md`.
