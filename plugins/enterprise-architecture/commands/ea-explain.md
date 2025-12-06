---
description: Explain an enterprise architecture concept
argument-hint: <concept>
allowed-tools: Read, Glob, Grep, Skill
---

# Explain Enterprise Architecture Concept

Explain an EA concept in practical, developer-friendly terms.

## Arguments

`$ARGUMENTS` - The concept to explain (e.g., "TOGAF", "ADR", "Zachman Framework", "landing zone")

## Workflow

1. **Invoke the ea-learning skill** with the concept argument
2. **Provide a practical explanation** that:
   - Explains what it is in plain terms
   - Shows why it matters for developers/architects
   - Gives concrete examples when possible
   - Links to related concepts
3. **Reference relevant memory files** if they exist

## Example Usage

```bash
/ea:explain TOGAF
/ea:explain ADR
/ea:explain Zachman Framework
/ea:explain landing zone
/ea:explain architecture principle
```

## Output

A clear, practical explanation of the concept that helps developers and architects understand and apply it.
