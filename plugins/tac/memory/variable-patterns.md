# Variable Patterns for Agentic Prompts

Variables drive reusability in prompts. Understanding dynamic vs static patterns is essential.

## Variable Types

### Dynamic Variables (User Input)

Accept input from the user at runtime.

| Pattern | Description | Example |
| --------- | ------------- | --------- |
| `$1` | First positional argument | `FILE_PATH: $1` |
| `$2` | Second positional argument | `COUNT: $2` |
| `$3` | Third positional argument | `MODEL: $3` |
| `$ARGUMENTS` | All arguments as string | `USER_PROMPT: $ARGUMENTS` |

### Static Variables (Fixed Values)

Fixed values defined in the prompt.

```markdown
## Variables

OUTPUT_DIR: specs/
MODEL: sonnet
ASPECT_RATIO: 16:9
MAX_RETRIES: 3
```markdown

## Variable Section Structure

```markdown
## Variables

# Dynamic (from user)
USER_PROMPT: $ARGUMENTS
FILE_PATH: $1
COUNT: $2 or 3 if not provided

# Static (fixed)
OUTPUT_DIR: specs/
MODEL: sonnet
LOG_LEVEL: info
```markdown

**Conventions:**

1. Dynamic variables first
2. Static variables second
3. SCREAMING_SNAKE_CASE for all names
4. Clear descriptions where helpful

## Default Values

Provide defaults when arguments are optional.

```markdown
COUNT: $2 or 3 if not provided
MODEL: $3 or "sonnet" if not provided
FORMAT: $2 or "markdown" if not specified
```markdown

Pattern: `$N or <default> if not provided`

## Naming Convention

**Use SCREAMING_SNAKE_CASE:**

| Good | Bad |
| ------ | ----- |
| `USER_PROMPT` | `userPrompt` |
| `OUTPUT_DIR` | `output-dir` |
| `FILE_PATH` | `filePath` |
| `MAX_RETRIES` | `maxRetries` |

## Referencing Variables in Workflow

Variables defined in the Variables section can be referenced in Workflow:

```markdown
## Variables
USER_PROMPT: $ARGUMENTS
OUTPUT_DIR: specs/

## Workflow
1. Parse the USER_PROMPT for requirements
2. Generate implementation plan
3. Save to OUTPUT_DIR/<filename>.md
4. Report the created file path
```markdown

**Reference Style:**

- Use the variable name directly
- Wrap in backticks for clarity: `USER_PROMPT`
- Can use in paths: `OUTPUT_DIR/<filename>.md`

## Computed Variables

Some variables are computed during execution:

```markdown
## Variables
IMAGE_OUTPUT_DIR: agentic_drop_zone/image_output/<date_time>/

## Workflow
1. Get current <date_time> by running `date +%Y-%m-%d_%H-%M-%S`
2. Create IMAGE_OUTPUT_DIR directory
```markdown

**Pattern:** Use `<placeholder>` for computed values.

## Common Variable Patterns

### Path Variables

```markdown
OUTPUT_DIR: specs/
LOG_DIR: logs/
BUNDLE_DIR: agents/context_bundles/
```markdown

### Configuration Variables

```markdown
MODEL: sonnet
MAX_TURNS: 10
TIMEOUT: 300
ALLOWED_TOOLS: Read, Write, Edit
```markdown

### Input Processing Variables

```markdown
USER_PROMPT: $ARGUMENTS
SOURCE_FILE: $1
TARGET_FILE: $2
OPTIONS: $3 or "--default" if not provided
```markdown

### Loop Variables

```markdown
NUMBER_OF_IMAGES: $2 or 3 if not provided
MAX_ITERATIONS: 10
BATCH_SIZE: 5
```markdown

## Frontmatter vs Variables Section

| Location | Purpose | Scope |
| ---------- | --------- | ------- |
| **Frontmatter** | Configuration | Claude Code behavior |
| **Variables Section** | Data | Prompt execution |

**Frontmatter:**

```yaml
---
allowed-tools: Read, Write
model: sonnet
argument-hint: [file-path] [count]
---
```markdown

**Variables Section:**

```markdown
## Variables
FILE_PATH: $1
COUNT: $2 or 5 if not provided
```markdown

## Variable Validation Pattern

```markdown
## Workflow
1. Validate inputs
   - If USER_PROMPT is empty, STOP and ask user
   - If FILE_PATH doesn't exist, STOP and report error
   - If COUNT > 10, warn user about resource usage
2. Continue with validated inputs
```markdown

Always validate dynamic variables before using them.

## Anti-Patterns

| Anti-Pattern | Problem | Solution |
| -------------- | --------- | ---------- |
| `user_prompt` | Inconsistent naming | `USER_PROMPT` |
| No defaults | Fails when arg missing | Add `or X if not provided` |
| Magic values | Hard to understand | Define as static variable |
| Inline paths | Hard to change | Extract to variable |
| Unvalidated input | Runtime failures | Validate in Workflow step 1 |

## Complete Example

```markdown
---
description: Generate images from prompt
argument-hint: [prompt] [count]
allowed-tools: Bash, Write, mcp__replicate
model: sonnet
---

# Generate Images

## Variables

# Dynamic
IMAGE_PROMPT: $1
COUNT: $2 or 3 if not provided

# Static
OUTPUT_DIR: generated/images/
MODEL: replicate/sdxl
ASPECT_RATIO: 16:9
MAX_RETRIES: 3

## Workflow

1. Validate inputs
   - If IMAGE_PROMPT is empty, STOP and ask user for prompt
   - If COUNT > 10, warn about resource usage

2. Create OUTPUT_DIR if it doesn't exist

3. Generate COUNT images
   <generation-loop>
   - Call MODEL with IMAGE_PROMPT
   - Set ASPECT_RATIO
   - Save to OUTPUT_DIR/<timestamp>_<index>.png
   - Retry up to MAX_RETRIES on failure
   </generation-loop>

4. Report generated files

## Report
Generated COUNT images to OUTPUT_DIR
```yaml

## Key Quote

> "Variables drive reusability. Static vs dynamic variables let you template prompts that can be customized for any task."

---

**Cross-References:**

- @prompt-sections-reference.md - Variables is A-tier section
- @seven-levels.md - Variables used from Level 2+
- @control-flow-patterns.md - Using variables in conditionals
