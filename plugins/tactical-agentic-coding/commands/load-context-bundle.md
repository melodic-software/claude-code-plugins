# Load Context Bundle

Reload previous session context from a context bundle file.

## Arguments

- `$1`: Path to the context bundle JSONL file

## Instructions

You are reloading context from a previous agent session to continue work.

### Step 1: Read Bundle File

Read the JSONL bundle file at the path specified in `$1`.

Each line is a JSON object with one of these formats:

```json
{"operation": "read", "file_path": "path/to/file", "limit": 100, "offset": 0}
{"operation": "write", "file_path": "path/to/file", "content_length": 500}
{"operation": "prompt", "prompt": "truncated user prompt..."}
```markdown

### Step 2: Analyze Bundle

Extract and analyze:

1. All unique file paths accessed
2. Read operations with their parameters
3. User prompts to understand work done

### Step 3: Deduplicate and Optimize

For each unique file, determine optimal read parameters:

**Deduplication Rules:**

1. If ANY entry for a file has no limit/offset -> Read entire file
2. If multiple entries with parameters -> Choose largest limit, prefer offset 0
3. If all have offset > 0 -> Choose entry reading furthest into file
4. If >3 entries for same file -> Read entire file (frequent access = important)

### Step 4: Load Context

Read each unique file ONLY ONCE with optimal parameters:

```text
For each file in deduplicated list:
  - Read with determined parameters
  - Note what was loaded
```markdown

### Step 5: Understand Story

Based on user prompts and file operations, construct understanding of:

- What was the previous agent working on?
- What files were central to the work?
- What was the progression of changes?
- What might be next?

### Step 6: Report

## Output

Report context restoration:

```markdown
## Context Bundle Loaded

**Bundle:** [filename]
**Session:** [session_id if available]

### Previous Work Summary
Based on prompts and file operations, the previous agent was:
[Summary of work done]

### Files Restored
| File | Access Count | Loaded |
| ------ | -------------- | -------- |
| file1.ts | 5 | Full |
| file2.md | 2 | Full |
| file3.py | 1 | Partial (lines 1-100) |

### Context Restored
- **Files loaded:** [count]
- **Estimated tokens:** [estimate]
- **Work continuity:** [assessment]

### Ready to Continue
[What you're now prepared to do based on restored context]

### Gaps Identified
[Any context that couldn't be restored or may be stale]
```markdown

## Notes

- Context bundles are created by hooks that track file operations
- This enables continuation of work across agent instances
- Bundle files use JSONL format (one JSON object per line)
- See @context-priming-patterns.md for priming vs bundles comparison
- See @rd-framework.md for context management strategies
