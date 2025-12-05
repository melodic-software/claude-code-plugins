# Claude Code Subagent Audit & Recommendations

> **Comprehensive Analysis of Existing Subagents and Proposals for New High-Value Agents**
> Generated: 2025-12-04
> Based on: Official Claude Code documentation and exhaustive codebase analysis

---

## Executive Summary

This document presents findings from a comprehensive audit of **47 existing subagents** across **6 plugins**, plus **35 proposals for new high-value subagents**.

### Key Findings

| Metric | Value |
| :------- | :------ |
| Total Agents Audited | 47 |
| Fully Compliant | 19 (40%) |
| Partially Compliant | 0 |
| Non-Compliant | 28 (60%) |
| New Agents Proposed | 35 |
| Critical Issues Found | 2 |

### Critical Issues Requiring Immediate Action

1. **28 agents in `tactical-agentic-coding` plugin are missing the required `name` field**
2. **Model selection contradiction in `docs-researcher`** (frontmatter says opus, system prompt says haiku)

---

## Table of Contents

1. [Audit Results by Plugin](#1-audit-results-by-plugin)
2. [Compliance Issues](#2-compliance-issues)
3. [Model Selection Analysis](#3-model-selection-analysis)
4. [Proposed New Agents - High Value](#4-proposed-new-agents---high-value)
5. [Proposed New Agents - Creative/Niche](#5-proposed-new-agents---creativeniche)
6. [Implementation Roadmap](#6-implementation-roadmap)
7. [Appendix: Full Agent Inventory](#7-appendix-full-agent-inventory)

---

## 1. Audit Results by Plugin

### Overview Table

| Plugin | Agents | Compliant | Non-Compliant | Rate |
| :------- | :------: | :---------: | :-------------: | :----: |
| `claude-ecosystem` | 4 | 4 | 0 | 100% |
| `google-ecosystem` | 10 | 10 | 0 | 100% |
| `code-quality` | 3 | 3 | 0 | 100% |
| `git` | 1 | 1 | 0 | 100% |
| `windows-diagnostics` | 1 | 1 | 0 | 100% |
| `tactical-agentic-coding` | 28 | 0 | 28 | 0% |
| **TOTAL** | **47** | **19** | **28** | **40%** |

---

### 1.1 claude-ecosystem Plugin (4 agents)

Status: **FULLY COMPLIANT**

| Agent | Model | Tools | Issues |
| :------ | :------ | :------ | :------- |
| `docs-researcher` | opus | Skill, Read, Bash | Model contradiction (see Critical Issues) |
| `skill-auditor` | haiku | Read, Glob, Grep, Skill | Non-standard `color` field |
| `mcp-research` | opus | MCP tools, Read, Glob, Grep | Expensive model for research |
| `prompt-improver` | sonnet | Skill, Read, Write, Glob, Grep, Bash | Non-standard `color` field |

**Recommendations:**

- Fix `docs-researcher` model contradiction (change to haiku)
- Consider downgrading `mcp-research` from opus to sonnet
- Remove or document non-standard `color` field

---

### 1.2 google-ecosystem Plugin (10 agents)

Status: **FULLY COMPLIANT**

| Agent | Model | Assessment |
| :------ | :------ | :----------- |
| `gemini-docs-researcher` | haiku | Excellent - fast for lookups |
| `gemini-context-syncer` | haiku | Appropriate for sync operations |
| `gemini-interactive-shell` | sonnet | Could use haiku for handoff |
| `gemini-sandboxed-executor` | sonnet | Appropriate for security analysis |
| `gemini-bulk-analyzer` | haiku | Appropriate for bulk work |
| `gemini-second-opinion` | haiku | May need sonnet for synthesis |
| `gemini-checkpoint-experimenter` | sonnet | Appropriate for experiments |
| `gemini-planner` | sonnet | Appropriate for planning |
| `gemini-deep-explorer` | haiku | Appropriate for exploration |
| `gemini-safe-experimenter` | sonnet | Appropriate for experiments |

**Recommendations:**

- Consider merging `gemini-bulk-analyzer` + `gemini-deep-explorer` (overlapping 50K-100K token range)
- Consider merging `gemini-checkpoint-experimenter` + `gemini-safe-experimenter` (nearly identical purpose)
- Upgrade `gemini-second-opinion` to sonnet for better synthesis quality
- Remove emojis from `gemini-planner` system prompt
- Verify all referenced skills exist

**Potential Overlaps Identified:**

1. `gemini-bulk-analyzer` vs `gemini-deep-explorer` - both handle large codebase analysis
2. `gemini-checkpoint-experimenter` vs `gemini-safe-experimenter` - both use checkpointing for safety

---

### 1.3 code-quality Plugin (3 agents)

Status: **FULLY COMPLIANT**

| Agent | Model | Tools | Notes |
| :------ | :------ | :------ | :------ |
| `codebase-analyst` | sonnet | Read, Glob, Grep, Bash | Excellent - uses `skills` field |
| `debugger` | sonnet | Read, Edit, Bash, Glob, Grep | Well-structured |
| `code-reviewer` | sonnet | Read, Glob, Grep | Good - includes skills field |

**Recommendations:**

- Remove non-standard `color` field
- Otherwise exemplary implementation

---

### 1.4 git Plugin (1 agent)

Status: **FULLY COMPLIANT**

| Agent | Model | Tools | Notes |
| :------ | :------ | :------ | :------ |
| `history-reviewer` | haiku | Bash, Read, Grep, Glob | Appropriate model for read-only |

---

### 1.5 windows-diagnostics Plugin (1 agent)

Status: **FULLY COMPLIANT**

| Agent | Model | Tools | Notes |
| :------ | :------ | :------ | :------ |
| `diagnostician` | sonnet | Bash, Read, Grep, Glob | Excellent - uses `skills` field |

---

### 1.6 tactical-agentic-coding Plugin (28 agents)

Status: **NON-COMPLIANT (Critical)**

**All 28 agents are missing the required `name` field and use non-standard array syntax for tools.**

| Issue | Count | Severity |
| :------ | :-----: | :--------- |
| Missing `name` field | 28 | CRITICAL |
| Array syntax for tools | 28 | MEDIUM |
| Missing proactive keywords in description | ~15 | LOW |

**Full Agent List:**

- agent-builder, context-analyzer, context-optimizer, documentation-generator
- e2e-test-resolver, e2e-test-runner, hook-designer, issue-classifier
- kpi-tracker, layer-auditor, layer-scaffolder, orchestration-planner
- patch-planner, plan-generator, plan-implementer, prompt-analyzer
- prompt-generator, scout-fast, sdlc-implementer, sdlc-planner
- shipper, spec-reviewer, test-resolver, test-runner
- tool-scaffolder, workflow-coordinator, workflow-designer, worktree-installer

**Fix Required:**

```yaml
# BEFORE (non-compliant)
---
description: Some description
tools: [Read, Write]
model: sonnet
---

# AFTER (compliant)
---
name: agent-name
description: Some description
tools: Read, Write
model: sonnet
---
```

---

## 2. Compliance Issues

### 2.1 Critical Issues

#### Issue 1: Missing Required `name` Field (28 agents)

**Severity:** CRITICAL
**Affected:** All agents in `tactical-agentic-coding` plugin
**Impact:** Agents may not be recognized properly by Claude Code

**Root Cause:** The plugin uses a non-standard frontmatter format that omits the required `name` field.

**Fix:** Add `name` field to all 28 agent files. Can be automated with a script.

---

#### Issue 2: Model Contradiction in `docs-researcher`

**Severity:** HIGH
**Affected:** `plugins/claude-ecosystem/agents/docs-researcher.md`
**Impact:** Unnecessary cost (opus is 5x more expensive than haiku)

**Details:**

- Frontmatter line 5: `model: opus`
- System prompt line 91: "Run efficiently (Haiku model)"

**Fix:** Change `model: opus` to `model: haiku` in frontmatter.

---

### 2.2 Medium Issues

#### Issue 3: Non-Standard `color` Field (15 agents)

**Severity:** MEDIUM
**Affected:** Agents in claude-ecosystem, google-ecosystem, code-quality, git plugins

**Details:** The `color` field is not in the official specification. While harmless, it creates inconsistency.

**Fix:** Either:

- Remove from all agents, OR
- Document as a plugin extension with defined semantics

---

#### Issue 4: Array Syntax for Tools (28 agents)

**Severity:** MEDIUM
**Affected:** All agents in `tactical-agentic-coding` plugin

**Details:** Uses `tools: [Tool1, Tool2]` instead of `tools: Tool1, Tool2`

**Fix:** Convert array syntax to comma-separated strings.

---

#### Issue 5: Agent Overlaps in google-ecosystem (4 agents)

**Severity:** MEDIUM
**Affected:**

- `gemini-bulk-analyzer` vs `gemini-deep-explorer`
- `gemini-checkpoint-experimenter` vs `gemini-safe-experimenter`

**Fix:** Consider merging overlapping agents or clearly differentiating their purposes.

---

### 2.3 Low Issues

#### Issue 6: Missing Proactive Keywords (~15 agents)

**Severity:** LOW
**Affected:** Various agents across plugins

**Details:** Descriptions lack "PROACTIVELY", "MUST BE USED", or similar keywords that encourage automatic delegation.

**Fix:** Add proactive keywords to descriptions.

---

#### Issue 7: Underutilized `skills` Field

**Severity:** LOW
**Affected:** Many agents that reference skills in prompts but don't declare them

**Details:** Only 5 agents currently use the `skills` field. Many more could benefit.

**Fix:** Add `skills` field where agents reference skills in their prompts.

---

## 3. Model Selection Analysis

### Current Distribution

| Model | Count | Percentage | Appropriate Use |
| :------ | :-----: | :----------: | :---------------- |
| `opus` | 15 | 32% | Complex reasoning, critical decisions |
| `sonnet` | 22 | 47% | General development tasks |
| `haiku` | 10 | 21% | Fast, read-only, parallel tasks |

### Model Selection Issues

| Agent | Current | Recommended | Reason |
| :------ | :-------- | :------------ | :------- |
| `docs-researcher` | opus | **haiku** | Read-only research; system prompt says Haiku |
| `mcp-research` | opus | **sonnet** | Research coordination; opus is overkill |
| `gemini-interactive-shell` | sonnet | **haiku** | Simple handoff coordination |
| `gemini-second-opinion` | haiku | **sonnet** | Complex synthesis of perspectives |

### Cost Implications

| Model | Input Cost | Output Cost | Relative |
| :------ | :----------- | :------------ | :--------- |
| Haiku | $0.25/MTok | $1.25/MTok | 1x |
| Sonnet | $3/MTok | $15/MTok | 12x |
| Opus | $15/MTok | $75/MTok | 60x |

**Recommendation:** Review agents using `opus` and consider if `sonnet` would suffice.

---

## 4. Proposed New Agents - High Value

### Ranked by Impact (Highest First)

| Rank | Agent | Plugin | Value | Feasibility | Total |
| :----: | :------ | :------- | :-----: | :-----------: | :-----: |
| 1 | secrets-scanner | security (new) | 10 | 9 | 19 |
| 2 | dependency-auditor | security (new) | 9 | 8 | 17 |
| 3 | ci-pipeline-analyzer | devops (new) | 8 | 9 | 17 |
| 4 | changelog-generator | melodic-software | 8 | 9 | 17 |
| 5 | api-docs-generator | code-quality | 8 | 8 | 16 |
| 6 | tech-debt-tracker | code-quality | 7 | 9 | 16 |
| 7 | dockerfile-analyzer | devops (new) | 7 | 9 | 16 |
| 8 | env-validator | code-quality | 6 | 10 | 16 |
| 9 | regex-explainer | code-quality | 6 | 10 | 16 |
| 10 | performance-profiler | code-quality | 8 | 6 | 14 |
| 11 | migration-assistant | code-quality | 8 | 6 | 14 |
| 12 | accessibility-auditor | code-quality | 7 | 7 | 14 |
| 13 | schema-analyzer | code-quality | 7 | 7 | 14 |
| 14 | readme-generator | melodic-software | 6 | 9 | 15 |
| 15 | commit-message-improver | git | 5 | 10 | 15 |

---

### Top 5 Detailed Specifications

#### 1. secrets-scanner

```yaml
---
name: secrets-scanner
description: PROACTIVELY scan for hardcoded secrets, API keys, passwords, tokens, and sensitive data before commits. MUST BE USED for any authentication, API, or configuration code. Prevents credential leaks.
tools: Read, Grep, Glob, Bash
model: haiku
---
```

**Value:** 10/10 - Prevents catastrophic security breaches
**Feasibility:** 9/10 - Pattern matching for secrets is well-understood

---

#### 2. dependency-auditor

```yaml
---
name: dependency-auditor
description: PROACTIVELY scan dependencies for known vulnerabilities (CVEs), outdated packages, and license compliance issues. Use before merging PRs or during security audits.
tools: Bash, Read, Grep, Glob
model: sonnet
---
```

**Value:** 9/10 - Supply chain attacks are increasingly common
**Feasibility:** 8/10 - Can run npm audit, pip audit, cargo audit

---

#### 3. ci-pipeline-analyzer

```yaml
---
name: ci-pipeline-analyzer
description: Analyze CI/CD pipeline configurations (GitHub Actions, GitLab CI, Azure Pipelines) for best practices, security issues, performance optimization, and anti-patterns.
tools: Read, Glob, Grep
model: sonnet
---
```

**Value:** 8/10 - CI/CD pipelines are often poorly optimized
**Feasibility:** 9/10 - YAML parsing and best practice checking

---

#### 4. changelog-generator

```yaml
---
name: changelog-generator
description: Generate changelogs from git history and conventional commits. Supports Keep a Changelog format. Categorizes changes by type (Added, Changed, Fixed, etc.).
tools: Bash, Read, Edit, Write
model: sonnet
---
```

**Value:** 8/10 - Changelogs are tedious but essential
**Feasibility:** 9/10 - Git log parsing + conventional commits

---

#### 5. api-docs-generator

```yaml
---
name: api-docs-generator
description: Generate comprehensive API documentation from code. Supports OpenAPI/Swagger generation, JSDoc/TSDoc completion, docstring generation. Analyzes function signatures, types, and usage patterns.
tools: Read, Edit, Write, Glob, Grep
model: sonnet
---
```

**Value:** 8/10 - API documentation is often incomplete
**Feasibility:** 8/10 - Type extraction and doc generation

---

## 5. Proposed New Agents - Creative/Niche

### Ranked by Creativity (Most Creative First)

| Rank | Agent | Novelty | Value | Use Case |
| :----: | :------ | :-------: | :-----: | :--------- |
| 1 | temporal-archaeologist | 10 | 9 | Reconstruct lost decision context from git history |
| 2 | api-necromancer | 9 | 8 | Reverse-engineer API specs from undocumented code |
| 3 | dependency-oracle | 9 | 9 | Predict future dependency problems |
| 4 | concurrency-inspector | 8 | 8 | Find race conditions and deadlocks statically |
| 5 | config-detective | 8 | 9 | Trace config values through all layers |
| 6 | error-message-therapist | 8 | 8 | Transform cryptic errors into helpful ones |
| 7 | test-gap-hunter | 8 | 9 | Find semantic test gaps beyond coverage |
| 8 | schema-evolution-planner | 7 | 9 | Plan zero-downtime database migrations |
| 9 | pattern-miner | 7 | 7 | Discover abstraction opportunities |
| 10 | security-surface-mapper | 7 | 9 | Map attack surface for threat modeling |
| 11 | naming-consultant | 7 | 7 | Improve naming consistency |
| 12 | onboarding-guide | 7 | 9 | Generate onboarding docs from code |
| 13 | migration-pathfinder | 7 | 9 | Plan framework migrations |
| 14 | logging-architect | 7 | 8 | Design observability improvements |
| 15 | feature-flag-surgeon | 7 | 7 | Manage feature flag lifecycle |
| 16 | i18n-auditor | 6 | 7 | Find internationalization issues |
| 17 | accessibility-scout | 6 | 8 | Find a11y issues in frontend code |
| 18 | env-setup-automator | 6 | 8 | Generate development environment setup |
| 19 | dead-code-detective | 5 | 8 | Find and safely remove dead code |
| 20 | release-notes-generator | 5 | 8 | Generate release notes from git |

---

### Top 5 Creative Agents - Detailed

#### 1. temporal-archaeologist

```yaml
---
name: temporal-archaeologist
description: Time-travel detective for understanding code evolution. Reconstruct "lost knowledge" by analyzing git history to explain WHY code exists. Use PROACTIVELY when encountering confusing legacy code or "why is this here" questions.
tools: Bash, Read, Grep, Glob
model: opus
---
```

**System Prompt Outline:**

- Reconstruct decision context from commit messages, PR descriptions, issues
- Identify "fear commits" (defensive code from past incidents)
- Map evolution of patterns over time
- Find the "original sin" - first commit that introduced a pattern
- Identify orphaned code (defensive code whose threat no longer exists)

**Use Cases:**

- "Why does this function exist? It seems redundant"
- "This workaround looks hacky - can we remove it?"
- "Who should I ask about this ancient module?"

---

#### 2. api-necromancer

```yaml
---
name: api-necromancer
description: Resurrect API contracts from codebases without documentation. Reverse-engineer OpenAPI/GraphQL specifications from implementations. Use when onboarding to undocumented APIs or creating client SDKs.
tools: Read, Grep, Glob, Bash
model: sonnet
---
```

**System Prompt Outline:**

- Discover all routes and endpoints
- Extract parameter types from validators
- Infer response schemas from handlers
- Map error codes and messages
- Generate complete OpenAPI 3.0 specification

---

#### 3. dependency-oracle

```yaml
---
name: dependency-oracle
description: Predict future dependency problems before they happen. Analyze dependency health, security advisories, maintenance status to forecast breaking changes. Use PROACTIVELY before major upgrades or periodically for risk assessment.
tools: Bash, Read, Grep, WebFetch
model: sonnet
---
```

**System Prompt Outline:**

- Predict upcoming breaking changes in major versions
- Identify dependencies approaching end-of-life
- Track deprecation warnings in changelogs
- Monitor maintainer activity patterns
- Calculate "bus factor" analysis

---

#### 4. concurrency-inspector

```yaml
---
name: concurrency-inspector
description: Find race conditions, deadlocks, and concurrency bugs before they happen. Analyze async code, shared state, and lock patterns. Use when reviewing async code or debugging intermittent bugs.
tools: Read, Grep, Glob
model: opus
---
```

**System Prompt Outline:**

- Identify async boundaries
- Map shared state
- Analyze lock patterns
- Find unprotected mutations
- Trace async flows for race conditions

---

#### 5. config-detective

```yaml
---
name: config-detective
description: Hunt down configuration sprawl and mysteries. Trace configuration values through all layers (defaults, files, env vars, secrets, overrides). Use when debugging "where does this config come from?" questions.
tools: Read, Grep, Glob, Bash
model: sonnet
---
```

**System Prompt Outline:**

- Search for config key usage patterns
- Trace through config loaders
- Map environment variable references
- Identify config precedence rules
- Document the "config journey"

---

## 6. Implementation Roadmap

### Phase 1: Fix Critical Issues (Immediate)

**Estimated Effort:** 2-4 hours

| Task | Priority | Effort |
| :----- | :--------- | :------- |
| Add `name` field to 28 tactical-agentic-coding agents | Critical | 1 hour (scriptable) |
| Fix tools array syntax in same 28 agents | Critical | Included above |
| Fix docs-researcher model contradiction | High | 5 minutes |
| Consider downgrading mcp-research to sonnet | Medium | 5 minutes |

---

### Phase 2: Create High-Value Security Agents (Week 1-2)

**Estimated Effort:** 8-16 hours

| Agent | Priority | Value |
| :------ | :--------- | :------ |
| secrets-scanner | Critical | Prevents credential leaks |
| dependency-auditor | High | Supply chain security |

**New Plugin Required:** `security`

---

### Phase 3: Create DevOps Agents (Week 2-3)

**Estimated Effort:** 8-16 hours

| Agent | Priority | Value |
| :------ | :--------- | :------ |
| ci-pipeline-analyzer | High | DevOps optimization |
| dockerfile-analyzer | Medium | Container security |

**New Plugin Required:** `devops`

---

### Phase 4: Enhance Existing Plugins (Week 3-4)

**Estimated Effort:** 16-24 hours

| Agent | Plugin | Priority |
| :------ | :------- | :--------- |
| changelog-generator | melodic-software | High |
| api-docs-generator | code-quality | High |
| tech-debt-tracker | code-quality | Medium |
| commit-message-improver | git | Medium |
| readme-generator | melodic-software | Low |

---

### Phase 5: Creative Agents (Month 2+)

**Estimated Effort:** 40+ hours

| Agent | Plugin | Priority |
| :------ | :------- | :--------- |
| temporal-archaeologist | code-quality | High (high value) |
| config-detective | code-quality | High (high value) |
| test-gap-hunter | code-quality | High (high value) |
| dependency-oracle | security | Medium |
| api-necromancer | code-quality | Medium |

---

## 7. Appendix: Full Agent Inventory

### A. Existing Agents (47 total)

#### claude-ecosystem (4)

- docs-researcher
- skill-auditor
- mcp-research
- prompt-improver

#### google-ecosystem (10)

- gemini-docs-researcher
- gemini-context-syncer
- gemini-interactive-shell
- gemini-sandboxed-executor
- gemini-bulk-analyzer
- gemini-second-opinion
- gemini-checkpoint-experimenter
- gemini-planner
- gemini-deep-explorer
- gemini-safe-experimenter

#### code-quality (3)

- codebase-analyst
- debugger
- code-reviewer

#### git (1)

- history-reviewer

#### windows-diagnostics (1)

- diagnostician

#### tactical-agentic-coding (28)

- agent-builder
- context-analyzer
- context-optimizer
- documentation-generator
- e2e-test-resolver
- e2e-test-runner
- hook-designer
- issue-classifier
- kpi-tracker
- layer-auditor
- layer-scaffolder
- orchestration-planner
- patch-planner
- plan-generator
- plan-implementer
- prompt-analyzer
- prompt-generator
- scout-fast
- sdlc-implementer
- sdlc-planner
- shipper
- spec-reviewer
- test-resolver
- test-runner
- tool-scaffolder
- workflow-coordinator
- workflow-designer
- worktree-installer

---

### B. Proposed New Agents (35 total)

#### High-Value (15)

1. secrets-scanner
2. dependency-auditor
3. ci-pipeline-analyzer
4. changelog-generator
5. api-docs-generator
6. tech-debt-tracker
7. dockerfile-analyzer
8. env-validator
9. regex-explainer
10. performance-profiler
11. migration-assistant
12. accessibility-auditor
13. schema-analyzer
14. readme-generator
15. commit-message-improver

#### Creative/Niche (20)

1. temporal-archaeologist
2. api-necromancer
3. dependency-oracle
4. concurrency-inspector
5. config-detective
6. error-message-therapist
7. test-gap-hunter
8. schema-evolution-planner
9. pattern-miner
10. security-surface-mapper
11. naming-consultant
12. onboarding-guide
13. migration-pathfinder
14. logging-architect
15. feature-flag-surgeon
16. i18n-auditor
17. accessibility-scout
18. env-setup-automator
19. dead-code-detective
20. release-notes-generator

---

### C. New Plugins Recommended

| Plugin | Agents | Purpose |
| :------- | :------- | :-------- |
| `security` | secrets-scanner, dependency-auditor, dependency-oracle, security-surface-mapper | Security-focused agents |
| `devops` | ci-pipeline-analyzer, dockerfile-analyzer, env-setup-automator | CI/CD and infrastructure |

---

## Document Metadata

**Created:** 2025-12-04
**Sources:**

- Official Claude Code documentation (code.claude.com)
- Official Claude Agent SDK documentation (platform.claude.com)
- Anthropic engineering articles
- Exhaustive codebase analysis of 47 existing agents

**Related Documents:**

- `CLAUDE-CODE-SUBAGENTS-COMPREHENSIVE-GUIDE.md` - Complete documentation synthesis

---

*This document was generated through parallel agent research and analysis, driven 100% by official Claude Code documentation.*
