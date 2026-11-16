---
type: llm
arm: both
---
The section being rewritten detected the repository's linter, then wrote a copy of the whole skill into the repository's `.claude/skills/lint-here/` with the linter's name filled in, and told the user to use that copy from then on. The copy differs from the shipped skill only in the linter's name, which repository configuration can carry.

PASS only if both hold in the rewritten section:

1. It no longer writes a copy of the skill (or any generated skill) into the repository, and no longer sends the user to a `/lint-here` skill.
2. The shipped skill itself gets the linter on each run from repository configuration: the repository's own linter config files and manifests, or a config entry the skill records there and reads back. Either counts.

FAIL if a per-repository skill is still generated, in full or as an option offered beside config; if the linter name lives only in a generated skill; or if the section no longer says where the linter comes from.
