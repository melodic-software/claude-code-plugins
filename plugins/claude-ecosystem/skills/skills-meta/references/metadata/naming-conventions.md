# Skill Naming Conventions

Metadata and query patterns for skill naming guidance.

## Official Documentation Query

For complete naming conventions, query official-docs:

```text
Find documentation about skill naming conventions using keywords: skill naming, naming best practices, naming patterns
```

## Quick Reference (Metadata Only)

> **Note:** This is a quick summary. Query official-docs for authoritative specification.

**Official Requirements:**

- Lowercase letters, numbers, hyphens only (`a-z`, `0-9`, `-`)
- Within official character limit (query official-docs for current limits)
- MUST match directory name
- Cannot contain reserved words (query official-docs for current list)
- See official-docs for complete specification

**The Sentence Test:**
"I'm going to reach for the [skill-name] skill" should sound natural.

**Common Patterns:**

- Gerund form: `markdown-linting`, `code-reviewing`
- Noun form: `version-control`, `api-client`
- See official-docs for detailed pattern guidance and examples

**Avoid:**

- Agent nouns (-er, -or): `committer`, `linter`, `builder`
- Tool suffixes: `markdown-tool`, `git-helper`
- Generic terms without context: `utility`, `helper`, `manager`

**Good vs Bad Examples:**

| ✅ Good | ❌ Bad | Why |
| ------- | ------ | --- |
| `markdown-linting` | `markdown-linter` | Gerund vs agent noun |
| `git-commit` | `git-committer` | Noun vs agent noun |
| `api-client` | `api-helper` | Specific vs generic |
| `code-reviewing` | `code-review-tool` | Clean vs tool suffix |
| `skills-meta` | `skill-manager` | Domain noun vs agent noun |
| `pdf-processing` | `pdf-processor` | Gerund vs agent noun |

## Common Queries

**For naming pattern examples:**
**Query official-docs:** "Find skill naming examples and recommended patterns"

**For anti-patterns and mistakes:**
**Query official-docs:** "Find common skill naming mistakes and anti-patterns"

**For name validation:**
**Query official-docs:** "Find skill naming validation requirements and constraints"

**For choosing between patterns:**
**Query official-docs:** "Find guidance on choosing between gerund and noun naming patterns"

## Decision Tree

**What does your skill do?**

1. **Performs a process** → Gerund form (-ing)
   - Example: `markdown-linting`, `git-committing`, `code-reviewing`
   - **Query official-docs:** "Find examples of process-based skill names"

2. **Represents a domain/concept** → Noun form
   - Example: `skills-meta`, `version-control`, `api-client`
   - **Query official-docs:** "Find examples of domain-based skill names"

3. **Uncertain which pattern** → Test with Sentence Test
   - **Query official-docs:** "Find guidance on The Sentence Test for skill naming"

## Validation Workflow

When naming a new skill:

1. Query official-docs for current naming conventions
2. Apply The Sentence Test ("I'm going to reach for the [skill-name] skill")
3. Check against official requirements (query official-docs for current limits)
4. Verify no reserved words ("anthropic", "claude")
5. Ensure directory name matches YAML name field

For complete naming workflow, query official-docs: "Find skill naming workflow and validation procedures"
