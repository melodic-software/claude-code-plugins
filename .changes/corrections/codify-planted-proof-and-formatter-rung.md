---
bump: minor
---

### Added

- `prove-check.sh --plant <patch>` proves a check against a planted violation: the patch is
  committed on top of the new ref in the script's temporary worktree, on no branch and never
  pushed, and the worktree is removed on every exit path. `/corrections:codify` plants the mistake
  when no old ref resolves, so `rules` holds a never-broken rule only when no plant can express it.
- The bundled enforcement ladder is 3.3.0, with a `formatter` rung for a style rule the
  repository's recorded format command (`fix-cmd`) can enforce. A `style` finding takes it when
  that command can, and `editorconfig-severity` otherwise.
- `rules` labels each style rule `formatter` or `lint`, and `rules-ledger.mjs` checks the label
  against the rung and accepts a `plant` in place of an `old_ref`.
