/playbooks:skill-authoring. Rewrite this section of my skill's SKILL.md so it meets our skill criteria. Print only the rewritten section in your reply; do not write any file.

## Ship the fix

1. Run the unit tests for the package you touched.
2. Stage only the files you changed, each by name; never `git add -A`.
3. Write the commit subject in Conventional Commits form, `<type>(<scope>): <subject>`, under 72 characters.
4. Add the co-author trailer as the last line of the message.
5. Commit with a heredoc so the message keeps its line breaks.
6. Add a line to `docs/fixes.md` naming the bug and the commit.

Author's note, not part of the section: steps 2 to 5 come from our `/source-control:commit` skill. I copied them in on purpose, so this section is self-contained and the agent never has to load a second skill to ship a fix. Steps 1 and 6 are this skill's own.
