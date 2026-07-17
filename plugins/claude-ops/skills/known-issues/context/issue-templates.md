# Anthropic Issue Templates Reference (Snapshot)

**Point-in-time snapshot for offline reference only.** `create` action MUST fetch live template from GitHub before drafting. Templates may change without notice.

Snapshot retrieved 2026-03-29 from `anthropics/claude-code/.github/ISSUE_TEMPLATE/`.

Live source:

```bash
gh api repos/anthropics/claude-code/contents/.github/ISSUE_TEMPLATE/<template>.yml --jq '.content' | base64 -d
```

Blank issues are disabled — all issues must use a template.

## Available templates

| Template | File | Label | Title prefix |
|----------|------|-------|-------------|
| Bug Report | `bug_report.yml` | `bug` | `[BUG]` |
| Feature Request | `feature_request.yml` | `enhancement` | `[FEATURE]` |
| Documentation | `documentation.yml` | (not fetched) | (not fetched) |
| Model Behavior | `model_behavior.yml` | (not fetched) | (not fetched) |

## Bug Report fields

| Field ID | Type | Required | Description |
|----------|------|----------|-------------|
| `preflight` | checkboxes | Yes | 3 required checks: searched existing, single bug, latest version |
| `actual` | textarea | Yes | "What's Wrong?" — describe the bug |
| `expected` | textarea | Yes | "What Should Happen?" — expected behavior |
| `error_output` | textarea | No | Error messages/logs (rendered as shell code block) |
| `reproduction` | textarea | Yes | Steps to reproduce (numbered, with code) |
| `model` | dropdown | No | Sonnet (default), Opus, Not sure, Other |
| `regression` | dropdown | Yes | Yes/No/Don't know |
| `working_version` | input | No | Last working version (if regression) |
| `version` | input | Yes | Claude Code version (`claude --version`) |
| `platform` | dropdown | Yes | Anthropic API, AWS Bedrock, Google Vertex AI, Other |
| `os` | dropdown | Yes | macOS, Windows, Ubuntu/Debian Linux, Other Linux, Other |
| `terminal` | dropdown | Yes | Terminal.app, Warp, Cursor, iTerm2, VS Code, Windows Terminal, etc. |
| `additional` | textarea | No | Screenshots, config files, links |

## Feature Request fields

| Field ID | Type | Required | Description |
|----------|------|----------|-------------|
| `preflight` | checkboxes | Yes | 2 required checks: searched existing, single feature |
| `problem` | textarea | Yes | Problem statement — what problem, why needed |
| `solution` | textarea | Yes | Proposed solution — ideal UX |
| `alternatives` | textarea | No | Alternative solutions considered |
| `priority` | dropdown | Yes | Critical, High, Medium, Low |
| `category` | dropdown | Yes | CLI, TUI, File ops, API, MCP, Performance, Config, SDK, Docs, Other |
| `use_case` | textarea | No | Concrete real-world example |
| `additional` | textarea | No | Screenshots, mockups, links |

## `gh issue create` with form templates

GitHub form-based issue templates (YAML) render as structured markdown in issue body. To create issue matching template format, construct body as markdown with section headers matching template field labels.

### Bug report body format

```markdown
### Preflight Checklist

- [X] I have searched existing issues and this hasn't been reported yet
- [X] This is a single bug report
- [X] I am using the latest version of Claude Code

### What's Wrong?

{description of the bug}

### What Should Happen?

{expected behavior}

### Error Messages/Logs

```shell
{error output if any}
```

### Steps to Reproduce

1. {step 1}
2. {step 2}
3. {step 3}

### Claude Model

{Sonnet / Opus / Not sure / Other}

### Is this a regression?

{Yes / No / I don't know}

### Last Working Version

{version or "N/A"}

### Claude Code Version

{output of claude --version}

### Platform

{Anthropic API / AWS Bedrock / Google Vertex AI / Other}

### Operating System

{macOS / Windows / Ubuntu/Debian Linux / Other Linux / Other}

### Terminal/Shell

{terminal name}

### Additional Information

{any additional context}

```

### Feature request body format

```markdown
### Preflight Checklist

- [X] I have searched existing requests and this feature hasn't been requested yet
- [X] This is a single feature request

### Problem Statement

{what problem, why needed}

### Proposed Solution

{ideal UX description}

### Alternative Solutions

{alternatives considered or "None"}

### Priority

{Critical / High / Medium / Low}

### Feature Category

{CLI / TUI / File ops / API / MCP / Performance / Config / SDK / Docs / Other}

### Use Case Example

{concrete scenario or "N/A"}

### Additional Context

{any additional info}
```

### `gh issue create` command patterns

```bash
# Bug report
gh issue create \
  --repo anthropics/claude-code \
  --title "[BUG] {concise title}" \
  --label "bug" \
  --body "$(cat <<'EOF'
{body from template above}
EOF
)"

# Feature request
gh issue create \
  --repo anthropics/claude-code \
  --title "[FEATURE] {concise title}" \
  --label "enhancement" \
  --body "$(cat <<'EOF'
{body from template above}
EOF
)"
```

### Auto-detectable values

These fields can be pre-filled automatically:

| Field | How to detect |
|-------|--------------|
| Claude Code Version | `claude --version 2>/dev/null` |
| Operating System | `uname -s` → Windows (MINGW/MSYS), macOS (Darwin), Linux |
| Terminal/Shell | `$TERM_PROGRAM` or `$TERM` |
| Platform | "Anthropic API" (default for this repo) |
| Is a regression? | If issue found via `/known-issues search`, check registry for prior working state |

## Contact links (non-issue options)

- Discord: https://anthropic.com/discord
- Docs: https://docs.claude.com/en/docs/claude-code
- Getting Started: https://docs.claude.com/en/docs/claude-code/quickstart
- Troubleshooting: https://docs.claude.com/en/docs/claude-code/troubleshooting
