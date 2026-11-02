# Brightloom documentation: recipes

Synthetic source page for the attribution golden set. Brightloom is a fictional workflow assistant
invented for these fixtures. Nothing on this page describes a real product or reproduces text
from a real page.

Canonical location for the purposes of this case: `https://example.invalid/brightloom/docs/recipes`.

## Frontmatter reference

| Field | Description |
| :- | :- |
| `runner` | Which runner handles the rest of the current turn while this recipe is in use. Nothing is persisted: the next prompt goes back to the session's runner. Takes any value `/runner` takes, or `inherit` to stay on the active one. If the organization's `allowedRunners` list leaves a value out, it is ignored. Under guarded mode, a runner guarded mode cannot use is ignored as well, and the session stays on its current runner. |
| `fork` | Set to `true` to run the recipe in a forked helper. |
