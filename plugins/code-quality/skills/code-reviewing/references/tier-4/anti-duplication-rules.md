# Anti-Duplication Rules

Content quality checks enforcing single source of truth principle. Prevents duplicate content across repository.

## Core Principle

- [ ] Every piece of information exists in EXACTLY ONE authoritative location
- [ ] All other references link to that location
- [ ] No copy-paste of content between files

**Detection:** Compare content across files for similarities; search for repeated configuration examples, version numbers, or instruction blocks

**Rationale:** DRY principle - update once, accuracy everywhere

## Version Information

### Single Source of Truth for Versions

- [ ] Version info lives in ONE "Last Verified" section (typically SKILL.md)
- [ ] All other files reference this location
- [ ] Format: `Latest version: see [SKILL.md Last Verified](../SKILL.md#last-verified)`

**Canonical location format:**

```markdown
## Last Verified

**Date**: YYYY-MM-DD

**Tool Versions Tested**:

- tool-name: 1.2.3+
- another-tool: 2.0.0
```

**Detection:** Search for version numbers scattered across multiple files

**Rationale:** When versions change, update ONE place; all references automatically stay current

## Hub-and-Spoke Content

### Hub Files

- [ ] Hub files contain NO duplicate content from spokes
- [ ] Hub files link to spokes with brief context only
- [ ] Each topic exists in exactly ONE spoke

**Detection:** Check hub files for detailed instructions that belong in spoke files

**Rationale:** Navigation vs detailed content - clear separation of concerns

### Spoke Files

- [ ] Spoke files contain complete details
- [ ] No content duplicated from other spokes
- [ ] Self-contained (can be read independently)

**Detection:** Compare spoke files for overlapping detailed content

**Rationale:** Single authoritative source per topic

## Configuration Examples

- [ ] Configuration examples exist in ONE canonical location
- [ ] Other files link to canonical example
- [ ] Format: `For configuration example, see [main-doc.md#configuration](main-doc.md#configuration)`

**Detection:** Search for repeated code blocks, JSON/YAML config examples

**Rationale:** Configuration changes propagate from single source

## Reports and Summaries

### Creating Reports

- [ ] ONE comprehensive report per task/topic (not multiple overlapping reports)
- [ ] Report contains all sections: Executive Summary, Detailed Findings, Verification, Recommendations
- [ ] No separate "findings", "verification", "summary" reports

**Detection:** Look for multiple temp files with overlapping timestamps/topics

**Rationale:** Consolidation prevents fragmented information and conflicting data

### Report Naming

- [ ] Descriptive, consolidated names
- [ ] Format: `YYYY-MM-DD_topic-complete-audit.md`
- [ ] Avoid: Multiple reports with same date/topic but different suffixes

**Example:**

- Good: `2025-11-28_markdown-linting-complete-audit.md`
- Bad: `...-audit.md` + `...-verification.md` + `...-findings.md`

**Detection:** Find multiple temp files matching pattern `YYYY-MM-DD_topic-*.md`

**Rationale:** Single comprehensive document easier to review and maintain

## Instruction Duplication

### Documentation and Guides

- [ ] Setup instructions exist in ONE authoritative file
- [ ] Other files link to setup guide (no copy-paste)
- [ ] Troubleshooting steps not duplicated across files

**Detection:** Search for repeated command sequences, installation steps

**Rationale:** Instructions change over time - updating multiple copies leads to inconsistency

### Command Examples

- [ ] Command examples in ONE canonical location per use case
- [ ] Other references link or briefly mention with pointer
- [ ] No repeated "how to do X" blocks

**Detection:** Find repeated bash/PowerShell command blocks

**Rationale:** Commands evolve - single source ensures accuracy

## Consolidation Strategies

### When Duplication is Found

1. Identify all instances of duplicated content
2. Choose canonical location (most appropriate file)
3. Consolidate content to ONE location
4. Replace duplicates with links to canonical location
5. Verify all links work correctly

**Detection:** Diff files to find identical or near-identical sections

**Rationale:** Proactive deduplication prevents accumulation of stale copies

### Choosing Canonical Location

- [ ] Most specific/detailed file wins for detailed content
- [ ] SKILL.md wins for version information
- [ ] Main topic file wins for core instructions
- [ ] Reference files win for deep-dive content

**Detection:** Evaluate file purpose and scope to determine canonical location

**Rationale:** Content lives where it logically belongs

## Enforcement Checklist

### Before Creating Content

- [ ] Search for similar content: `grep -r "key phrase" .`
- [ ] Check related files in same directory
- [ ] Look for existing documentation on topic

### If Similar Content Exists

- [ ] Link to existing content (do NOT create duplicate)
- [ ] Update existing content if it needs improvement
- [ ] Refactor to consolidate if content is scattered

### If Content is Truly New

- [ ] Create in ONE canonical location
- [ ] Link to it from other places that need it
- [ ] Document why this is the authoritative source

**Detection:** Manual review during content creation

**Rationale:** Prevention better than cleanup

## Red Flags (Duplication Indicators)

- [ ] Multiple temp reports on same topic
- [ ] Copy-pasting content between files
- [ ] Same instructions in multiple locations
- [ ] Repeated version numbers in multiple files
- [ ] Duplicate configuration examples
- [ ] Same troubleshooting steps in multiple places
- [ ] Identical command examples across files

**Detection:** Code review, grep for repeated patterns

**Rationale:** Early detection prevents duplication from becoming entrenched

## Common Violations

**High severity:**

1. Configuration examples duplicated in 3+ files
2. Version information scattered (not in single Last Verified section)
3. Multiple reports on same topic with overlapping content
4. Installation instructions copy-pasted across guides

**Medium severity:**

1. Troubleshooting steps repeated in 2 files
2. Command examples duplicated (without linking)
3. Brief instructions repeated when link would suffice

**Low severity:**

1. Example outputs repeated verbatim
2. Minor phrasing overlap (acceptable if not verbatim duplication)

## Proactive Consolidation

- [ ] When duplication found during ANY task, point it out
- [ ] Offer to consolidate if user agrees
- [ ] For obvious duplications (multiple temp reports, same config in 3+ files), consolidate immediately
- [ ] For structural changes (published docs, external links), ask permission first

**Rationale:** Continuous improvement - fix duplication when encountered, prevent accumulation
