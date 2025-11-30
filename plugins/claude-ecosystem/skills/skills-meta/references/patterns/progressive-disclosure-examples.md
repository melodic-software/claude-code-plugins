# Progressive Disclosure Examples

Query patterns for finding official progressive disclosure documentation and examples.

## Official Documentation Query

For complete progressive disclosure guidance, query official-docs:

```text
Find documentation about progressive disclosure using keywords: progressive disclosure, skill organization, token efficiency, layered content
```

## Common Queries

**For progressive disclosure concept:**
**Query official-docs:** "Find official documentation about progressive disclosure pattern for skills"

**For implementation examples:**
**Query official-docs:** "Find progressive disclosure implementation examples and patterns"

**For token efficiency strategies:**
**Query official-docs:** "Find token efficiency and context window optimization for skills"

**For reference file organization:**
**Query official-docs:** "Find documentation about organizing references and conditional loading"

## Progressive Disclosure Principles (Metadata Only)

> **Note:** This is a quick summary. Query official-docs for authoritative specification.

**Three Layers:**

1. **Layer 1 (Always Loaded)**: YAML frontmatter (name, description)
2. **Layer 2 (Loaded on Skill Activation)**: SKILL.md body
3. **Layer 3 (Loaded on Demand)**: references/ files

**Key Benefits:**

- Token efficiency (only load what's needed)
- Context window optimization
- Faster skill activation
- Scalable content organization

**Example Directory Structure:**

```text
.claude/skills/my-skill/
├── SKILL.md                    # Layer 2: under 500 lines, ~3k tokens (hub)
├── references/
│   ├── workflows/
│   │   ├── setup-workflow.md   # Layer 3: Loaded on demand
│   │   └── validation-workflow.md
│   ├── patterns/
│   │   └── common-patterns.md
│   └── metadata/
│       └── keywords.md
├── scripts/
│   └── validate.py             # Executed, not loaded into context
└── assets/
    └── template.md             # Used in output, not loaded
```

**Token Savings Estimates:**

- Without progressive disclosure: ~15,000 tokens (all content in SKILL.md)
- With progressive disclosure: ~3,000 tokens (hub only) + on-demand loading
- Typical savings: 60-80% reduction in initial context usage

**For detailed implementation guidance, examples, and best practices**, query official-docs using the patterns above.

## Decision Tree

**When to use progressive disclosure?**

1. **Skill exceeds size threshold** → Use progressive disclosure (for current threshold, see SKILL.md#specifications-quick-reference)
2. **Skill has reference material** → Move to references/ directory
3. **Skill has examples** → Conditional load via references
4. **Skill has detailed specs** → Progressive disclosure recommended

For implementation workflow and current thresholds, query official-docs: "Find progressive disclosure implementation workflow and best practices"
