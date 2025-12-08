# The Stakeholder Trifecta

Engineering for three audiences: you, your team, and your agents. This is the stakeholder trifecta for the age of agents.

## The Three Stakeholders

| Stakeholder | Purpose | Communication Focus |
| ------------- | --------- | --------------------- |
| **You** | Current self, future reference | Quick understanding, recall |
| **Your Team** | Collaboration, shared workflows | Consistent format, clear purpose |
| **Your Agents** | Execution, automation | Direct language, precise instructions |

## Communicating to Each

### Stakeholder 1: You

**Purpose:** Quick understanding and future reference.

When you return to a prompt weeks later:

- Can you quickly understand what it does?
- Is the purpose clear?
- Are there hints for how to use it?

**Best Practices:**

- Clear, descriptive titles
- Purpose section explaining "why"
- Argument hints in metadata
- Comments for non-obvious logic

### Stakeholder 2: Your Team

**Purpose:** Consistent format, clear purpose for collaboration.

When teammates use your prompts:

- Can they find what they need?
- Is the format familiar?
- Is the purpose discoverable?

**Best Practices:**

- Consistent structure across prompts
- Descriptive `description` in frontmatter
- Standard section ordering
- Documentation of expected inputs/outputs

### Stakeholder 3: Your Agents

**Purpose:** Direct language, precise instructions for execution.

When agents execute your prompts:

- Are instructions unambiguous?
- Is the workflow clear?
- Are edge cases handled?

**Best Practices:**

- Direct, imperative language
- Numbered sequential steps
- Explicit STOP conditions
- Clear variable references

## Consistency: The Greatest Weapon

> "Consistency is the greatest weapon against confusion for both you and your agent."

| Inconsistent | Consistent |
| -------------- | ------------ |
| Different structures every time | Same sections in same order |
| Varying variable styles | SCREAMING_SNAKE_CASE always |
| Random file locations | Standard directories |
| Ad-hoc output formats | Report templates |

## The Agentic Shift

Most engineers haven't made this shift:

```text
Traditional: Code -> Tests -> Deploy
             (Writing for machines)

Agentic:     Prompts -> Agents -> Results
             (Writing for agents)
```markdown

**Key Mindset Changes:**

1. Prompts are first-class engineering artifacts
2. Communication clarity is a core skill
3. Three audiences must all understand
4. Consistency scales better than cleverness

## Communication Checklist

Before finalizing a prompt:

### For You

- [ ] Will I understand this in 3 months?
- [ ] Is the purpose obvious from the title?
- [ ] Are there breadcrumbs for context?

### For Your Team

- [ ] Does it follow team conventions?
- [ ] Is the description searchable?
- [ ] Can someone else run this without asking?

### For Your Agents

- [ ] Are instructions unambiguous?
- [ ] Is the workflow step-by-step?
- [ ] Are failure modes handled?

## The Force Multiplier Effect

```text
One well-crafted prompt
     |
     v
Understood by you (maintainable)
     |
     v
Shared with team (scalable)
     |
     v
Executed by agents (automated)
     |
     v
Tens to hundreds of hours of productive work
```yaml

## Key Quote

> "Engineering for three audiences: you, your team, and your agents. This is the stakeholder trifecta for the age of agents."

---

**Cross-References:**

- @seven-levels.md - Levels build communication complexity
- @prompt-sections-reference.md - Sections for each audience
- @tac-philosophy.md - Commander of Compute mindset
