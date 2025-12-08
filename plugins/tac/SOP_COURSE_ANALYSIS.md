# SOP: Video Course Analysis for Plugin Development

## Purpose

This Standard Operating Procedure documents the process for analyzing video-based courses to extract Claude Code plugin components (skills, subagents, commands, memory files).

## Prerequisites

### Required Source Materials (Per Lesson)

```text
lessons/lesson-XXX-{slug}/
  video.md        # Video metadata (title, duration, URL)
  lesson.md       # Structured lesson summary
  captions.txt    # Full video transcript
  links.md        # External resources mentioned
  repos.md        # Companion repository references
  images/         # Screenshots and visual aids
```markdown

### Output Structure

```text
analysis/
  lesson-XXX-analysis.md    # Per-lesson analysis
  CONSOLIDATION.md          # Cross-lesson synthesis
```yaml

---

## Phase 1: Content Ingestion

### Step 1.1: Read Video Metadata

```markdown
Read: lessons/lesson-XXX-{slug}/video.md
Extract:

- Title
- Duration
- URL (for reference only)
```markdown

### Step 1.2: Read Lesson Summary

```markdown
Read: lessons/lesson-XXX-{slug}/lesson.md
Extract:

- Core tactic name
- Key frameworks
- Implementation patterns
- Anti-patterns
```markdown

### Step 1.3: Read Full Transcript

```markdown
Read: lessons/lesson-XXX-{slug}/captions.txt
Extract:

- Direct quotes (for accuracy)
- Detailed explanations not in summary
- Examples and code snippets
- Nuanced insights
```markdown

**Critical:** The transcript contains the complete instructor voice. Do not skip this step - summaries miss important context.

### Step 1.4: Read Links and Repository References

```markdown
Read: lessons/lesson-XXX-{slug}/links.md
Read: lessons/lesson-XXX-{slug}/repos.md
Extract:

- Companion repository URLs
- External documentation references
```yaml

### Step 1.5: Explore Companion Repository (If Available)

For each companion repo referenced:

1. **Clone or access the repository**
2. **Read README.md** - Project overview
3. **Read .claude/settings.json** - Permission configuration
4. **Read .claude/commands/*.md** - All slash commands
5. **Read adws/*.py** - AI Developer Workflow scripts
6. **Read specs/*.md** - Example plans/specifications
7. **Identify patterns** - Naming conventions, file organization

**Priority files to read:**

- `README.md`
- `.claude/settings.json`
- `.claude/commands/*.md` (all of them)
- `adws/README.md`
- `adws/adw_*.py` (main workflow scripts)
- Any `*_system.md` or `*_prompt.md` files

---

## Phase 2: Analysis Document Creation

### Step 2.1: Create Analysis File

Create `analysis/lesson-XXX-analysis.md` with the following template:

```markdown
# Lesson X Analysis: {Title} - {Subtitle}

## Content Summary

### Core Tactic

**{Tactic Name}** - {One-sentence description of the tactic}

### Key Frameworks

{Tables and descriptions of frameworks introduced}

### Implementation Patterns from Repo (tac-X)

{Code examples and patterns from companion repository}

### Anti-Patterns Identified

{List of anti-patterns mentioned}

### Metrics/KPIs

{How this lesson connects to agentic coding KPIs}

## Extracted Components

### Skills

| Name | Purpose | Keywords |
| ---- | ------- | -------- |
| {skill-name} | {purpose} | {keywords} |

### Subagents

| Name | Purpose | Tools |
| ---- | ------- | ----- |
| {agent-name} | {purpose} | {tool list} |

### Commands

| Name | Purpose | Arguments |
| ---- | ------- | --------- |
| /{command} | {purpose} | {arguments} |

### Memory Files

| Name | Purpose | Load Condition |
| ---- | ------- | -------------- |
| {filename}.md | {purpose} | {when to load} |

## Key Insights for Plugin Development

{High-value components and implementation notes}

### Key Quotes

> "{Direct quote from transcript}"

## Validation Checklist

- [ ] Read video.md (metadata)
- [ ] Read lesson.md (structured summary)
- [ ] Read captions.txt (full transcript)
- [ ] Explored companion repository
- [ ] Identified all extractable components
- [ ] Cross-referenced with previous lessons

## Cross-Lesson Dependencies

- **Builds on Lesson X**: {relationship}
- **Sets up Lesson Y**: {relationship}

## Notable Implementation Details

{Code snippets, configuration examples, architectural patterns}

---

**Analysis Date:** {YYYY-MM-DD}
**Analyzed By:** {Model/Agent}
```yaml

### Step 2.2: Component Extraction Guidelines

#### Skills

Extract as a skill when:

- There's a repeatable workflow or decision process
- The concept requires multi-step guidance
- Users need help selecting between options
- The pattern applies across multiple contexts

**Naming convention:** `{noun-phrase}` (e.g., `template-engineering`, `context-audit`)

#### Subagents

Extract as a subagent when:

- A focused agent with specific tools would be useful
- The task benefits from delegation
- Context isolation improves results
- The pattern is reusable across codebases

**Naming convention:** `{role-noun}` (e.g., `plan-generator`, `test-runner`)

#### Commands

Extract as a command when:

- There's a concrete action to perform
- The action takes arguments
- Users would invoke this repeatedly
- The pattern maps to a slash command

**Naming convention:** `/{verb-noun}` (e.g., `/chore`, `/implement`, `/test`)

#### Memory Files

Extract as a memory file when:

- Information should be loaded into agent context
- The content is reference material (not workflow)
- Conditional loading based on task type is useful
- The content rarely changes

**Naming convention:** `{topic-phrase}.md` (e.g., `12-leverage-points.md`)

---

## Phase 3: Consolidation

### Step 3.1: Create Consolidation Document

After all lessons are analyzed, create `analysis/CONSOLIDATION.md`:

1. **Executive Summary** - Overview of course and tactics
2. **Key Frameworks Reference** - All frameworks in one place
3. **Plugin Component Specification** - Deduplicated lists:
   - Skills (with descriptions and keywords)
   - Subagents (with tools)
   - Commands (with arguments)
   - Memory Files (with load conditions)
4. **Implementation Patterns** - Reusable code templates
5. **Key Quotes** - Best quotes from all lessons
6. **Anti-Patterns Summary** - All anti-patterns in one table
7. **Validation Status** - What's been validated

### Step 3.2: Deduplication

During consolidation:

- Merge similar skills into one
- Combine related memory files
- Identify overlapping commands
- Note cross-lesson dependencies

### Step 3.3: Prioritization

Rank components by:

1. **Frequency** - How often the pattern appears
2. **Impact** - How much value it provides
3. **Uniqueness** - Is this available elsewhere?
4. **Complexity** - How hard to implement?

---

## Phase 4: Validation

### Step 4.1: Cross-Reference with Official Docs

For each extracted component:

1. Verify terminology matches official Claude Code docs
2. Confirm tool names and capabilities are accurate
3. Validate configuration patterns are current
4. Note any outdated patterns that need updating

### Step 4.2: Test Patterns

For critical patterns:

1. Create minimal test cases
2. Verify commands work as documented
3. Test skill workflows
4. Validate subagent tool combinations

---

## Best Practices

### Do's

- **Read the full transcript** - Summaries miss nuance
- **Explore every repository file** - Hidden gems in config files
- **Cross-reference lessons** - Concepts build on each other
- **Quote directly** - Preserve instructor voice
- **Note timestamps** - Reference specific video moments
- **Track dependencies** - Lesson X builds on Lesson Y

### Don'ts

- **Don't skip the transcript** - It's the primary source
- **Don't assume from summaries** - Verify in transcript
- **Don't ignore companion repos** - They contain working code
- **Don't create duplicates** - Consolidate similar concepts
- **Don't over-extract** - Not every mention is a component

### Context Management

For large courses (10+ lessons):

- Process 3-4 lessons per session
- Save analysis files after each lesson
- Use todo lists to track progress
- Create checkpoints with consolidation updates

---

## Output Artifacts

### Per-Lesson

| File | Purpose |
| ---- | ------- |
| `lesson-XXX-analysis.md` | Detailed analysis |

### Per-Course

| File | Purpose |
| ---- | ------- |
| `CONSOLIDATION.md` | Synthesized components |
| `SOP_COURSE_ANALYSIS.md` | This document |

### Plugin Components (Post-Validation)

| Directory | Contents |
| --------- | -------- |
| `skills/` | Skill YAML and markdown |
| `agents/` | Subagent configurations |
| `commands/` | Slash command templates |
| `memory/` | Memory file content |

---

## Metrics

### Analysis Quality Indicators

| Metric | Target |
| ------ | ------ |
| Transcript coverage | 100% read |
| Repo files read | All .claude/, adws/, specs/ |
| Components per lesson | 3-8 meaningful components |
| Cross-references | Every lesson links to others |
| Validation checklist | All items checked |

### Time Estimates

| Phase | Time (per lesson) |
| ----- | ----------------- |
| Content ingestion | 15-30 minutes |
| Analysis writing | 20-40 minutes |
| Consolidation | 30-60 minutes (total) |
| Validation | 15-30 minutes (total) |

---

## Troubleshooting

### Context Window Limits

**Problem:** Can't process all lessons in one session.

**Solution:**

1. Process 3-4 lessons per session
2. Save analysis files immediately after creation
3. Create a plan file to track progress
4. Use todo list for cross-session continuity

### Missing Companion Repos

**Problem:** Repository not accessible.

**Solution:**

1. Focus on transcript and lesson summary
2. Note "Repository not explored" in validation checklist
3. Infer patterns from code snippets in transcript
4. Mark components as "needs validation"

### Conflicting Information

**Problem:** Transcript says X, summary says Y.

**Solution:**

1. Transcript is authoritative (instructor's actual words)
2. Note the discrepancy in analysis
3. Use transcript version for components
4. Flag for validation

---

## Version History

| Version | Date | Changes |
| ------- | ---- | ------- |
| 1.0 | 2025-12-04 | Initial SOP from TAC course analysis |

---

**Last Updated:** 2025-12-04
**Author:** Claude Code (Opus 4.5)
