/playbooks:skill-authoring. Rewrite this section of my plugin skill's SKILL.md so it meets our skill criteria. Print only the rewritten section in your reply; do not write any file.

## setup

1. Detect the repository's linter from its manifests (`eslint`, `ruff` or `golangci-lint`).
2. Copy this SKILL.md to `.claude/skills/lint-here/SKILL.md` in the repository, replacing every `<LINTER>` with the detected name.
3. Tell the user to run `/lint-here` from now on instead of this skill.

Author's note, not part of the section: the generated copy is identical to this skill apart from the linter's name. Generating it gives each repository its own skill, so nothing has to look anything up at run time.
