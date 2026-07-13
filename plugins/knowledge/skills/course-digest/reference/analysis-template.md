# Analysis Template

Templates for Phase 5 (Recommend) outputs. Primary deliverables of the skill.

## repo-candidates.md

```markdown
# Repo Candidates: {Course Title}

**Course:** {title} by {instructor}
**Platform:** {platform}
**Analyzed:** {date}

## Already implemented

Patterns from this course that we already follow (validation that our approach aligns):

- **{Pattern name}** — {brief description}. We do this via {our implementation}.
  - Course reference: Module "{module}", Lesson "{lesson}"

## High-priority candidates

Patterns with high relevance and reasonable adoption effort:

### {Candidate title}

- **What:** {what the course teaches}
- **Why it matters for us:** {specific relevance to our repo}
- **Current state:** {what we do now, or "not implemented"}
- **Adoption path:** {concrete steps to adopt}
- **Effort:** Low / Medium / High
- **Course reference:** Module "{module}", Lesson "{lesson}"

## Medium-priority candidates

Worth considering but lower urgency or higher effort:

### {Candidate title}

(same structure as high-priority)

## Not applicable

Course content that doesn't fit our context (documented so we don't revisit):

- **{Topic}** — {why it doesn't apply}. (e.g., "uses NUnit-specific features; we use xUnit")
```

## action-items.md

```markdown
# Action Items: {Course Title}

Concrete next steps derived from course analysis. Each item maps to a repo mechanism.

## CLAUDE.md / .claude/rules/ candidates

Rules or conventions worth codifying:

- [ ] **{Rule description}** — Add to `{target file}`.
  Rationale from course: {why the instructor advocates this}
  - Source: "{lesson title}"

## Skill candidates

New skills suggested by course patterns:

- [ ] **/{skill-name}** — {what it would do}.
  Inspired by: {course concept}

## Architecture patterns

Structural changes to consider:

- [ ] **{Pattern}** — {description and where it applies}
  - Current: {what we have}
  - Proposed: {what the course suggests}
  - Source: "{lesson title}"

## Testing practices

Improvements to testing approach:

- [ ] **{Practice}** — {description}
  - Source: "{lesson title}"

## CI/CD improvements

Pipeline or workflow changes:

- [ ] **{Improvement}** — {description}

## /work-items items

Items to add to the maintenance backlog:

- [ ] **{Item}** — {description}. Priority: {P1/P2/P3}
```

## course-summary.md

```markdown
# Course Summary: {Course Title}

**Instructor:** {name}
**Platform:** {platform}
**Duration:** {total duration}
**Lessons:** {count}
**Analyzed:** {date}

## Instructor's philosophy

{2-3 sentences capturing the instructor's core approach and values}

## Key themes

1. **{Theme}** — {description spanning multiple modules}
2. ...

## Module summaries

### {Module 1 title}

{2-3 sentence summary}. Key takeaways: {bulleted list}

### {Module 2 title}

...

## Cross-cutting observations

{Patterns or tensions that span the entire course}

## Relevance to our stack

{High-level assessment of how this course maps to our .NET / C# / Aspire / modular monolith context}
```
