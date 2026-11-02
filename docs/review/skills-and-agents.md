# Skills and agents

- Skill and agent bodies never restate a volatile upstream specific (behavior, limit, default,
  version), even with a stamp; they point at the exact section, and the pointer carries an as-of
  date and recheck trigger: [rule](../../.claude/rules/skill-bodies-state-current-rules.md).
- Skill and agent text meets the skill standard, and a cut to an existing skill ships only with
  eval evidence of no loss:
  [skill criteria](../../plugins/playbooks/skills/skill-authoring/reference/skill-criteria.md).
- A generic skill names no `gh` command or GitHub grammar unless it sits behind the operation's
  owner or in a declared-provider surface:
  [ADR 0060](../adr/0060-abstract-provider-details-in-skills-behind-consumer-conventions-and-adapters.md).
- Cross-plugin citations name the skill by `/plugin:skill`, never by path:
  [plugin philosophy](../plugin-philosophy.md#configuration-ownership-and-scope).
- A new standing instruction names its observed-stumble evidence:
  [instruction economy](../plugin-philosophy.md#instruction-economy).
