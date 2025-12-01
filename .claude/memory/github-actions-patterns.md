# Github Actions Patterns

This document covers patterns for integrating Claude Code with GitHub Actions for autonomous workflows, batch processing, and operational excellence.

## Overview

The Claude Code GitHub Action (GHA) runs Claude Code in a containerized CI/CD environment. This enables:

- Autonomous PR generation from any trigger source
- Full environment control and sandboxing
- Complete audit trails via GHA logs
- Support for hooks, MCP servers, and all Claude Code features

## PR-from-Anywhere Pattern

Trigger PR creation from external events without human intervention.

### Architecture

```text
External Trigger -> GitHub Actions -> Claude Code -> Pull Request
     |                   |               |              |
   Slack              Container      Full agent      Ready for
   Jira               sandbox        execution       review
   CloudWatch         + audit
   Webhook
```

### Trigger Sources

| Source          | Use Case                                          |
| --------------- | ------------------------------------------------- |
| Slack command   | "Fix the login bug" triggers automated fix        |
| Jira transition | Issue moved to "Ready for Dev" triggers impl      |
| CloudWatch      | Error threshold triggers automated investigation  |
| Webhook         | External system requests code changes             |
| Schedule        | Periodic maintenance, dependency updates          |
| Issue comment   | User requests help, Claude responds with PR       |

### Example Workflow

```yaml
name: Claude Code PR Generator
on:
  repository_dispatch:
    types: [claude-fix-request]
  workflow_dispatch:
    inputs:
      task:
        description: 'Task for Claude to complete'
        required: true

jobs:
  generate-pr:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Run Claude Code
        uses: anthropic/claude-code-action@v1
        with:
          anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
          prompt: ${{ github.event.inputs.task || github.event.client_payload.task }}
          allowed_tools: "Read,Write,Edit,Bash,Glob,Grep"

      - name: Create PR
        uses: peter-evans/create-pull-request@v5
        with:
          title: "Claude: ${{ github.event.inputs.task }}"
          body: "Automated changes by Claude Code"
```

### Security Considerations

- Use repository secrets for API keys
- Restrict allowed tools to minimum necessary
- Review PRs before merging (human in the loop)
- Set up branch protection rules
- Consider separate bot account for attribution

## Ops Log Review Process

GHA logs contain full agent execution traces - use them for continuous improvement.

### Log Structure

GitHub Actions logs capture:

- Full conversation history
- Tool calls and responses
- Error messages and stack traces
- Timing information
- Token usage

### Data-Driven Improvement Flywheel

```text
1. Collect: GHA runs produce logs
      |
2. Analyze: Query logs for patterns
      |
3. Fix: Update CLAUDE.md, tooling, workflows
      |
4. Verify: Check if errors decrease
      |
   (repeat)
```

### Analysis Patterns

```bash
# Query recent Claude GHA logs for common errors
gh run list --workflow=claude-code.yml --limit=50 --json databaseId \
  | jq -r '.[].databaseId' \
  | xargs -I{} gh run view {} --log \
  | grep -i "error\|failed\|exception" \
  | sort | uniq -c | sort -rn

# Find common tool failures
gh run view <run-id> --log | grep "tool_use.*failed"

# Extract successful patterns for documentation
gh run view <run-id> --log | grep "completed successfully"
```

### Meta-Analysis Workflow

Use Claude itself to analyze Claude logs:

```bash
# Download recent logs
gh run view <run-id> --log > claude-run.log

# Have Claude analyze them
claude -p "Analyze this Claude Code execution log. \
  Identify: 1) Common mistakes 2) Failed patterns 3) Successful strategies. \
  Suggest CLAUDE.md improvements." < claude-run.log
```

### Regular Review Cadence

| Frequency | Focus                               |
| --------- | ----------------------------------- |
| Daily     | Critical errors, failed runs        |
| Weekly    | Pattern analysis, common issues     |
| Monthly   | CLAUDE.md updates, tooling changes  |
| Quarterly | Architecture review, major updates  |

## Batch Processing Patterns

Use Claude Code for large-scale automated changes.

### Fan-Out Pattern

Process many items in parallel:

```yaml
jobs:
  prepare:
    runs-on: ubuntu-latest
    outputs:
      matrix: ${{ steps.set-matrix.outputs.matrix }}
    steps:
      - id: set-matrix
        run: |
          # Generate list of files to process
          echo "matrix=$(find src -name '*.py' | jq -R -s -c 'split("\n")[:-1]')" >> $GITHUB_OUTPUT

  process:
    needs: prepare
    runs-on: ubuntu-latest
    strategy:
      matrix:
        file: ${{ fromJson(needs.prepare.outputs.matrix) }}
      max-parallel: 5
    steps:
      - uses: anthropic/claude-code-action@v1
        with:
          prompt: "Migrate ${{ matrix.file }} from Python 2 to Python 3 style"
```

### Headless Mode for Batch

Use `claude -p` for scripted batch operations:

```bash
# Process multiple files
for file in src/*.py; do
  claude -p "Add type hints to $file. Return OK if succeeded, FAIL if failed." \
    --allowedTools Edit,Read
done

# With output processing
claude -p "Analyze security of auth.py" --output-format json \
  | jq '.findings[] | select(.severity == "high")'
```

### When to Use GHA vs Local

| Scenario                     | Recommendation    |
| ---------------------------- | ----------------- |
| PR generation from events    | GHA               |
| Audit trail required         | GHA               |
| Sandboxing critical          | GHA               |
| Quick iteration              | Local             |
| Interactive refinement       | Local             |
| Cost-sensitive batch         | Local (parallel)  |

## Issue Triage Automation

Automatically respond to and triage new issues.

### Example: Auto-Label and Respond

```yaml
on:
  issues:
    types: [opened]

jobs:
  triage:
    runs-on: ubuntu-latest
    steps:
      - uses: anthropic/claude-code-action@v1
        with:
          prompt: |
            Analyze this issue:
            Title: ${{ github.event.issue.title }}
            Body: ${{ github.event.issue.body }}

            1. Suggest appropriate labels (bug, feature, docs, etc.)
            2. Assess priority (P0-P3)
            3. Identify relevant code areas
            4. Draft a helpful initial response

            Output as JSON: {labels: [], priority: "", areas: [], response: ""}
```

## Code Review Automation

Augment human code review with automated analysis.

### Example: PR Review Assistant

```yaml
on:
  pull_request:
    types: [opened, synchronize]

jobs:
  review:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Get diff
        run: git diff origin/main...HEAD > pr.diff

      - uses: anthropic/claude-code-action@v1
        with:
          prompt: |
            Review this PR diff for:
            1. Bugs or logic errors
            2. Security issues
            3. Performance concerns
            4. Style/convention violations
            5. Missing tests

            Be specific with line numbers and suggestions.
```

## Security Best Practices

### Sandboxing Benefits

GHA provides stronger isolation than local execution:

- Ephemeral container environment
- Network policies can be applied
- No access to local credentials or SSH keys
- Complete audit trail in logs
- Reproducible environment

### Credential Management

```yaml
# Use GitHub Secrets
env:
  ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}

# Never hardcode keys
# Never log sensitive values
# Use least-privilege API keys when possible
```

### Tool Restrictions

```yaml
# Restrict to read-only for analysis
allowed_tools: "Read,Glob,Grep"

# Allow writes only for specific tasks
allowed_tools: "Read,Write,Edit,Bash(npm:*)"
```

## Monitoring and Observability

### Key Metrics to Track

| Metric               | Purpose                               |
| -------------------- | ------------------------------------- |
| Success rate         | Overall reliability                   |
| Token usage          | Cost tracking                         |
| Execution time       | Performance baseline                  |
| Error categories     | Identify improvement areas            |
| PR merge rate        | Quality of generated changes          |

### Alerting

Set up alerts for:

- Failed runs above threshold
- Unusual token consumption
- Repeated errors on same files
- Long execution times

---

**Last Updated:** 2025-11-30
