# The bundled `claude-code-docs` skill: verification record

Detail behind the `## Boundary` section in [SKILL.md](../SKILL.md). Each row is a four-part
record: our decision, the pointer to read live, the date it was derived, and the event that makes
it worth deriving again.

| Decision | Pointer | As of | Recheck when |
|---|---|---|---|
| We treat `claude-code-docs` as the native surface for a quick answer about a Claude Code feature, and this skill as the read of one named page whose answer rests on that page's text | Upstream documents no page for it: the [skills: bundled skills](https://code.claude.com/docs/en/skills#bundled-skills) section names example bundled skills and does not list it. Our basis is a read of the installed 2.1.314 binary, where it registers as a model-invocable bundled skill described as answering questions about Claude Code features | 2026-10-31 | A release renames or removes it, makes it model-disabled, or that section starts listing it |
| We never assume `claude-code-docs` is present: the bundled-skill switches can hide it | [`disableBundledSkills`](https://code.claude.com/docs/en/settings-reference#disablebundledskills); [skills: override skill visibility](https://code.claude.com/docs/en/skills#override-skill-visibility-from-settings) | 2026-10-31 | Either page changes which switch hides a bundled skill |
