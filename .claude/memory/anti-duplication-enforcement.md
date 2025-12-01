# Anti-Duplication Enforcement

**Purpose**: Strong, actionable guidance to PREVENT content duplication in all forms

## The Problem

Content duplication creates painful maintenance overhead:

- Multiple places to update when information changes
- Risk of inconsistencies and stale information
- Wasted tokens loading duplicate content
- Confusion about which version is authoritative

## The Rule (Absolute)

**EVERY piece of information exists in EXACTLY ONE authoritative location.**

If information needs to appear multiple places: **LINK, DON'T DUPLICATE.**

## Mandatory Checks Before Creating Content

### Before Writing ANY Content

**STOP and check**:

1. **Does this content already exist?**

   ```bash
   grep -r "key phrase" .
   ```

2. **Is this a variation of existing content?**
   - Check related files in same directory
   - Look for similar topics in other files
   - Search for keywords/concepts

3. **Am I about to create multiple outputs on same topic?**
   - Reports, summaries, analyses
   - -> Create ONE comprehensive document instead

### Decision Tree

```text
Need to create content?
  |
Does similar content exist?
  |-- YES -> LINK to it (do not duplicate)
  +-- NO -> Continue to next check
      |
Will content appear in multiple places?
  |-- YES -> Create in ONE canonical spot, link from others
  +-- NO -> Create content once
```

## Specific Anti-Patterns

### 1. Multiple Reports (PROHIBITED)

**NEVER DO THIS**:

```text
.claude/temp/2025-11-17_task-report-1.md
.claude/temp/2025-11-17_task-report-2.md
.claude/temp/2025-11-17_task-summary.md
.claude/temp/2025-11-17_task-findings.md
```

**ALWAYS DO THIS**:

```text
.claude/temp/2025-11-17_task-complete.md
(One comprehensive report with all sections)
```

### 2. Documentation Duplication (PROHIBITED)

**NEVER DO THIS**:

```markdown
# main.md
## Setup Instructions
Step 1: Install...
Step 2: Configure...
[50 lines]

# guide.md
## Setup Instructions
Step 1: Install...
Step 2: Configure...
[Same 50 lines]
```

**ALWAYS DO THIS**:

```markdown
# main.md
## Setup
See [Setup Guide](guide.md) for complete instructions.

# guide.md
## Setup Instructions
Step 1: Install...
Step 2: Configure...
[50 lines - exists ONLY here]
```

### 3. Version Information Scattered (PROHIBITED)

**NEVER DO THIS**:

```text
File A: "Tool version: 1.2.3"
File B: "Latest: v1.2.3"
File C: "Current version 1.2.3"
```

**ALWAYS DO THIS**:

```markdown
# SKILL.md
## Last Verified
**Tool Versions Tested**:
- tool-name: 1.2.3+

# All other files
Latest version: see [SKILL.md Last Verified](../SKILL.md#last-verified)
```

### 4. Configuration Examples (PROHIBITED)

**NEVER DO THIS**:

- Same config example in 3+ files

**ALWAYS DO THIS**:

- ONE canonical example
- All others link to it

## Canonical Locations by Type

### Version Information

**Location**: `<skill>/SKILL.md` -> "Last Verified" section
**All others**: Link with `(see SKILL.md#last-verified)`

### Configuration Examples

**Location**: Most appropriate reference file for the topic
**All others**: Link to that file

### Installation Instructions

**Location**: `references/installation-*.md` files
**All others**: Link with brief context

### Troubleshooting

**Location**: Relevant reference file for the component
**Hub files**: Brief issue + link to detailed troubleshooting

### Code Examples

**Location**: ONE authoritative file per example
**All others**: Link or @-reference

## Proactive Deduplication

### When You Find Duplication

**DO NOT wait for user to point it out.**

**Immediately**:

1. Identify all instances
2. Choose canonical location
3. Consolidate content
4. Replace duplicates with links
5. Inform user what was fixed

### Red Flags to Watch For

- **You're copy-pasting content** -> STOP, link instead
- **You're creating report #2 on same topic** -> STOP, merge into #1
- **You see same config in 2+ files** -> STOP, consolidate
- **You're writing same version in 2+ places** -> STOP, use canonical version
- **You're repeating instructions** -> STOP, link to canonical instructions

### Self-Check Questions

Before finishing ANY task:

- [ ] Did I create multiple temp files? (Consolidate if yes)
- [ ] Did I put version info in >1 place? (Use canonical if yes)
- [ ] Did I duplicate any examples? (Consolidate if yes)
- [ ] Did I copy-paste between files? (Link instead if yes)
- [ ] Could any content be a link? (Make it a link if yes)

## Hub-and-Spoke Architecture

### Pattern for Skills and Documentation

```text
SKILL.md (Hub)
|-- Overview (unique content)
|-- Quick commands (essential reference)
|-- Policy/workflow (unique to skill)
+-- Links to references (NO duplicate content)
    |-> references/setup.md (detailed instructions)
    |-> references/advanced.md (advanced topics)
    +-> references/troubleshooting.md (detailed fixes)
```

**Rules**:

- Hub: Brief overview + links, NO duplicate content from spokes
- Spokes: Complete details, each topic ONCE
- NO content appears in both hub and spoke

### Token Efficiency

**Goal**: Load only what's needed

**Hub file** (e.g., SKILL.md):

- Small, focused (300-500 lines ideal)
- Loads every time skill is invoked
- Contains only essential guidance

**Spoke files** (references):

- Detailed (can be longer)
- Loaded on-demand when specific topic needed
- Contains complete information

**Anti-pattern**: Hub file with 1000+ lines of duplicated spoke content

## Enforcement Protocol

### During Content Creation

1. **Search first**: `grep -r "topic" .` before writing
2. **Check existing files** in same directory
3. **Look for related content** in parent/sibling directories
4. **Create ONCE** in most appropriate location
5. **Link from elsewhere** if needed in multiple places

### During Task Completion

**Before reporting task complete**:

```bash
# Check for duplicate temp files
ls .claude/temp/*.md | grep "$(date +%Y-%m-%d)"

# If multiple files on same topic exist:
# -> Consolidate into ONE
```

### When Updating Content

**If updating version, configuration, or instructions**:

1. Find ALL occurrences: `grep -r "old value" .`
2. Identify canonical location
3. Update canonical location
4. Ensure all others link to canonical (don't duplicate)

## Summary: The Golden Rules

1. **ONE authoritative location** per piece of information
2. **LINK, don't duplicate** when needed elsewhere
3. **Search before creating** to find existing content
4. **Consolidate proactively** when duplication found
5. **ONE report per task**, not multiple overlapping reports
6. **Version info in ONE place** (Last Verified section)
7. **Hub-and-spoke** for documentation (hub links to spokes, no duplicate content)

**Remember**: If you're about to copy-paste, you're doing it wrong. Link instead.

**Last Updated:** 2025-11-30
