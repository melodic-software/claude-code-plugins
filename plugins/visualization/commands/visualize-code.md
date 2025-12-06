---
description: Analyze source code and generate a diagram (class, ER, sequence, or dependency)
argument-hint: <path> [diagram-type]
allowed-tools: Task, Read, Write, Glob, Grep, Bash
---

# Visualize Code Command

Analyze source code files and automatically generate appropriate diagrams.

## Usage

```bash
/visualization:visualize-code <path> [diagram-type]
```

## Arguments

- `<path>` - File or directory to analyze (required)
- `[diagram-type]` - Optional: `class`, `er`, `sequence`, `dependency` (auto-detected if omitted)

## Examples

```bash
/visualization:visualize-code src/models
/visualization:visualize-code src/services/user.service.ts class
/visualization:visualize-code prisma/schema.prisma er
/visualization:visualize-code src/routes sequence
/visualization:visualize-code src dependency
```

## Supported Analysis Types

| Type | Trigger | Input |
| --- | --- | --- |
| `class` | TypeScript/Python/Java classes | `.ts`, `.py`, `.java`, `.cs` files |
| `er` | ORM/database schemas | `schema.prisma`, `models.py`, `*.entity.ts` |
| `sequence` | API route handlers | Route files with HTTP handlers |
| `dependency` | Import statements | Any source files |

## Execution

Delegate to the `visualization:code-visualizer` agent with the following prompt:

---

**Task:** Analyze source code and generate an appropriate diagram.

**Target:** $1 (path to analyze)
**Diagram Type:** $2 (optional - auto-detect if not specified)

**Instructions:**

1. **Discover files** at the specified path using Glob
2. **Determine analysis type** based on:
   - Explicit diagram type argument (if provided)
   - File patterns and content
3. **Read and analyze** the relevant source files
4. **Extract structure**:
   - For class diagrams: classes, properties, methods, relationships
   - For ER diagrams: entities, fields, keys, relationships
   - For sequence diagrams: handlers, service calls, responses
   - For dependency diagrams: imports, module relationships
5. **Generate diagram** using Mermaid syntax (preferred for GitHub rendering)
6. **Return results** with diagram and analysis notes

**Auto-Detection Rules:**

| File Pattern | Default Type |
| --- | --- |
| `schema.prisma` | ER |
| `models.py` (Django/SQLAlchemy) | ER |
| `*.entity.ts` | ER |
| `**/routes/**`, `*_controller.*` | Sequence |
| Generic `.ts`, `.py`, `.java` | Class |

**Output Format:**

Return:

1. Brief summary of what was analyzed (files, classes, entities, etc.)
2. The generated diagram in a ```mermaid code block
3. Any limitations or incomplete analysis notes
4. Suggestions for refinement

**Example Output for Class Diagram:**

Analyzed 5 files in `src/models/`:

- User.ts (1 class, 4 methods)
- Post.ts (1 class, 3 methods)
- Comment.ts (1 class, 2 methods)

```mermaid
classDiagram
    class User {
        +String id
        +String email
        +createPost()
        +addComment()
    }
    ...
```

Note: Some private utility methods were omitted for clarity.
