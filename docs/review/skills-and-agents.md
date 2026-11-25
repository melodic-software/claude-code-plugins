# Skills and agents

- Skill and agent bodies never restate a volatile upstream specific (behavior, limit, default,
  version), even with a stamp; they point at the exact section, and the pointer carries no as-of
  date or recheck trigger (a copied or measured upstream number or string keeps both):
  [rule](../../.claude/rules/skill-bodies-state-current-rules.md).
- Skill and agent text meets the skill standard, and a cut to an existing skill ships only with
  eval evidence of no loss, except a restated upstream fact swapped for a pointer:
  [skill criteria](../../plugins/playbooks/skills/skill-authoring/reference/skill-criteria.md). A PR
  held for that evidence is released by its record:
  [Cross-lane PR hold](../contracts/loop-lane/README.md#cross-lane-pr-hold).
- A generic skill names no `gh` command or GitHub grammar unless it sits behind the operation's
  owner or in a declared-provider surface (a plugin whose purpose is one provider, or an adapter):
  provider commands, API fields and link grammar are implementation details that the consumer's
  conventions and adapter binding select, and a skill that hardcodes them sets the precedent every
  new skill copies. Forge work goes to `/source-control:pull-request`, tracker work to the
  work-item-tracker seam; a full forge seam waits for a named consumer on a second forge, since a
  contract shaped by GitHub alone would freeze while the PR surface still changes.
- A generic skill or agent ships no model-read language, framework, tool or library choice outside
  the named exceptions; it resolves the choice from the consumer repository:
  [ADR 0101](../adr/0101-resolve-ecosystem-specifics-from-the-consumer-repository.md). Nor does it
  ship an ecosystem-specific example (a code sample for one stack, a link to one tool's docs):
  [plugin philosophy](../plugin-philosophy.md#hardcoded-consumer-specifics).
- A new skill that recommends, places or builds enforcement, or an instruction, reads the
  enforcement ladder, prefers the strongest tier that can decide the matter, and discovers the
  consumer's tooling first:
  [enforcement ladder](../contracts/enforcement-ladder/README.md),
  [ecosystem resolution](../contracts/ecosystem-resolution/README.md).
- Cross-plugin citations name the skill by `/plugin:skill`, never by path:
  [plugin philosophy](../plugin-philosophy.md#configuration-ownership-and-scope).
- A new standing instruction names its observed-stumble evidence:
  [instruction economy](../plugin-philosophy.md#instruction-economy).
- A new taste number in a user-interface reference names a key, and a key name follows the shape
  rules in [`reference/values.md`](../../plugins/user-interface/reference/values.md).
