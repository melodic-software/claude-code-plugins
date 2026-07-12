# repo-analysis

Git-repo structure, framework, and section-diff analysis (`@melodic/repo-analysis` — `parseGitHubUrl`, `detectRepoStructure`, `detectFrameworks`, `countFiles`, `diffSections`, `diffStartEnd`; pure Node builtins, vitest). Consumed via `file:` package dependency.

Owner: shared capability — no single skill owner; `/course-digest` (`analyze-code-repo.js`) and `/youtube` (`analyze-harvested-repos.js`) jointly consume, so changing it means exercising both consumers. Consumers derive on demand via the repo dep-graph edge scan (`tools/AGENTS.md` "Vertical slices").
