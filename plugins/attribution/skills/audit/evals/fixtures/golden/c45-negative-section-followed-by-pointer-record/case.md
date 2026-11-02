# Recipe authoring

How this team writes Brightloom recipes; other recipes cite its headings.

## Recipe `runner` (Northwind addition)

A recipe can set `runner` in its frontmatter. It decides which runner handles the rest of the
current turn while the recipe is in use, and nothing is persisted: the next prompt goes back to the
session's runner. `inherit` stays on the active one. If the organization's `allowedRunners` list
leaves a value out, it is ignored. Under guarded mode, a runner guarded mode cannot use is ignored
as well, and the session stays on its current runner. With `fork: true` the value picks the forked
helper's runner; what happens to a value left out in that case is settled at the fork pointer
below.

- **Pointer**: whenever a recipe's `runner` matters, read the `runner` row at
  <https://example.invalid/brightloom/docs/recipes#frontmatter-reference> live, and for forks
  <https://example.invalid/brightloom/docs/helpers#choose-a-runner> too. **Checked**: 2026-11-01.
  **Revisit when**: that row changes how long the override lasts, the allowlist or guarded-mode
  rule, or the `fork` behavior.

## Arguments (Northwind addition)

Recipes take positional arguments only; named arguments are this team's convention for scripts.
