---
bump: minor
---

### Added

- Primary-tier `projects-and-issues` audit recipe (`reference/recipes/projects-and-issues.md`) covering native issue statuses (including actor-provenance trust-boundary separation), Repository Boards versus organization Projects, native Issue Artifacts, symmetric `"Relates to"` links and sub-issues, issue types and fields, and label archiving hygiene.

### Changed

- Updated `reference/recipes/actions-policy.md` to audit workflow action lockfiles (`actions.lock`), self-repository local action shorthand (`$/...`) and nested `parallel:` step policy coverage, unarchived single-file artifact (`archive: false`) basename alignment with retention rules, repository Actions event/actor policies with active-workflow existence verification, and OIDC repository-property (`repo_property_*`) custom-property inclusions with org-admin-only editability.
- Updated `reference/recipes/billing.md` to audit per-product metered usage summaries on the enhanced billing platform and org/repository artifact and log retention ceilings.
- Updated `reference/recipes/rulesets-repo-drift.md` to audit immutable-release enablement alongside tag-protection rulesets on release-publishing repositories.
- Promoted `projects-and-issues` to primary tier in `reference/areas.md` and extended `github.test.sh` to enforce full recipe inventory and `areas.md` link parity.
