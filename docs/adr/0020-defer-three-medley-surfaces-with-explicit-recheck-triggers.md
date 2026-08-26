# Defer three medley surfaces from the plugin migration, each with a recheck trigger

- Status: accepted
- Date: 2026-07-12

## Decision

Three general-purpose surfaces in the harvest-source repo (`melodic-software/medley`) are held out of this
wave's plugin migration deliberately, each with an explicit
[recheck trigger](../conventions/upstream-drift/README.md) — recorded here so the deferral
is a decision, not a silent omission. The medley side carries a thin pointer back to this record at each
surface (the workflow-engine authoring rule, the `onboard` skill, and the `gh-bot.sh` bot-identity
convention), so a contributor who touches a deferred surface finds the trigger without leaving that repo.

- **Workflow engines** (`code-review.js`, `codebase-review.js`, `deep-research.js`,
  `research-deep-fanout.js`, `skills-audit.js`, `skills-evals.js`, `skills-remediate.js`): deferred
  2026-07-12 as not a plugin component, so these may be removed entirely rather than migrated.
  Re-verified 2026-07-27: the no-native-slot premise no longer holds — plugins now ship workflow
  scripts via a `workflows/` directory
  (<https://code.claude.com/docs/en/plugins-reference#standard-plugin-layout>) or the `workflows`
  manifest field (<https://code.claude.com/docs/en/plugins-reference#component-path-fields>), and a
  plugin workflow runs plugin-namespaced
  (<https://code.claude.com/docs/en/workflows#distribute-a-workflow-in-a-plugin>) — but the deferral
  stands on the usage question alone. **Recheck trigger:** the engines survive the next usage review
  (still earning their keep) → migrate through the native plugin `workflows/` slot, verifying each
  engine script fits the documented workflow-script shape, with a smoke test specced for that
  dispatch path before packaging.
- **`onboard` skill:** repo-specific today — its phase gates encode this repo's exact runtime, linter, and
  tooling pins. **Recheck trigger:** a second repo needs environment-prerequisite auditing → extract a
  generic core through the extensibility-contract seams (the convention-resolution ladder infers or asks
  for the per-repo pins), leaving repo specifics in tracked config rather than baked into the skill.
- **`tools/github-auth` (`gh-bot.sh`):** hardcodes the org's bot App / installation identity. **Recheck
  trigger:** a second repo needs bot-actor GitHub operations → parameterize org / App / installation
  through the seams (`userConfig` scalars, `sensitive` for the key) instead of standing up a second
  hardcoded wrapper.
