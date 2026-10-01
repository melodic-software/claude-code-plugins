# Widget Runner: shell selection

Synthetic source page for the attribution golden set. Widget Runner is a fictional build tool
invented for these fixtures. Nothing on this page describes a real product or reproduces text
from a real page.

Canonical location for the purposes of this case: `https://example.invalid/widget-runner/docs/shells`.

## Windows agents

The runner runs task commands through the POSIX shell when one is installed, or through the
PowerShell shim when none is installed. The choice is made once at agent start.

## Overriding the choice

Set `WIDGET_SHELL` to force either.
