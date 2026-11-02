# Gauge documentation: plugin evaluations

Synthetic source page for the attribution golden set. Gauge is a fictional evaluation tool
invented for these fixtures. Nothing on this page describes a real product or reproduces text
from a real page.

Canonical location for the purposes of this case: `https://example.invalid/gauge/docs/plugin-evals`.

## Run in CI

In CI, pass `--trust-plugin` so a checkout the runner has not trusted is not refused.

`--keep-local` writes the HTML report to disk instead of uploading it. The report is one
self-contained file that makes no network requests, so you can attach it to a CI job as an
artifact.

Set `--spend-cap-usd` to cap what a run may spend.

## Command options

| Option | Description |
| :- | :- |
| `--pass-mark` | Minimum case score counted as a pass. Defaults to 1.0. Set a pass mark that matches the score you require. |
