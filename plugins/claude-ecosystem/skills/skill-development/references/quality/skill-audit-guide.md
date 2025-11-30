# Skill Audit Guide

Workflow-driven checklist for auditing Claude Code skills using official documentation.

**Pattern**: This guide provides audit workflows and query patterns. ALL validation requirements are fetched from official documentation via the `docs-management` skill.

## Overview

This guide provides a systematic workflow for auditing skills. Use this when:

- Conducting periodic skill maintenance reviews
- Validating newly created skills before deployment
- Responding to skill quality concerns
- Ensuring team skills meet organizational standards

**Audit Levels:**

1. **Quick Audit** (5-10 min): Critical issues only (YAML, structure, activation)
2. **Standard Audit** (15-30 min): Full workflow below
3. **Deep Audit** (30-60 min): Standard + testing, performance analysis

## Table of Contents

- [Pre-Audit Setup](#pre-audit-setup)
- [Pre-Flight Validation (MANDATORY)](#pre-flight-validation-mandatory)
- [Audit Workflow](#audit-workflow)
  - [1. Official Documentation Compliance](#1-official-documentation-compliance)
  - [2. YAML Frontmatter Validation](#2-yaml-frontmatter-validation)
  - [3. File Structure Validation](#3-file-structure-validation)
  - [4. Content Quality Assessment](#4-content-quality-assessment)
  - [5. Functional Quality](#5-functional-quality)
  - [6. Maintenance Quality](#6-maintenance-quality)
  - [7. Token Efficiency](#7-token-efficiency-and-progressive-disclosure)
  - [8. Testing Quality](#8-testing-quality)
  - [9. Audit Completion](#9-audit-completion)
- [Type B Meta-Skill Audits](#type-b-meta-skill-audits)
- [Common Issues and Fixes](#common-issues-and-fixes)
- [Related Resources](#related-resources)

## Pre-Audit Setup

**⚠️ OPERATIONAL WORKFLOW**: Preparation steps before beginning the audit.

Before beginning the audit:

1. **Check last audit date** from `.claude/skills/.audit-log.md`
2. **Check recent git modifications** (optional - see note below):

   ```bash
   git log --oneline --since="YYYY-MM-DD" -- .claude/skills/skill-name/
   ```

3. **Identify audit scope**: Quick, Standard, or Deep
4. **Document findings** in `.claude/temp/YYYY-MM-DD_HHmmss-audit-{skill-name}.md`

### Optional: Using Git History for Context

Git history is **valuable but optional**. Use it when you need additional context for:

- Understanding skill evolution since last audit
- Investigating design decisions (check commit messages)
- Tracing when token bloat or issues started
- Understanding multi-contributor perspectives

**Skip git history for:**

- Brand new skills (no history yet)
- Straightforward validation audits
- Time-constrained quick audits

**Rule of thumb**: Spend <5 minutes on git history if you use it at all.

## Pre-Flight Validation (MANDATORY)

**🚨 CRITICAL**: Complete these steps before touching the deeper audit workflow. If something fails, pause and remediate immediately.

### Step 1: Run Canonical Validator

```bash
python .claude/skills/skill-development/scripts/validate_yaml_frontmatter.py .claude/skills/skill-name/
```

Proceed only when the script reports `✅ PASS`. Fix issues, then re-run until clean.

### Step 2: Query Official Specification

Before validating against requirements, load the current official specification:

**Query docs-management:**

```text
Find the official YAML frontmatter specification for skills including required fields, validation rules, and constraints
```

Consult `references/metadata/yaml-frontmatter-reference.md` for query patterns if needed.

### Step 3: Record Validation Result

Note the validation timestamp and any fixes in `.claude/temp/YYYY-MM-DD_HHmmss-audit-{skill}.md`. Future auditors can see exactly when the skill last matched the canonical spec.

## Audit Workflow

### 1. Official Documentation Compliance

**ALL skill validation must follow official Claude Code documentation.**

**Query docs-management for current requirements:**

```text
Find official Claude Code skills best practices and requirements
```

**Primary documentation areas to validate:**

- YAML frontmatter structure and fields
- Description patterns ("what + when", third person, within official limits)
- File structure and organization
- Progressive disclosure patterns
- Naming conventions (gerund/noun form, no agent nouns)

**Validation checklist:**

- [ ] Query docs-management for current best practices
- [ ] Compare skill against loaded official requirements
- [ ] Document any deviations with rationale
- [ ] Flag unexplained deviations as audit findings

### 2. YAML Frontmatter Validation

**🚨 PREREQUISITE**: Pre-Flight Validation MUST pass before this section.

#### Query Official Requirements

Before checking fields, query docs-management:

```text
Find YAML frontmatter validation requirements for skills including field whitelist, required fields, and validation constraints
```

#### Validation Workflow

1. **Load official field whitelist** from docs-management
2. **Verify only valid fields present** (typically: `name`, `description`, `allowed-tools`)
3. **Check required fields** (typically: `name`, `description`)
4. **Validate field-specific requirements** via docs-management queries:
   - Name field: Query "Find skill name field requirements and constraints"
   - Description field: Query "Find skill description field requirements and patterns"
   - Allowed-tools field: Query "Find allowed-tools configuration requirements"

#### Critical Validation Points

- [ ] **Opening delimiter** exists on line 1: `---`
- [ ] **Closing delimiter** exists before content: `---`
- [ ] **Valid YAML syntax**: No tabs, proper indentation
- [ ] **Only valid fields present**: Verify against official whitelist from docs-management
- [ ] **Required fields exist**: Verify against official requirements from docs-management
- [ ] **Field values comply**: Check each field against official constraints from docs-management

### 3. File Structure Validation

**Query official structure requirements:**

```text
Find official file structure requirements for skills including required files, optional directories, and organization patterns
```

#### Structure Validation Workflow

1. **Load official structure specification** from docs-management
2. **Verify required files present** (typically: `SKILL.md` with frontmatter)
3. **Check optional directories** (if present: `scripts/`, `references/`, `assets/`)
4. **Validate organization** against official patterns

#### Supporting Files Validation

For each supporting directory present:

- **scripts/**: Query docs-management for script requirements ("Find skill script best practices")
- **references/**: Query docs-management for reference organization ("Find progressive disclosure patterns")
- **assets/**: Query docs-management for asset guidelines ("Find skill asset requirements")

#### File Organization Checklist

- [ ] No unnecessary files (temp files, backups, clutter)
- [ ] Proper naming (kebab-case convention)
- [ ] Descriptive filenames (not generic)
- [ ] Domain-based organization (logical grouping)
- [ ] Clear hierarchy for discovery

#### Encapsulation Check

**⚠️ OPERATIONAL**: Software architecture principle applied to skills.

Verify no files outside the skill directory reference internal skill files:

```bash
# Search for external references to skill internals
grep -r "skill-name/references/" --exclude-dir=".claude/skills/skill-name"
grep -r "skill-name/scripts/" --exclude-dir=".claude/skills/skill-name"
grep -r "skill-name/assets/" --exclude-dir=".claude/skills/skill-name"
```

Should return no results. Only `SKILL.md` should be referenced externally.

### 4. Content Quality Assessment

**Query official content quality requirements:**

```text
Find official skill content quality requirements including line limits, time-sensitive information handling, file reference depth, workflow structure, and common anti-patterns
```

#### Content Validation Workflow

1. **Load official content guidance** from docs-management
2. **Check SKILL.md size** against official limits (see SKILL.md#specifications-quick-reference)
3. **Validate workflows and structure** against official patterns
4. **Check for anti-patterns** via docs-management ("Find skill authoring anti-patterns")

#### Key Content Quality Areas

Query docs-management for each area:

- **Optimal file size**: "Find SKILL.md size recommendations"
- **Progressive disclosure**: "Find progressive disclosure implementation patterns"
- **Workflow structure**: "Find skill workflow structure requirements"
- **Template patterns**: "Find skill template pattern requirements"
- **Degrees of freedom**: "Find appropriate specificity guidance for skills"

#### Content Quality Checklist

- [ ] SKILL.md body within recommended line limit (500 lines guidance, not hard rule - see tradeoff framework)
- [ ] No time-sensitive information (or properly handled per official guidance)
- [ ] File references appropriate depth (one level deep from SKILL.md)
- [ ] Workflows have clear steps (query docs-management for workflow patterns)
- [ ] Clear structure with logical sections
- [ ] Imperative tone for instructions
- [ ] No duplication between SKILL.md and references
- [ ] Concrete examples (not abstract)
- [ ] Consistent terminology throughout
- [ ] Up-to-date content

#### Progressive Disclosure Context Clues Checklist

Good progressive disclosure requires consistent context clues so Claude knows when to load references:

- [ ] **Clear reference links**: Each reference file has explicit pointer from SKILL.md
- [ ] **Descriptive filenames**: Names like `troubleshooting.md`, `platform-windows.md` (not `doc1.md`)
- [ ] **When-to-load guidance**: SKILL.md indicates when each reference is needed
- [ ] **One level deep**: References do NOT link to other references
- [ ] **Table of contents**: Reference files over 100 lines have TOC at top
- [ ] **Keywords in links**: Link text includes trigger keywords for the content

**Example of good context clues:**

```markdown
**For form filling workflows**: See [FORMS.md](FORMS.md) - load when user mentions forms
**For troubleshooting**: See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - load on errors
```

### 5. Functional Quality

**Query official functional requirements:**

```text
Find official skill activation requirements, testing guidance, and MCP tool reference patterns
```

#### Activation Testing Workflow

1. **Load activation requirements** from docs-management
2. **Test autonomous activation** with expected scenarios
3. **Verify description triggers** align with use cases
4. **Check for false positives** (unwanted activation)

#### Testing Scenarios

Minimum 3 scenarios per official guidance:

1. Direct request: "Use the [skill-name] skill to..."
2. Implicit request: Task description matching skill purpose
3. Alternative phrasing: Different wording for same use case

#### MCP Tool References

If skill references MCP tools, query docs-management:

```text
Find MCP tool reference requirements for skills including fully qualified naming patterns
```

Verify tool names follow official pattern (typically: `ServerName:tool_name`).

### 6. Maintenance Quality

**Query official maintenance requirements:**

```text
Find official skill maintenance requirements including documentation, code quality for scripts, error handling, security considerations, and visual analysis patterns
```

#### Code Quality (for scripts/)

Query docs-management for script requirements:

```text
Find skill script best practices including error handling, validation patterns, package management, and platform considerations
```

Key areas to validate:

- Error handling patterns (query: "Find skill script error handling requirements")
- Package management (query: "Find skill script package dependency requirements")
- Platform considerations (query: "Find cross-platform script requirements")
- Security practices (query: "Find skill security best practices")

#### Security Checklist

- [ ] No hardcoded secrets
- [ ] Input validation present
- [ ] File path safety
- [ ] Network operations documented

### 7. Token Efficiency and Progressive Disclosure

**🚨 CRITICAL**: This section catches bloated skills that should use hub + references architecture.

#### Query Official Requirements First

**Before evaluating token efficiency, load official guidance:**

```text
Find official skill size limits, token thresholds, and progressive disclosure requirements
```

```text
Find official guidance on when skills should use hub architecture with references
```

#### Content Composition Analysis (MANDATORY)

**For ALL skills, analyze content composition:**

1. **Categorize each section** as either:
   - **Core (Always-Load)**: Content needed on EVERY invocation
   - **Conditional (On-Demand)**: Content needed only in specific scenarios

2. **Calculate composition ratio**:

   ```text
   Core Content %     = (Core lines / Total lines) × 100
   Conditional Content % = (Conditional lines / Total lines) × 100
   ```

3. **Query docs-management for thresholds:**

   ```text
   Find progressive disclosure thresholds for when to extract content to references
   ```

4. **Apply official thresholds** from docs-management to determine if extraction needed

#### Content Type Classification

**Query docs-management for authoritative classification:**

```text
Find guidance on what content should always load vs conditionally load in skills
```

**General heuristic (verify against official docs):**

- Core: Critical requirements, overview, when to use, quick start
- Conditional: Platform alternatives, troubleshooting, detailed examples, test scenarios

#### Progressive Disclosure Trigger Evaluation

**Query docs-management for official triggers:**

```text
Find official triggers for when skills must use progressive disclosure and references
```

**Evaluation workflow:**

1. Load official size/composition triggers from docs-management
2. Measure skill against each trigger
3. Document which triggers are exceeded (if any)
4. Flag for extraction if ANY official trigger exceeded

#### Hub Architecture Validation

**Query docs-management for hub architecture requirements:**

```text
Find official hub architecture requirements for skills with references
```

**Validation checklist (verify items against official docs):**

- [ ] SKILL.md functions as navigation hub
- [ ] SKILL.md contains only core content
- [ ] References contain focused, single-purpose content
- [ ] Minimal duplication across files
- [ ] Clear decision points for reference loading
- [ ] Proper encapsulation

#### Token Budget Compliance

**Query docs-management for current limits:**

```text
Find official SKILL.md size limits and token budget recommendations
```

**Validation workflow:**

1. Load official size limits from docs-management
2. Estimate skill tokens (~4 chars = 1 token)
3. Compare against official limits
4. Flag violations for remediation

#### Content Composition Audit Checklist

- [ ] **Queried docs-management** for size limits and thresholds
- [ ] **Performed content composition analysis** (categorized all sections)
- [ ] **Calculated composition ratio** (core vs conditional %)
- [ ] **Applied official threshold check** from docs-management
- [ ] **Identified extraction candidates** if thresholds exceeded
- [ ] **Verified hub architecture** if references/ exists (against official requirements)
- [ ] **Documented reference loading strategy** in SKILL.md if references/ used

### 8. Testing Quality

**Query official testing requirements:**

```text
Find official skill testing requirements including evaluation patterns, multi-model testing, real usage testing, and team feedback guidance
```

#### Evaluation Testing

Query docs-management for evaluation requirements:

```text
Find skill evaluation testing requirements and patterns
```

Official guidance typically includes:

- Minimum number of evaluations (often 3+)
- Evaluation structure and format
- Baseline establishment (performance without skill)
- Evaluation-driven development process

#### Multi-Model Testing

Query docs-management for multi-model testing requirements:

```text
Find multi-model testing requirements for skills
```

Typically includes testing with:

- Claude Haiku (fast, economical)
- Claude Sonnet (balanced)
- Claude Opus (powerful reasoning)

#### Real Usage Testing

Query docs-management for real usage testing guidance:

```text
Find real usage testing requirements for skills
```

Areas to validate:

- Activation testing with varied phrasings
- Real workflow scenarios (not just toy examples)
- Observation of Claude's navigation patterns
- Edge case handling

### 9. Audit Completion

**⚠️ OPERATIONAL**: Audit reporting and log management workflow.

#### Final Steps

1. **Document findings** in audit temp file: `.claude/temp/audit-{skill-name}-latest.md`

   ```markdown
   # Audit Report: skill-name

   **Date**: YYYY-MM-DD HH:MM UTC
   **Auditor**: Claude (via skill-development skill)
   **Audit Type**: [Quick|Standard|Deep]

   ## Summary
   [Overall assessment]

   ## Official Documentation Queries Used
   - Query 1: [what you queried]
   - Query 2: [what you queried]

   ## Issues Found
   - [Issue 1]: Description
   - [Issue 2]: Description

   ## Fixes Applied
   - [Fix 1]: What was changed
   - [Fix 2]: What was changed

   ## Recommendations
   - [Recommendation 1]
   - [Recommendation 2]

   ## Audit Result
   ✅ PASS | ⚠️ PASS WITH WARNINGS | ❌ FAIL
   ```

2. **Update audit log entry** in `.claude/skills/.audit-log.md`
   - Update the row for this skill with current UTC date
   - Format: `YYYY-MM-DD`

3. **CRITICAL: Sync audit log to filesystem**

   This ensures the audit log matches actual skill directories.

   a. **List all actual skill directories**:

   ```bash
   ls -1d .claude/skills/*/ | sed 's|.claude/skills/||' | sed 's|/$||' | sort
   ```

   b. **Read current audit log**

   c. **Compare and identify discrepancies**:
   - Skills in filesystem but NOT in log = NEW (add with empty date)
   - Skills in log but NOT in filesystem = DELETED (remove from log)

   d. **Update audit log** to match reality:
   - Add new skills with empty dates
   - Remove deleted skills
   - Keep existing audit dates unchanged
   - Sort alphabetically

   e. **Verify sync**:

   ```bash
   comm -3 \
     <(ls -1d .claude/skills/*/ | sed 's|.claude/skills/||' | sed 's|/$||' | sort) \
     <(grep '|' .claude/skills/.audit-log.md | tail -n +2 | grep -v '^|--' | awk -F'|' '{print $2}' | tr -d ' ' | sort)
   ```

   Empty output = sync correct ✅

4. **Report back** to main conversation:
   - Summarize findings
   - List issues fixed
   - Provide recommendations

## Type B Meta-Skill Audits

**For meta-skills that delegate to official documentation** (like skill-development itself):

### Type B Compliance Checklist

- [ ] **Zero duplication**: No official content duplicated in skill files
- [ ] **Delegation pattern**: All official requirements fetched via docs-management
- [ ] **Metadata-only references**: References contain query patterns, not duplicated content
- [ ] **Hub architecture**: SKILL.md orchestrates, doesn't duplicate
- [ ] **Encapsulation**: Skill internals not referenced externally

### Type B Validation Workflow

1. **Scan all references** for duplicated official content
2. **Check for detailed requirement lists** that should be queries
3. **Verify delegation patterns** used throughout
4. **Identify violations** and plan restructuring
5. **Document Type B compliance** in audit report

### Common Type B Violations

- Detailed official requirement checklists (should be query patterns)
- Copied specification sections (should link to docs-management)
- Cached official examples (should query for current examples)
- Duplicated validation rules (should delegate to docs-management)

**Fix**: Restructure to metadata + query patterns + operational workflows only.

## Common Issues and Fixes

### Issue: Skill Doesn't Activate

**Query docs-management:**

```text
Find skill activation troubleshooting guidance and description pattern requirements
```

**Diagnosis workflow:**

1. Load activation requirements from docs-management
2. Compare skill description against official patterns
3. Test with varied phrasings
4. Check for conflicts with other skills

### Issue: SKILL.md Too Large

**Query docs-management:**

```text
Find SKILL.md size recommendations and progressive disclosure patterns
```

**Important:** The 500-line recommendation is GUIDANCE, not a hard rule.

**Tradeoff Framework Before Extracting:**

| Question | If YES → Extract | If NO → May Keep |
| -------- | ---------------- | ---------------- |
| Is content platform-specific, troubleshooting, or examples? | Extract to references/ | Core workflows may stay |
| Is content rarely needed (conditional use cases)? | Extract to references/ | Always-needed content may stay |
| Would extraction NOT harm usability? | Extract to references/ | If splitting hurts UX, may keep |
| Is content verbose/explanatory (high token cost)? | Extract or condense | Essential, concise content may stay |

**Decision Rule:** Content needed on EVERY invocation that cannot be made more concise may exceed 500 lines. Conditional content should ALWAYS be extracted.

**Fix workflow:**

1. Load official size limits from docs-management
2. Apply tradeoff framework to categorize content
3. Identify content for references/ (conditional, platform-specific, verbose)
4. Keep only core, always-needed content in SKILL.md
5. Implement progressive disclosure pattern with good context clues
6. Verify against official structure guidance

### Issue: Outdated Content

**Query docs-management:**

```text
Find current skill authoring best practices and requirements
```

**Fix workflow:**

1. Load latest official guidance
2. Update skill to match current patterns
3. Verify all links and references current
4. Update version history

### Issue: Poor Progressive Disclosure

**Query docs-management:**

```text
Find progressive disclosure implementation patterns and examples
```

**Fix workflow:**

1. Load official progressive disclosure guidance
2. Separate SKILL.md (hub) from references/ (details)
3. Document when to load each reference
4. Ensure references provide unique content

## Related Resources

**Within skill-development:**

- `references/metadata/yaml-frontmatter-reference.md` - YAML query patterns
- `references/workflows/validating-skills-workflow.md` - Validation procedures
- `references/workflows/creating-skills-workflow.md` - Creation patterns
- See [Type B Meta-Skill Audits](#type-b-meta-skill-audits) section above for Type B audit workflow

**Official documentation (via docs-management):**

Query docs-management with these patterns:

- "Find official skill best practices"
- "Find skill validation requirements"
- "Find skill testing guidance"
- "Find skill security best practices"

---

**Last Updated**: 2025-11-28
**Pattern**: Delegation-based audit workflow (metadata + query patterns only)
**Coverage**: 100% workflow coverage, 0% content duplication
**Changes**: Added 500-line tradeoff framework, progressive disclosure context clues checklist, clarified that 500 lines is guidance not hard rule
