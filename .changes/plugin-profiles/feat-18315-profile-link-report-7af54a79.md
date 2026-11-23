---
bump: minor
---

### Added

- **Skill links that leave a profile are reported.** `profiles.mjs check` reads each skill's `## Next` and `## Related` `/plugin:skill` targets and reports, without failing, a target whose plugin a profile switches off or whose skill it hides (`links.next`, and `links.related` as a separate informational list) and a target that resolves to no skill (`links.unresolved`). A profile's members are its plugins, its optional plugins, always-on unless it opts out, and their manifest dependencies, minus `exclude`. `--skills <plugins dir>` checks a repository tree against its shipped profiles and also lists catalog plugins no shipped profile names; without it the installed plugins are checked against your own profiles. `--changed <file>` puts the lines for the skills and profiles a change touched first, and with `GITHUB_STEP_SUMMARY` set the tree check writes them to the job summary, the rest under a collapsed heading.
