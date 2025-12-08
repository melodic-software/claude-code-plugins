---
description: Audit a codebase for agentic layer coverage and identify investment opportunities
argument-hint: [target-directory]
---

# Audit Layer

Audit a codebase for agentic layer coverage and identify investment opportunities.

## Arguments

- `$ARGUMENTS`: Target directory to audit (defaults to current directory)

## Instructions

You are auditing a codebase to assess its agentic layer maturity.

### Step 1: Check Commands Directory

Look for `.claude/commands/` or equivalent:

```bash
# Check existence
ls -la .claude/commands/ 2>/dev/null | | echo "Not found"

# List templates if exists
ls .claude/commands/*.md 2>/dev/null | wc -l
```

Score: 20 points if exists with 3+ templates

### Step 2: Check Specs Directory

Look for `specs/` or equivalent:

```bash
# Check existence and count
ls specs/*.md 2>/dev/null | wc -l
```

Score: 15 points if exists with specs

### Step 3: Check ADW Directory

Look for `adws/` or equivalent:

```bash
# Check for core module
ls adws/adw_modules/agent.py 2>/dev/null

# Count workflow scripts
ls adws/adw_*.py 2>/dev/null | wc -l
```

Score: 25 points if adws/ exists, +20 if agent.py exists

### Step 4: Check Hooks

Look for `.claude/hooks/`:

```bash
ls .claude/hooks/*.py 2>/dev/null | wc -l
```

Score: 10 points if hooks exist

### Step 5: Check Observability

Look for `agents/` output directory:

```bash
ls -d agents/*/ 2>/dev/null | wc -l
```

Score: 5 points if agent output exists

### Step 6: Check Worktrees

Look for `trees/` isolation:

```bash
ls -d trees/*/ 2>/dev/null | wc -l
git worktree list 2>/dev/null | wc -l
```

Score: 5 points if worktrees exist

## Scoring

| Component | Max Points |
| ----------- | ------------ |
| .claude/commands/ | 20 |
| specs/ | 15 |
| adws/ | 25 |
| adw_modules/agent.py | 20 |
| hooks/ | 10 |
| agents/ | 5 |
| trees/ | 5 |
| **Total** | **100** |

## Maturity Levels

| Score | Level | Recommendation |
| ------- | ------- | ---------------- |
| 0-20 | None | Start with minimum viable layer |
| 21-40 | Basic | Add composed workflows |
| 41-60 | Developing | Add hooks and triggers |
| 61-80 | Advanced | Add worktree isolation |
| 81-100 | Complete | Focus on optimization |

## Output

Provide audit report:

```markdown
## Agentic Layer Audit Report

**Directory:** {target}
**Date:** {today}
**Score:** {score}/100
**Level:** {level}

### Components Found
- [x/o] .claude/commands/ ({count} templates)
- [x/o] specs/ ({count} specs)
- [x/o] adws/ ({count} workflows)
- [x/o] adw_modules/agent.py
- [x/o] hooks/ ({count} hooks)
- [x/o] agents/ (output directory)
- [x/o] trees/ (worktree isolation)

### Gaps Identified
1. {missing component}
2. {missing component}

### Recommended Investments
1. {next investment}
2. {next investment}

### Time Investment Analysis
- Estimated current: {percent}% on agentic layer
- Target: 50%+ on agentic layer
```

## Notes

- Higher scores indicate more mature agentic layers
- Focus investments on highest-impact gaps first
- Target is 50%+ engineering time on agentic layer
