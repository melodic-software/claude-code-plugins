# Agentic Coding KPIs

Key Performance Indicators for measuring agentic coding success. From TAC Lesson 002.

## Why KPIs Matter

Without measurement, you can't improve. These four KPIs track your progression from AI coding (high presence, many attempts) to true agentic coding (zero presence, one-shot success).

## The Four KPIs

### 1. Size (UP)

**Increase the size of work handed to agents.**

| Stage | Work Size | Example |
| ------- | ----------- | --------- |
| Beginner | 5 minutes | "Add a console.log here" |
| Intermediate | 30 minutes | "Implement this API endpoint" |
| Advanced | 3 hours | "Build the authentication system" |
| Expert | Full day+ | "Implement this feature end-to-end" |

**How to improve**: Start small, increase scope as agents succeed consistently.

**Red flag**: Stuck at small tasks because larger ones fail.

### 2. Attempts (DOWN) - Target: 1 (one-shot success)

Each iteration represents failure. True agentic coding means the agent gets it right the first time.

| Attempts | Status | Action |
| ---------- | -------- | -------- |
| 1 | Excellent | Maintain and expand |
| 2-3 | Acceptable | Identify missing leverage point |
| 4+ | Poor | Stop and fix fundamentals |

**How to improve**: When attempts > 1, ask "which leverage point was missing?"

**Red flag**: Iteration as normal workflow (that's AI coding, not agentic coding).

### 3. Streak (UP)

**Consecutive one-shot successes.**

Track how many tasks in a row succeed on the first attempt.

| Streak | Meaning |
| -------- | --------- |
| 1-3 | Building consistency |
| 4-7 | Solid foundation |
| 8-15 | Strong agentic capability |
| 15+ | Expert level |

**When streak breaks**: Identify which leverage point was missing for that specific task. Fix it and continue.

**How to improve**: After each success, ask "what made this work?" After each failure, ask "what was missing?"

### 4. Presence (DOWN) - Target: 0 (zero human intervention)

Presence measures how much you need to be involved during agent execution.

| Presence Level | Description |
| ---------------- | ------------- |
| High | Constantly watching, correcting, guiding |
| Medium | Checking in periodically, occasional corrections |
| Low | Set task, check result, minimal intervention |
| Zero | Fully autonomous, no intervention needed |

**How to improve**: Each time you intervene, ask "how could I have prevented this?"

**Red flag**: Babysitting agents (high presence defeats the purpose).

---

## The Transition

### AI Coding (Phase 1)

- High presence (constantly involved)
- Many attempts (iteration is normal)
- Small tasks (limited scope)
- Short streaks (inconsistent success)

### Agentic Coding (Phase 2)

- Zero presence (autonomous)
- One attempt (one-shot success)
- Large tasks (full features)
- Long streaks (consistent wins)

---

## Measurement Framework

### Daily Tracking

| Task | Size | Attempts | Streak | Presence | Notes |
| ------ | ------ | ---------- | -------- | ---------- | ------- |
| Example task 1 | 30 min | 1 | 5 | Low | Tests helped |
| Example task 2 | 1 hour | 3 | 0 | High | Missing stdout |

### Weekly Review

1. **Average Size**: Are tasks getting larger?
2. **Average Attempts**: Trending toward 1?
3. **Longest Streak**: Increasing?
4. **Average Presence**: Decreasing?

### When Metrics Slip

1. **Size decreased?** - Agent failing at larger tasks. Identify missing leverage point.
2. **Attempts increased?** - Something changed. Check recent failures.
3. **Streak broke?** - Analyze the failing task. What was different?
4. **Presence increased?** - Why did you need to intervene? Fix root cause.

---

## Example Scenarios

### Scenario 1: API Endpoint Implementation

**Before optimization:**

- Size: 15 min (one endpoint at a time)
- Attempts: 3-4 (agent misses edge cases)
- Streak: 2 (inconsistent)
- Presence: High (constantly fixing errors)

**Fix**: Add comprehensive tests + stdout logging

**After optimization:**

- Size: 2 hours (multiple endpoints)
- Attempts: 1 (tests catch issues)
- Streak: 8 (consistent wins)
- Presence: Low (just review final PR)

### Scenario 2: Documentation Update

**Before optimization:**

- Size: 5 min (one section at a time)
- Attempts: 2 (formatting issues)
- Streak: 3
- Presence: Medium (checking formatting)

**Fix**: Add template + clear style guide in CLAUDE.md

**After optimization:**

- Size: 30 min (entire doc)
- Attempts: 1 (template guides formatting)
- Streak: 12
- Presence: Zero (fully autonomous)

---

## Quick Reference

| KPI | Direction | Target | Action When Off Track |
| ----- | ----------- | -------- | ---------------------- |
| Size | UP | Largest possible | Identify failing leverage point |
| Attempts | DOWN | 1 | Find missing context/tests |
| Streak | UP | As high as possible | Analyze breaking task |
| Presence | DOWN | 0 | Automate interventions |

---

## Related

- @12-leverage-points.md - What to fix when KPIs slip
- @agent-perspective-checklist.md - Pre-task checklist
- @tac-philosophy.md - Why this matters

---

**Source:** Lesson 002 - 12 Leverage Points of Agentic Coding
**Last Updated:** 2025-12-04
