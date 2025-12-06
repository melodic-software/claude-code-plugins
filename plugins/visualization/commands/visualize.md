---
description: Generate a diagram from a natural language description using Mermaid or PlantUML
argument-hint: <description of what to diagram>
allowed-tools: Task, Read, Write, Glob, Grep
---

# Visualize Command

Generate diagrams from natural language descriptions.

## Usage

```bash
/visualization:visualize <description>
```

## Examples

```bash
/visualization:visualize a sequence diagram showing user authentication flow
/visualization:visualize class diagram for a blog with users, posts, and comments
/visualization:visualize ER diagram for an e-commerce database
/visualization:visualize flowchart for order processing with error handling
/visualization:visualize C4 context diagram for a microservices architecture
```

## Execution

Delegate to the `visualization:diagram-generator` agent with the following prompt:

---

**Task:** Generate a diagram based on the user's description.

**User's request:** $ARGUMENTS

**Instructions:**

1. Analyze the description to determine the appropriate diagram type
2. Choose between Mermaid (default) or PlantUML based on requirements
3. Generate syntactically correct diagram code
4. Return the diagram inline in a markdown code block

**Diagram Type Selection:**

- Interactions/flows between systems → Sequence diagram
- Class/object structure → Class diagram
- Database schema → ER diagram
- State transitions → State diagram
- Process/workflow → Flowchart
- Architecture overview → C4 diagram
- Timeline → Gantt chart
- Git workflow → Git graph

**Tool Selection:**

- Default to Mermaid (GitHub-native rendering)
- Use PlantUML for:
  - C4 diagrams (better support)
  - MindMaps (Mermaid doesn't support)
  - JSON visualization (Mermaid doesn't support)
  - When user explicitly requests PlantUML

**Output Format:**
Return the diagram in a markdown code block:

- For Mermaid: ```mermaid
- For PlantUML: ```plantuml

Include a brief explanation of:

- What diagram type was chosen and why
- Any assumptions made
- Suggestions for customization
