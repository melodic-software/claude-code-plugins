# Synthetic /context capture — parser test fixture only

This fixture mirrors the section and cell shapes of `claude -p "/context"` output as of the
format observed at authoring time. Every number in it is invented for the test; none is a
measurement, and nothing may ever be reported from this file.

## Context Usage

**Model:** claude-test-model  
**Tokens:** 30.6k / 500k (6%)

### Estimated usage by category

| Category | Tokens | Percentage |
|----------|--------|------------|
| System prompt | 2.5k | 0.5% |
| System tools | 11.4k | 2.3% |
| System tools (deferred) | 8.2k | 1.6% |
| Custom agents | 1.1k | 0.2% |
| Skills | 4.7k | 0.9% |
| Messages | 42 | 0.0% |
| Free space | 437.2k | 87.4% |
| Autocompact buffer | 34k | 6.8% |

### Custom Agents

| Agent Type | Source | Tokens |
|------------|--------|--------|
| example:worker | Plugin | 210 |
| example:verifier | Plugin | 190 |

### Skills

| Skill | Source | Tokens |
|-------|--------|--------|
| sample-user-skill | User | ~150 |
| example:alpha | Plugin (example) | 320 |
| example:beta | Plugin (example) | < 20 |
