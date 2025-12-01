---
description: Execute a shell command in Gemini CLI sandbox for isolation
argument-hint: <command>
allowed-tools: Bash
---

# Gemini Sandbox Command

Execute a command in Gemini's sandboxed environment for safety.

## Usage

```text
/google-ecosystem:gemini-sandbox <command>
```

## Arguments

- `$ARGUMENTS` (required): Shell command to execute in sandbox

## Examples

- `/google-ecosystem:gemini-sandbox npm install some-unknown-package`
- `/google-ecosystem:gemini-sandbox pip install untrusted-lib`
- `/google-ecosystem:gemini-sandbox ./suspicious-script.sh`
- `/google-ecosystem:gemini-sandbox rm -rf /tmp/test/*` (test safely)
- `/google-ecosystem:gemini-sandbox curl http://example.com/script.sh | head`

## Execution

### Validate Command

```bash
if [ -z "$ARGUMENTS" ]; then
  echo "Error: No command provided"
  echo "Usage: /google-ecosystem:gemini-sandbox <command>"
  exit 1
fi
```

### Execute in Sandbox

Run with sandbox flag (`-s`) and auto-approve (`--yolo`):

```bash
result=$(gemini -s "Execute this shell command and report the complete output:

$ARGUMENTS

Report:
1. The full stdout output
2. Any stderr output
3. The exit code
4. Any observations about what the command did" --output-format json --yolo 2>&1)
```

### Parse Results

```bash
response=$(echo "$result" | jq -r '.response // "Execution failed"')
tokens=$(echo "$result" | jq '.stats.models | to_entries | map(.value.tokens.total) | add // 0')

# Check for errors
error=$(echo "$result" | jq -r '.error.message // empty')
```

## Output Format

Present execution results:

```markdown
## Sandboxed Execution

**Command**: `{command}`
**Sandbox**: Active (Docker/Podman/Seatbelt)

### Result

{response}

---
*Executed in Gemini sandbox | {tokens} tokens*
```

If error occurred:

```markdown
## Sandbox Execution Failed

**Command**: `{command}`
**Error**: {error}

The command could not be executed. Possible causes:
- Sandbox not available (Docker not running?)
- Command blocked by sandbox policy
- Invalid command syntax
```

## Sandbox Types

Gemini CLI supports multiple sandbox methods:

| Method   | Platform | Description                        |
| -------- | -------- | ---------------------------------- |
| Docker   | All      | Full container isolation           |
| Podman   | All      | Rootless container isolation       |
| Seatbelt | macOS    | Process sandbox using sandbox-exec |

## Security Notes

- Commands run in isolated environment
- File system access limited to project directory
- Network may be restricted depending on profile
- Sandbox prevents accidental system damage
- **Not a security guarantee** - defense in depth only

## Use Cases

### Test Untrusted Package Install

```text
/google-ecosystem:gemini-sandbox npm install sketchy-package-from-npm
```

### Run Unknown Script Safely

```text
/google-ecosystem:gemini-sandbox ./downloaded-script.sh
```

### Test Destructive Commands

```text
/google-ecosystem:gemini-sandbox rm -rf ./test-directory/
```

### Analyze Command Behavior

```text
/google-ecosystem:gemini-sandbox strace -f ./binary 2>&1 | head -100
```

## Prerequisites

**Sandbox requires one of the following to be configured:**

- **Docker**: Must be installed and running (`docker ps` should work)
- **Podman**: Must be installed (`podman --version` should work)
- **macOS Seatbelt**: Available on macOS by default

If sandbox is not available, the command will fail with an error. Configure sandbox in Gemini's `settings.json`:

```json
{
  "sandbox": {
    "type": "docker"
  }
}
```

## Notes

- Uses `-s` flag for sandbox enforcement
- Uses `--yolo` for automatic approval within sandbox
- Results are from isolated environment, not host system
- Sandbox must be configured (Docker running, etc.)
