# Tern documentation: workspaces

Synthetic source page for the attribution golden set. Tern is a fictional coding agent
invented for these fixtures. Nothing on this page describes a real product or reproduces text
from a real page.

Canonical location for the purposes of this case: `https://example.invalid/tern/docs/workspaces`.

## How Tern enforces isolation

The isolation guard refuses a shell command whenever the command's text alone does not prove that
every git call in it stays inside the workspace. Examples: a command name built at runtime, syntax
the guard cannot parse, or an expansion able to run something the text never names.
