<!-- Source: https://docs.claude.com/en/docs/agents-and-tools/tool-use/bash-tool -->

# Bash tool

The bash tool enables Claude to execute shell commands in a persistent bash session, allowing system operations, script execution, and command-line automation.

## Overview

The bash tool provides Claude with:

* Persistent bash session that maintains state
* Ability to run any shell command
* Access to environment variables and working directory
* Command chaining and scripting capabilities

## Model compatibility

| Model                                                                                   | Tool Version    |
| --------------------------------------------------------------------------------------- | --------------- |
| Claude 4 models and Sonnet 3.7 ([deprecated](/en/docs/about-claude/model-deprecations)) | `bash_20250124` |

<Warning>
  Older tool versions are not guaranteed to be backwards-compatible with newer models. Always use the tool version that corresponds to your model version.
</Warning>

## Use cases

* **Development workflows**: Run build commands, tests, and development tools
* **System automation**: Execute scripts, manage files, automate tasks
* **Data processing**: Process files, run analysis scripts, manage datasets
* **Environment setup**: Install packages, configure environments

## Quick start

<CodeGroup>
  ```python Python theme={null}
  import anthropic

  client = anthropic.Anthropic()

  response = client.messages.create(
      model="claude-sonnet-4-5",
      max_tokens=1024,
      tools=[
          {
              "type": "bash_20250124",
              "name": "bash"
          }
      ],
      messages=[
          {"role": "user", "content": "List all Python files in the current directory."}
      ]
  )
  ```

  ```bash Shell theme={null}
  curl https://api.anthropic.com/v1/messages \
    -H "content-type: application/json" \
    -H "x-api-key: $ANTHROPIC_API_KEY" \
    -H "anthropic-version: 2023-06-01" \
    -d '{
      "model": "claude-sonnet-4-5",
      "max_tokens": 1024,
      "tools": [
        {
          "type": "bash_20250124",
          "name": "bash"
        }
      ],
      "messages": [
        {
          "role": "user",
          "content": "List all Python files in the current directory."
        }
      ]
    }'
  ```
</CodeGroup>

## How it works

The bash tool maintains a persistent session:

1. Claude determines what command to run
2. You execute the command in a bash shell
3. Return the output (stdout and stderr) to Claude
4. Session state persists between commands (environment variables, working directory)

## Parameters

| Parameter | Required | Description                               |
| --------- | -------- | ----------------------------------------- |
| `command` | Yes\*    | The bash command to run                   |
| `restart` | No       | Set to `true` to restart the bash session |

\*Required unless using `restart`

<Accordion title="Example usage">
  ```json  theme={null}
  // Run a command
  {
    "command": "ls -la *.py"
  }

  // Restart the session
  {
    "restart": true
  }
  ```
</Accordion>

## Example: Multi-step automation

Claude can chain commands to complete complex tasks:

```python  theme={null}