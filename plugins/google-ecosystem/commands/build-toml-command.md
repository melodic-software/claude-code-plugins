---
description: Interactive wizard for building Gemini CLI TOML custom commands
argument-hint: [command-name] [--scope user|project] [--template git|test|docs|review]
allowed-tools: Read, Bash
---

# Build TOML Command

Interactive wizard for creating Gemini CLI custom commands in TOML format.

## Usage

```text
/google-ecosystem:build-toml-command [command-name] [options]
```

## Arguments

- `$1` (optional): Command name (will prompt if not provided)
- `--scope user|project` (optional): Where to save (default: user)
- `--template <type>` (optional): Start from template
  - `git` - Git-related commands
  - `test` - Testing commands
  - `docs` - Documentation commands
  - `review` - Code review commands
  - `analyze` - Analysis commands

## Examples

- `/google-ecosystem:build-toml-command` - Full interactive wizard
- `/google-ecosystem:build-toml-command commit --template git` - Git commit template
- `/google-ecosystem:build-toml-command test-unit --scope project` - Project-level command
- `/google-ecosystem:build-toml-command review --template review` - Code review template

## Interactive Flow

### Step 1: Command Name

If not provided, prompt for name:

```text
Enter command name (e.g., "commit", "review", "test/unit"):
> _
```

**Naming rules:**

- Lowercase letters, numbers, hyphens
- Use `/` for namespacing: `git/commit` → `/git:commit`

### Step 2: Scope Selection

```text
Where should this command be saved?
1. User (~/.gemini/commands/) - Available in all projects
2. Project (.gemini/commands/) - Only this project

> _
```

### Step 3: Template Selection

```text
Start from a template?
1. Empty - Start from scratch
2. Git - Git workflow commands
3. Test - Testing commands
4. Docs - Documentation generation
5. Review - Code review
6. Analyze - Code analysis

> _
```

### Step 4: Description

```text
Enter a short description (shown in command list):
> _
```

### Step 5: Prompt Construction

```text
Enter the prompt. Use:
- {{args}} for command arguments
- @{file} for file content injection
- !{command} for shell command injection

(Enter blank line when done)
> _
```

### Step 6: Preview & Confirm

Show generated TOML:

```toml
# Command: /your-command
# Location: ~/.gemini/commands/your-command.toml

description = "Your description"
prompt = """
Your prompt here
"""
```

```text
Save this command? (y/n)
> _
```

## Templates

### Git Template

```toml
description = "Generate commit message from staged changes"
prompt = """
Analyze the staged git changes and generate a commit message.

## Changes
~~~diff
!{git diff --staged}
~~~

## Requirements

- Use conventional commit format (feat/fix/docs/refactor/test/chore)
- Keep subject line under 72 characters
- Add body if changes are significant

Generate only the commit message.
"""

```

### Test Template

```toml
description = "Generate tests for specified file"
prompt = """
Generate comprehensive tests for this file:

@{{{args}}}

Requirements:
- Use the project's test framework
- Cover edge cases and error conditions
- Follow existing test patterns
- Include both positive and negative tests
"""
```

### Docs Template

```toml
description = "Generate documentation for code"
prompt = """
Generate documentation for:

@{{{args}}}

Include:
- Purpose and overview
- Function/method documentation
- Usage examples
- Parameter descriptions
- Return value descriptions
"""
```

### Review Template

```toml
description = "Review code changes"
prompt = """
Review the following changes:

~~~diff
!{git diff}
~~~

Focus areas: {{args}}

Provide:

1. Issues found (bugs, security, performance)
2. Suggestions for improvement
3. Positive observations
4. Questions or concerns
"""

```

### Analyze Template

```toml
description = "Analyze code for specified concerns"
prompt = """
Analyze this code:

@{{{args}}}

Check for:
1. Code quality issues
2. Potential bugs
3. Performance concerns
4. Security vulnerabilities
5. Maintainability problems

Provide specific, actionable feedback.
"""
```

## Execution

### Step 1: Parse Arguments

```bash
command_name="$1"
scope="user"
template=""

# Parse flags
shift
while [[ $# -gt 0 ]]; do
  case "$1" in
    --scope)
      scope="$2"
      shift 2
      ;;
    --template)
      template="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
```

### Step 2: Determine Output Path

```bash
if [ "$scope" = "project" ]; then
  base_dir=".gemini/commands"
else
  base_dir="$HOME/.gemini/commands"
fi

# Handle namespaced commands (git/commit -> git/commit.toml)
if [[ "$command_name" == *"/"* ]]; then
  namespace=$(dirname "$command_name")
  name=$(basename "$command_name")
  output_dir="$base_dir/$namespace"
  output_file="$output_dir/$name.toml"
else
  output_dir="$base_dir"
  output_file="$base_dir/$command_name.toml"
fi
```

### Step 3: Load Template

```bash
case "$template" in
  git)
    description="Generate commit message from staged changes"
    prompt='...'  # Git template
    ;;
  test)
    description="Generate tests for specified file"
    prompt='...'  # Test template
    ;;
  # ... other templates
  *)
    description=""
    prompt=""
    ;;
esac
```

### Step 4: Interactive Prompts

If running interactively, prompt for missing values.

### Step 5: Generate TOML

```bash
cat << EOF
description = "$description"
prompt = """
$prompt
"""
EOF
```

### Step 6: Save File

```bash
mkdir -p "$output_dir"
cat > "$output_file" << EOF
description = "$description"
prompt = """
$prompt
"""
EOF

echo "Command saved to: $output_file"
echo "Use with: /${command_name/\//:}"
```

## Output

### Success Message

```text
Command created successfully!

File: ~/.gemini/commands/commit.toml
Usage: /commit [args]

Test it:
  gemini
  > /commit

To edit later:
  $EDITOR ~/.gemini/commands/commit.toml
```

### Preview Mode

```toml
# Preview - not saved yet
# File: ~/.gemini/commands/commit.toml

description = "Generate commit message from staged changes"
prompt = """
Analyze staged changes and generate a conventional commit message.

## Changes
~~~diff
!{git diff --staged}
~~~

Generate only the commit message.
"""

```

## Validation

Before saving, validate:

1. **Name**: Valid characters, no conflicts
2. **Description**: Non-empty, reasonable length
3. **Prompt**: Non-empty, balanced braces
4. **Syntax**: Valid TOML

```bash
# Validate TOML
python -c "import tomllib; tomllib.load(open('temp.toml', 'rb'))" 2>&1
```

## Tips

### Shell Injection Safety

```toml
# Good - read-only, limited output
!{git diff --staged | head -500}

# Risky - be careful
!{cat {{args}}}  # User controls path
```

### Argument Escaping

Arguments in `!{...}` blocks are automatically escaped:

```toml
# Safe - args escaped in shell context
prompt = "Search for: !{grep '{{args}}' src/}"
```

### Multi-line Prompts

Use triple quotes for readability:

```toml
prompt = """
First line.
Second line.

## Section
More content.
"""
```

## Notes

- Commands are loaded on Gemini CLI startup
- Restart Gemini to see new commands
- Test with `gemini` then `/your-command`
- Edit with your preferred editor
- Use `--scope project` for project-specific commands
