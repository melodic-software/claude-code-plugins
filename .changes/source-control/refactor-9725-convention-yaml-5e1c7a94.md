---
bump: minor
---

### Changed

- The commit and PR convention keys (`subject_pattern`, `type_list`, `pr_title_pattern`, `trailer_policy`, `pr_body_attribution`, `pr_body_required_sections`, `branch_issue_pattern`) now take their team value from `docs/conventions/source-control.yaml`, validated by `schemas/source-control.schema.json`. `.claude/source-control.md` is read only for a key the YAML lacks, for one release, and a YAML the shared reader rejects stops the lookup instead of falling back. `/source-control:setup apply layer=team` writes the YAML and moves the convention keys out of the legacy file.
- `parse-branch-issue.sh` reads `branch_issue_pattern` from the team YAML before the legacy markdown, and `--explain` prints the layer that supplied the pattern on stderr. The deprecation note for the `branch_issue_pattern` userConfig now points at the YAML.

### Added

- `lib/convention-key.sh`, the team-layer reader for the convention keys: `layer ROOT KEY` prints `yaml`, `legacy-md` or `none`, and `value` and `list` print the YAML value.
