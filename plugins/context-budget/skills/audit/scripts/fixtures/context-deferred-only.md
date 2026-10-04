# Synthetic /context capture: parser test fixture only

This fixture mirrors the shape headless `claude -p "/context"` was observed to print on Claude
Code 2.1.289: a `System tools (deferred)` row and no prefix `System tools` row. Every number in it
is invented for the test; none is a measurement, and nothing may ever be reported from this file.

## Context Usage

**Model:** claude-test-model  
**Tokens:** 19.2k / 500k (4%)

### Estimated usage by category

| Category | Tokens | Percentage |
|----------|--------|------------|
| System prompt | 2.5k | 0.5% |
| System tools (deferred) | 14k | 2.8% |
| Custom agents | 1.1k | 0.2% |
| Skills | 4.7k | 0.9% |
| Messages | 42 | 0.0% |
| Free space | 446.4k | 89.3% |
| Autocompact buffer | 34k | 6.8% |

### Skills

| Skill | Source | Tokens |
|-------|--------|--------|
| sample-user-skill | User | ~150 |
| example:alpha | Plugin (example) | 320 |
