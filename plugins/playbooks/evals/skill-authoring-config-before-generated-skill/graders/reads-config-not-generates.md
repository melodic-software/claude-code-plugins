---
type: llm
arm: both
---
The section being rewritten detected the repository's linter, then wrote a copy of the whole skill into the repository's `.claude/skills/lint-here/` with the linter's name filled in, and told the user to use that copy from then on. The copy differs from the shipped skill only in the linter's name, which repository configuration can hold.

PASS only if all three hold in the rewritten section:

1. It no longer writes a copy of the skill (or any generated skill) into the repository, and no longer sends the user to a `/lint-here` skill.
2. It records the detected linter name in repository configuration (a config file or config entry the skill reads), not in a skill file.
3. The shipped skill itself reads that configured name on later runs; detection still happens when no name is configured.

FAIL if a per-repository skill is still generated, in full or as an option offered beside config; if the linter name is stored only in a generated skill; or if the section drops detection without saying where the name comes from.
