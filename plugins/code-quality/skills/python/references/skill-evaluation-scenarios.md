# Python Skill Evaluation Scenarios

This document provides test scenarios to validate the python skill's effectiveness across common use cases. These evaluations help ensure the skill activates correctly, provides appropriate guidance, and adapts to different user contexts.

**Last Updated**: 2025-11-19
**Version**: 1.0.0

## Table of Contents

- [Overview](#overview)
- [Evaluation Methodology](#evaluation-methodology)
- [Scenario 1: Minimal Tier (Simple Script)](#scenario-1-minimal-tier-simple-script)
- [Scenario 2: Standard Tier (New Project Setup)](#scenario-2-standard-tier-new-project-setup)
- [Scenario 3: Standard Tier (Code Quality Tools)](#scenario-3-standard-tier-code-quality-tools)
- [Scenario 4: Full Tier (Production System)](#scenario-4-full-tier-production-system)
- [Scenario 5: Alternative Workflow (Poetry vs uv)](#scenario-5-alternative-workflow-poetry-vs-uv)
- [Test Results Template](#test-results-template)
- [Success Criteria](#success-criteria)

## Overview

This document defines formal evaluation scenarios for the python skill. These tests validate:

- **Activation**: Skill correctly recognizes Python-related queries
- **Tier Selection**: Appropriate complexity level matches user context
- **Content Accuracy**: Guidance aligns with official Python standards
- **Navigation**: Progressive disclosure works as intended
- **Tool Recommendations**: Suggestions are current and practical

## Evaluation Methodology

Each evaluation scenario includes:

1. **User Query**: The exact question or request
2. **Expected Behavior**: What should happen when skill activates
3. **Success Indicators**: Observable signs of correct behavior
4. **Acceptable Variations**: Alternative valid responses

### Testing Approach

**Manual Evaluation** (recommended for guidance skills):

1. Paste the user query into Claude Code
2. Note whether the skill activates automatically
3. Verify the response includes appropriate references
4. Check that guidance matches expected complexity tier
5. Document any deviations from expected behavior

**Automated Activation Testing**:

- Description keywords should trigger autonomous activation
- Related phrasings should also activate (fuzzy matching)
- Non-Python queries should not activate (false positive prevention)

## Scenario 1: Minimal Tier (Simple Script)

**Context**: User writing a one-off Python script, focused on clean code without project infrastructure.

**User Query**:

```text
I need to write a quick Python script to parse a CSV file and count occurrences.
What's the cleanest way to structure this?
```

**Expected Behavior**:

- [ ] Skill activates (keyword: "Python script")
- [ ] Response focuses on Tier 1 guidance
- [ ] Includes basic script structure example
- [ ] Minimal mention of project setup/dependencies
- [ ] References conventions-and-style.md for clean code

**Success Indicators**:

- Response is ~500-1000 tokens (not overwhelming)
- Example code is simple, readable, follows PEP-8
- No suggestion to create virtual environment or project structure
- References provided are 1-2 related files maximum

**Test Model**: Haiku (verify sufficient guidance for simple task)

---

## Scenario 2: Standard Tier (New Project Setup)

**Context**: User setting up a new multi-file Python project with team collaboration.

**User Query**:

```text
Help me set up a new Python project. I want to use modern tooling with pytest,
type checking, and linting. Where do I start?
```

**Expected Behavior**:

- [ ] Skill activates (keywords: "Python project", "pytest", "type checking")
- [ ] Response recommends Tier 2 Standard approach
- [ ] Provides uv as primary recommendation with Poetry as alternative
- [ ] Links to multiple references (project structure, dependency management, testing, code quality)
- [ ] Includes installation guidance for target platform
- [ ] Mentions pyproject.toml configuration

**Success Indicators**:

- Response is ~1500-2500 tokens
- Includes step-by-step project setup workflow
- References 4-6 related files (installation, structure, testing, code quality, etc.)
- Asset reference (pyproject-toml-template.toml) is mentioned
- Tool version information is current (Python 3.12+, uv, Ruff, mypy, pytest)

**Test Models**: Sonnet (expected primary model), Opus (verify not over-explained)

---

## Scenario 3: Standard Tier (Code Quality Tools)

**Context**: User adding quality tools to existing project.

**User Query**:

```text
My Python project doesn't have code quality checks yet.
I want to add Ruff for linting/formatting, mypy for type checking, and pytest for testing.
How do I configure all three together?
```

**Expected Behavior**:

- [ ] Skill activates (keywords: "Ruff", "mypy", "pytest")
- [ ] Response recommends Tier 2 Standard approach
- [ ] Focuses on code-quality-tools.md but also references testing-methodology.md and type-hints.md
- [ ] Provides pyproject.toml configuration examples
- [ ] Shows how to run each tool via uv
- [ ] Explains integration patterns (pre-commit hooks, CI/CD)

**Success Indicators**:

- Covers all three tools with equal depth
- Configuration examples are copy-paste ready
- References tool official documentation
- Mentions pre-commit hooks or CI/CD as next step
- Indicates Version information for each tool

**Test Model**: Sonnet (standard for code quality discussions)

---

## Scenario 4: Full Tier (Production System)

**Context**: User building production-ready Python system with advanced requirements.

**User Query**:

```text
I'm building a production API service with async/await, database integration,
type hints, security requirements, and comprehensive tests. What's the complete setup?
```

**Expected Behavior**:

- [ ] Skill activates (keywords: "production", "async/await", "type hints", "security")
- [ ] Response addresses Tier 3 Full complexity
- [ ] References 8+ files covering:
  - Project structure (src/ layout)
  - Dependency management (pinning, lockfiles)
  - Testing methodology (fixtures, mocking, coverage)
  - Type hints (advanced patterns, protocols)
  - Async patterns (TaskGroup, structured concurrency)
  - Security best practices (input validation, dependencies)
  - Code quality tools (Ruff, mypy, Bandit)
  - Packaging and deployment
- [ ] Covers performance considerations
- [ ] Discusses documentation and API docs

**Success Indicators**:

- Response is 3000+ tokens (comprehensive)
- Multiple deep-dive references provided
- Covers edge cases and advanced patterns
- Mentions async/await best practices (TaskGroup over create_task)
- Includes security checklist items
- References official PEP documents where appropriate

**Test Model**: Opus (verify advanced guidance quality)

---

## Scenario 5: Alternative Workflow (Poetry vs uv)

**Context**: User preferring Poetry over uv despite uv being recommended.

**User Query**:

```text
I prefer Poetry for dependency management. Can you show me how to set up a project
with Poetry, pytest, and Ruff instead of uv?
```

**Expected Behavior**:

- [ ] Skill activates (keywords: "Poetry", "pytest", "Ruff")
- [ ] Response acknowledges Poetry as valid alternative
- [ ] Provides equivalent workflow to uv-based approach
- [ ] Shows Poetry-specific commands (poetry add, poetry run)
- [ ] pyproject.toml configuration is similar (tool.poetry section)
- [ ] All other guidance (testing, linting, type checking) remains the same

**Success Indicators**:

- Response indicates Poetry is valid but uv is recommended (reasoning provided)
- All commands use Poetry equivalents (poetry add vs uv add)
- Configuration differences clearly explained
- Guidance on tool compatibility provided (Ruff, mypy work same regardless)
- No suggestion that one tool is "wrong"

**Test Model**: Sonnet (verify flexibility in recommendations)

---

## Test Results Template

Use this template to document evaluation results:

```markdown
### Scenario: [Name]

**Date Tested**: YYYY-MM-DD
**Tester**: [Name/Initials]
**Model Used**: Haiku / Sonnet / Opus

**Query Used**:
[Paste exact query]

**Activation**: ✅ / ❌ [Did skill activate?]

**Tier Selection**: ✅ / ⚠️ / ❌ [Did correct tier activate?]

**Success Indicators**:
- [x] Indicator 1
- [ ] Indicator 2 (optional notes on why)

**Token Count**: ~[estimated]

**Deviations from Expected Behavior**:
[If any, describe differences and whether acceptable]

**Overall Result**: ✅ PASS / ⚠️ MINOR ISSUES / ❌ NEEDS WORK

**Notes**:
[Any observations about response quality, clarity, or suggestions for improvement]
```

---

## Success Criteria

The python skill **PASSES** evaluation when:

### Activation Criteria (100% required)

- [ ] Skill activates for all test queries without false positives
- [ ] Alternative phrasings of same concept also activate
- [ ] Irrelevant Python queries (e.g., "What's the history of Python language?") don't over-activate

### Content Criteria (95% required)

- [ ] Guidance aligns with official Python standards (PEPs, python.org docs)
- [ ] Tool recommendations are current (versions documented in "Last Verified")
- [ ] Configuration examples are accurate and copy-paste ready
- [ ] All referenced files exist and are linked correctly
- [ ] No duplication between SKILL.md and references

### Tier Selection Criteria (90% required)

- [ ] Simple queries get Tier 1 responses (no project setup)
- [ ] Standard queries get Tier 2 responses (project setup + tooling)
- [ ] Advanced queries get Tier 3 responses (production-ready + edge cases)
- [ ] Tier selection adapts to user context

### Reference Navigation Criteria (90% required)

- [ ] Links to references are contextually appropriate
- [ ] Users can follow links and find detailed information
- [ ] Progressive disclosure reduces initial information load
- [ ] Hub architecture (SKILL.md as navigation) works effectively

### Token Efficiency Criteria (90% required)

- [ ] Responses don't load excessive references
- [ ] SKILL.md is sufficient for most common queries
- [ ] References are loaded on-demand, not preemptively
- [ ] No content duplication between files

### Alternative Paths Criteria (85% required)

- [ ] Skill acknowledges alternative approaches (Poetry vs uv, etc.)
- [ ] Alternative guidance is equally valid
- [ ] Flexibility in recommendations is clear
- [ ] No "wrong way" suggestions

### Model Compatibility Criteria (Recommended but not required)

- [ ] Haiku: Sufficient guidance for simple tasks
- [ ] Sonnet: Good balance of depth and clarity
- [ ] Opus: Advanced patterns explained well without redundancy

---

## Scheduling Evaluations

**Recommended Schedule**:

- **Initial Launch**: Complete all 5 scenarios with Sonnet (baseline)
- **Monthly**: Spot-check 1-2 scenarios to detect degradation
- **Quarterly**: Full evaluation cycle with all models
- **After Updates**: Test any modified references immediately

**When to Re-Evaluate**:

- After tool version updates (Python 3.14 release, uv major update, etc.)
- After reference file modifications
- When user feedback indicates confusion
- After Claude model changes
- Before recommending skill to broader team

---

## Related Documentation

- `.claude/skills/python/SKILL.md` - Main skill file
- `.claude/skills/python/references/` - All reference content
- `.claude/skills/skills-meta/references/quality/skill-audit-guide.md` - Audit methodology
- `.claude/memory/testing-principles.md` - Testing best practices

**Last Verified**: 2025-11-19
**Evaluation Status**: Ready for testing (all scenarios defined)
