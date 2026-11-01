---
tags: ['reduce']
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: 'Runs the bundled collision-hotspots script from the repository root with --prs sized to several days of history (about 40 a day), reads its conflicts, pairs and path rows, verifies the ranked files before ledgering them as collision-hotspot candidates beside the co-change evidence, carries every gap: line into the report, treats the known bump hotspots line (changelogs, lockfiles, version manifests) as version-bump noise that is not ledgered, and makes no repository edits because the run is dry-run.'
---

/coupling:reduce dry-run

We run several agents in parallel on this GitHub repo and their pull requests keep conflicting. Which files do they keep colliding on? We merge about 40 pull requests a day.
