# Skill Naming Conventions

Metadata and query patterns for skill naming guidance.

## Official Documentation Query

For complete naming conventions, query docs-management:

```text
Find documentation about skill naming conventions using keywords: skill naming, naming best practices, naming patterns
```

## Quick Reference (Metadata Only)

> **Note:** This is a quick summary. Query docs-management for authoritative specification.

**Official Requirements:**

- Lowercase letters, numbers, hyphens only (`a-z`, `0-9`, `-`)
- Within official character limit (query docs-management for current limits)
- MUST match directory name
- Cannot contain reserved words (query docs-management for current list)
- See docs-management for complete specification

**The Sentence Test:**
"I'm going to reach for the [skill-name] skill" should sound natural.

**Common Patterns:**

- Gerund form: `markdown-linting`, `code-reviewing`
- Noun form: `version-control`, `api-client`
- See docs-management for detailed pattern guidance and examples

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
| `skill-development` | `skill-manager` | Domain noun vs agent noun |
| `pdf-processing` | `pdf-processor` | Gerund vs agent noun |

## Common Queries

**For naming pattern examples:**
**Query docs-management:** "Find skill naming examples and recommended patterns"

**For anti-patterns and mistakes:**
**Query docs-management:** "Find common skill naming mistakes and anti-patterns"

**For name validation:**
**Query docs-management:** "Find skill naming validation requirements and constraints"

**For choosing between patterns:**
**Query docs-management:** "Find guidance on choosing between gerund and noun naming patterns"

## Decision Tree

**What does your skill do?**

1. **Performs a process** → Gerund form (-ing)
   - Example: `markdown-linting`, `git-committing`, `code-reviewing`
   - **Query docs-management:** "Find examples of process-based skill names"

2. **Represents a domain/concept** → Noun form
   - Example: `skill-development`, `version-control`, `api-client`
   - **Query docs-management:** "Find examples of domain-based skill names"

3. **Uncertain which pattern** → Test with Sentence Test
   - **Query docs-management:** "Find guidance on The Sentence Test for skill naming"

## Validation Workflow

When naming a new skill:

1. Query docs-management for current naming conventions
2. Apply The Sentence Test ("I'm going to reach for the [skill-name] skill")
3. Check against official requirements (query docs-management for current limits)
4. Verify no reserved words ("anthropic", "claude")
5. Ensure directory name matches YAML name field

For complete naming workflow, query docs-management: "Find skill naming workflow and validation procedures"
