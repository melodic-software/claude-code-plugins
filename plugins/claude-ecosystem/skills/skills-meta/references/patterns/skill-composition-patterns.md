# Skill Composition Patterns

Query patterns for finding official skill composition documentation and examples.

## Official Documentation Query

For complete skill composition guidance, query official-docs:

```text
Find documentation about skill composition using keywords: skill composition, skills invoking skills, modular skills
```

## Common Queries

**For composition concept:**
**Query official-docs:** "Find official documentation about skill composition and modular skill architecture"

**For implementation examples:**
**Query official-docs:** "Find skill composition implementation examples and patterns"

**For invocation syntax:**
**Query official-docs:** "Find documentation about how skills invoke other skills"

**For composition best practices:**
**Query official-docs:** "Find skill composition best practices and anti-patterns"

## Skill Composition Principles (Metadata Only)

> **Note:** This is a quick summary. Query official-docs for authoritative specification.

**Core Concept:**
Skills can invoke other skills for modular, reusable functionality.

**Use Cases:**

- Delegating specialized tasks
- Building complex workflows from simpler skills
- Avoiding duplication across skills
- Creating skill hierarchies

**Basic Pattern:**

```markdown
For [specific task], use the [other-skill-name] skill to [accomplish subtask].

[Continue with rest of workflow using the result...]
```

**Documentation Delegation Pattern (Type B Meta-Skill):**

```markdown
## Querying Official Documentation

For authoritative [topic] guidance, delegate to official-docs:

**Query official-docs:** "Find documentation about [topic] using keywords: [keyword1], [keyword2]"

This ensures always-current official documentation without duplication.
```

This pattern is used by meta-skills (like skills-meta) to avoid duplicating official documentation while still providing comprehensive guidance.

**For detailed implementation guidance, examples, and best practices**, query official-docs using the patterns above.

## Decision Tree

**When to use skill composition?**

1. **Task requires specialized knowledge** → Delegate to specialized skill
2. **Functionality exists in another skill** → Compose instead of duplicate
3. **Building complex workflow** → Compose from simpler skills
4. **Need modular architecture** → Design with composition in mind

For implementation workflow, query official-docs: "Find skill composition implementation workflow and patterns"
