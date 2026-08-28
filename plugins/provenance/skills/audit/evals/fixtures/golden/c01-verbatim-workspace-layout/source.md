# Widget Runner: workspace layout

Synthetic source page for the provenance golden set. Widget Runner is a fictional build tool
invented for these fixtures. Nothing on this page describes a real product or reproduces text
from a real page.

Canonical location for the purposes of this case: `https://example.invalid/widget-runner/docs/workspace`.

## Where the runner keeps its state

Widget Runner writes every artifact it produces beneath a single workspace root, and it will not
write outside that root even when a task asks it to. The root holds four directories, each
created on first use: `cache` for content-addressed task outputs, `logs` for per-task stdout and
stderr, `locks` for the advisory files that keep two runners off one workspace, and `tmp` for
scratch space that is cleared at the start of every run.

## Choosing a root

The root defaults to a `.widget` directory beside the manifest. Passing `--workspace` overrides
it, and the `WIDGET_WORKSPACE` variable overrides that in turn, so a shared build machine can
point every checkout at one cache without editing a tracked file.
