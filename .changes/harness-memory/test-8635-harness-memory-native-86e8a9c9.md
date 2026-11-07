---
bump: patch
---

### Changed

- The audit and stateless `evals.json` files are retired into the `evals/` case suite ([#8635](https://github.com/melodic-software/claude-code-plugins/issues/8635)). Seventeen new cases cover the audit's default report, its scope and data-directory boundaries, fix needing a prior audit, the repo-declared line-budget exemption, content placement, the C9 wrong-command check, per-project report keying and the unkeyed leftover report, C6 ownership of user-versus-project conflicts, the /init-shaped bloat pass, and nested `AGENTS.md` reachability with synced provenance; and stateless status, its scope boundary, disabling through both levers, and desktop memory. The legacy audit fixture is now that case's scaffold. Legacy stateless cases 3 and 5 were already covered by existing cases.
