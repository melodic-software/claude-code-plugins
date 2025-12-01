---
description: List all available Skills with their descriptions
model: claude-haiku-4-5-20251001
allowed-tools:
---

# List Skills

List all available skills from the Skill tool's built-in available skills list.

Format each skill as:

```text
### **skill-name**
Concise description (1-2 sentences max). Use when: [key use cases].
```

Requirements:

- Use bold markdown for skill names (### **name**)
- Add horizontal rule separator (---) between skills
- Keep descriptions concise - max 2-3 lines per skill
- Combine "Use when" into the description flow naturally
- Show total count at the end

Do NOT use bash scripts or filesystem searches - just output the list from your internal knowledge of the Skill tool.
