# Skill-local detector wrappers

Each skill that reads the project's ecosystems carries `scripts/detect-ecosystems.sh`, a wrapper
that `exec`s the detector at the plugin root, `scripts/detect-ecosystems.sh`, with its arguments.

- **The `allowed-tools` grant names a path under `${CLAUDE_SKILL_DIR}`**, never under
  `${CLAUDE_PLUGIN_ROOT}`, so the granted script has to sit in the skill's own directory. That is a
  repository convention: the [skills docs](https://code.claude.com/docs/en/skills) say
  `${CLAUDE_PLUGIN_ROOT}` is substituted there, but this repository ships no grant on docs alone
  (`plugins/discovery/reference/parent-contract.md`).
- **The detector stays single-sourced** at the plugin root and is shared by both skills. A wrapper
  holds no detection logic, and the two wrappers have identical bodies.
- **Each wrapper locates the plugin root from its own path.** `CLAUDE_PLUGIN_ROOT` is not exported
  into the Bash tool's environment, so expanding it inside a script yields an empty string.

`lib/test-helpers.sh` (`detect_wrapper_contract`) checks each point against the wrappers, the
skills' frontmatter and this file.
