---
description: Explore entire codebase with Gemini's large context window and output a structured markdown report
argument-hint: [scope: architecture|dependencies|patterns|all] [--output <path>]
allowed-tools: Read, Bash, Glob
---

# Gemini Explore Command

Delegate full codebase exploration to Gemini CLI's large context window. Outputs a structured markdown report for Claude to consume.

## Usage

```text
/google-ecosystem:gemini-explore [scope] [--output <path>]
```

## Arguments

- `$1` (optional): Exploration scope - defaults to "all"
  - `architecture` - High-level structure, modules, entry points
  - `dependencies` - Package dependencies, imports, relationships
  - `patterns` - Design patterns, conventions, code style
  - `all` - Comprehensive exploration (default)
- `--output <path>` (optional): Output path for report (default: `docs/ai-artifacts/explorations/`)

## Examples

- `/google-ecosystem:gemini-explore` - Full exploration with default output
- `/google-ecosystem:gemini-explore architecture` - Focus on architecture
- `/google-ecosystem:gemini-explore dependencies --output ./reports/` - Dependencies to custom path
- `/google-ecosystem:gemini-explore patterns` - Focus on patterns and conventions

## When to Use

Use this command when:

- Starting work on an unfamiliar codebase
- Codebase exceeds 50K tokens (Claude's effective working context)
- Need comprehensive architecture understanding before implementation
- Want to map dependencies across a monorepo
- Identifying patterns before large refactoring

## Token Threshold Guidance

| Codebase Size | Recommended Action              |
| ------------- | ------------------------------- |
| <50K tokens   | Use Claude's native exploration |
| 50K-500K      | Gemini Flash (this command)     |
| 500K-1M       | Gemini Flash with chunking      |
| >1M           | Gemini Pro (add `--pro` flag)   |

## Execution

### Step 1: Estimate Token Count

```bash
# Count all source files and estimate tokens
total_chars=$(find . -type f \( -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" -o -name "*.py" -o -name "*.go" -o -name "*.rs" -o -name "*.java" \) -not -path "*/node_modules/*" -not -path "*/.git/*" -not -path "*/dist/*" -not -path "*/build/*" | xargs wc -c 2>/dev/null | tail -1 | awk '{print $1}')
estimated_tokens=$((total_chars / 4))
echo "Estimated tokens: $estimated_tokens"
```

### Step 2: Determine Model

```bash
if [ "$estimated_tokens" -gt 1000000 ]; then
  model="gemini-2.5-pro"
else
  model="gemini-2.5-flash"
fi
```

### Step 3: Build Scope-Specific Prompt

```bash
scope="${1:-all}"

case "$scope" in
  architecture)
    prompt="EXPLORATION MODE: Analyze this codebase architecture.

Provide:
1. **Project Overview**: What does this project do?
2. **Directory Structure**: Key directories and their purpose
3. **Entry Points**: Main entry files and startup flow
4. **Core Modules**: Key modules and their responsibilities
5. **Architecture Pattern**: MVC, Clean Architecture, etc.
6. **Technology Stack**: Languages, frameworks, libraries

Format as structured markdown with headers."
    ;;
  dependencies)
    prompt="EXPLORATION MODE: Map dependencies in this codebase.

Provide:
1. **External Dependencies**: Package managers, versions
2. **Internal Dependencies**: Module import graph
3. **Circular Dependencies**: Any detected cycles
4. **Dependency Health**: Outdated, deprecated, security issues
5. **Shared Libraries**: Common utilities used across modules

Format as structured markdown with tables where appropriate."
    ;;
  patterns)
    prompt="EXPLORATION MODE: Identify patterns in this codebase.

Provide:
1. **Design Patterns**: Factory, Singleton, Observer, etc.
2. **Code Conventions**: Naming, file structure, imports
3. **Error Handling**: How errors are managed
4. **State Management**: How state flows through the app
5. **Testing Patterns**: Test structure, mocking strategies
6. **Documentation Style**: Comments, JSDoc, docstrings

Format as structured markdown with code examples."
    ;;
  *)
    prompt="EXPLORATION MODE: Comprehensive codebase exploration.

Provide a complete analysis covering:

## Architecture
- Project purpose and overview
- Directory structure and organization
- Entry points and startup flow
- Core modules and responsibilities

## Dependencies
- External packages and versions
- Internal module relationships
- Any circular dependencies

## Patterns & Conventions
- Design patterns used
- Coding conventions
- Error handling approach
- Testing structure

## Recommendations for Claude
- Key files to read first
- Important patterns to follow
- Potential areas of concern

Format as structured markdown suitable for another AI agent to consume."
    ;;
esac
```

### Step 4: Collect Source Files

```bash
# Collect all source files respecting common ignores
files=$(find . -type f \( -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" -o -name "*.py" -o -name "*.go" -o -name "*.rs" -o -name "*.java" -o -name "*.md" -o -name "*.json" \) -not -path "*/node_modules/*" -not -path "*/.git/*" -not -path "*/dist/*" -not -path "*/build/*" -not -path "*/__pycache__/*" -not -path "*/.next/*" | head -500)
```

### Step 5: Execute Exploration

```bash
result=$(cat $files 2>/dev/null | gemini "$prompt" --output-format json -m "$model")
```

### Step 6: Parse Results

```bash
response=$(echo "$result" | jq -r '.response // "Exploration failed"')
total_tokens=$(echo "$result" | jq '.stats.models | to_entries | map(.value.tokens.total) | add // 0')
model_used=$(echo "$result" | jq -r '.stats.models | keys[0] // "unknown"')
```

### Step 7: Generate Report

Create structured markdown report:

````markdown
---
generated-by: gemini-cli
model: {model_used}
timestamp: {ISO8601}
tokens: {total_tokens}
scope: {scope}
---

# Codebase Exploration Report

## Machine-Readable Summary
```json
{
  "type": "exploration",
  "scope": "{scope}",
  "tokens_used": {total_tokens},
  "model": "{model_used}",
  "key_findings": [
    "Finding 1",
    "Finding 2"
  ]
}
```

{response}

---
*Generated by Gemini CLI via `/gemini-explore` command*
````

### Step 8: Save Report

```bash
output_dir="${output:-docs/ai-artifacts/explorations}"
mkdir -p "$output_dir"
timestamp=$(date -u +"%Y-%m-%dT%H-%M-%SZ")
output_file="$output_dir/exploration-${scope}-${timestamp}.md"
echo "$report" > "$output_file"
echo "Report saved to: $output_file"
```

## Output Format

Reports are saved with YAML frontmatter for machine parsing:

- **generated-by**: Always "gemini-cli"
- **model**: Which Gemini model was used
- **timestamp**: ISO 8601 format
- **tokens**: Total tokens consumed
- **scope**: Exploration scope used

## Notes

- Uses Flash model by default for cost efficiency
- Automatically excludes node_modules, .git, dist, build directories
- Reports are saved to `docs/ai-artifacts/explorations/` by default (git-tracked)
- Token usage reported for cost awareness
- Output designed for Claude to read and act upon
