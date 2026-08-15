# Ecosystem Cleanup Definitions

The per-ecosystem cleanup surface is owned elsewhere — read it at the source:

- **Tier membership, protected paths, and sweep semantics** —
  [`cleanup-config.md`](cleanup-config.md), the configuration the Workflow (§1–§5 in `SKILL.md`)
  iterates.
- **Sweep mechanics and rationale** — the action scripts
  [`../scripts/clean-caches.sh`](../scripts/clean-caches.sh) and
  [`../scripts/clean-build.sh`](../scripts/clean-build.sh), whose comments carry the reasoning
  (e.g. why no build-system clean driver such as `dotnet clean` runs).
- **Git-tier actions** — [`../scripts/git-prune.sh`](../scripts/git-prune.sh),
  [`../scripts/git-branch-audit.sh`](../scripts/git-branch-audit.sh),
  [`../scripts/git-stash-audit.sh`](../scripts/git-stash-audit.sh) and siblings.
