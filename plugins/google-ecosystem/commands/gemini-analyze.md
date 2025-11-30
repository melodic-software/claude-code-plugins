---
description: Send a file to Gemini CLI for analysis with structured output
argument-hint: <file-path> [analysis-type: security|performance|architecture|bugs]
allowed-tools: Read, Bash
---

# Gemini Analyze Command

Send a file to Gemini CLI for structured analysis.

## Usage

```text
/google-ecosystem:gemini-analyze <file-path> [analysis-type]
```

## Arguments

- `$1` (required): File path to analyze
- `$2` (optional): Analysis type - defaults to "general"
  - `security` - Security vulnerabilities and risks
  - `performance` - Performance issues and optimizations
  - `architecture` - Design patterns and structure
  - `bugs` - Potential bugs and edge cases
  - `general` - Overall code review

## Examples

- `/google-ecosystem:gemini-analyze src/auth.ts security`
- `/google-ecosystem:gemini-analyze lib/utils.py performance`
- `/google-ecosystem:gemini-analyze app/main.go architecture`
- `/google-ecosystem:gemini-analyze index.js bugs`
- `/google-ecosystem:gemini-analyze config.yaml` (defaults to general)

## Execution

### Step 1: Validate File

Check that the file exists and is readable:

```bash
if [ ! -f "$1" ]; then
  echo "Error: File not found: $1"
  exit 1
fi
```

### Step 2: Determine Analysis Type

```bash
analysis_type="${2:-general}"
```

### Step 3: Build Prompt

Create analysis-specific prompts:

```bash
case "$analysis_type" in
  security)
    prompt="Security audit this code. Identify:
1. Authentication/authorization vulnerabilities
2. Input validation issues
3. Injection vulnerabilities (SQL, XSS, command)
4. Sensitive data exposure
5. Cryptographic weaknesses

Rate each finding: CRITICAL, HIGH, MEDIUM, LOW"
    ;;
  performance)
    prompt="Performance review this code. Identify:
1. Algorithmic inefficiencies
2. Memory leaks or excessive allocation
3. Unnecessary operations
4. Missing caching opportunities
5. N+1 query patterns

Estimate impact: HIGH, MEDIUM, LOW"
    ;;
  architecture)
    prompt="Architecture review this code. Analyze:
1. Design patterns used
2. SOLID principles adherence
3. Separation of concerns
4. Dependency management
5. Extensibility and maintainability

Provide recommendations for improvement"
    ;;
  bugs)
    prompt="Bug hunt in this code. Look for:
1. Logic errors
2. Off-by-one errors
3. Null/undefined handling
4. Race conditions
5. Edge cases not handled
6. Type mismatches

Rate likelihood: LIKELY, POSSIBLE, UNLIKELY"
    ;;
  *)
    prompt="General code review. Evaluate:
1. Code quality and readability
2. Best practices adherence
3. Potential issues
4. Improvement suggestions"
    ;;
esac
```

### Step 4: Execute Analysis

```bash
result=$(cat "$1" | gemini -p "$prompt" --output-format json -m gemini-2.5-flash)
```

### Step 5: Parse Results

```bash
response=$(echo "$result" | jq -r '.response // "Analysis failed"')
tokens=$(echo "$result" | jq '.stats.models | to_entries | map(.value.tokens.total) | add // 0')
model=$(echo "$result" | jq -r '.stats.models | keys[0] // "unknown"')
```

## Output Format

Present findings in structured format:

```markdown
# Gemini Analysis: {filename}

**Type**: {analysis_type}
**Model**: {model}
**Tokens**: {tokens}

---

{response}

---
*Analysis by Gemini CLI*
```

## Notes

- Uses Flash model by default for cost efficiency
- Supports multiple analysis types with specialized prompts
- Structured findings with severity/impact ratings
- Token usage reported for cost tracking
