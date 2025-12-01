---
description: Synchronize CLAUDE.md to GEMINI.md and check for context drift
argument-hint: [--status] [--init] [--force]
allowed-tools: Read, Bash, Glob
---

# Sync Context Command

Check and synchronize context between CLAUDE.md (source of truth) and GEMINI.md.

## Usage

```text
/google-ecosystem:sync-context [options]
```

## Arguments

- `--status` - Show sync status without making changes
- `--init` - Initialize GEMINI.md with @import pattern
- `--force` - Force regenerate GEMINI.md from template

## Examples

- `/google-ecosystem:sync-context` - Check sync status
- `/google-ecosystem:sync-context --status` - Show detailed sync report
- `/google-ecosystem:sync-context --init` - Create GEMINI.md if missing
- `/google-ecosystem:sync-context --force` - Regenerate GEMINI.md

## Sync Strategy

This command implements the **@import pattern**:

```markdown
# GEMINI.md
@CLAUDE.md

## Gemini-Specific Overrides
{overrides}
```

With this pattern, GEMINI.md automatically stays in sync because it imports CLAUDE.md directly via Gemini's memport system.

## Execution

### Step 1: Parse Arguments

```bash
mode="status"  # default

case "$1" in
  --status) mode="status" ;;
  --init)   mode="init" ;;
  --force)  mode="force" ;;
esac
```

### Step 2: Check Prerequisites

```bash
# Check CLAUDE.md exists
if [ ! -f "CLAUDE.md" ]; then
  echo "ERROR: CLAUDE.md not found"
  echo "Create CLAUDE.md first - it's the source of truth"
  exit 1
fi
```

### Step 3: Determine Sync State

```bash
# Create sync state directory
mkdir -p .claude/temp

# Get current CLAUDE.md hash
claude_hash=$(md5sum CLAUDE.md | cut -d' ' -f1)

# Read stored state
if [ -f ".claude/temp/sync-state.json" ]; then
  stored_hash=$(cat .claude/temp/sync-state.json | jq -r '.claude_hash // ""')
  last_sync=$(cat .claude/temp/sync-state.json | jq -r '.last_sync // "never"')
else
  stored_hash=""
  last_sync="never"
fi

# Check if GEMINI.md exists
gemini_exists="no"
gemini_uses_import="no"
if [ -f "GEMINI.md" ]; then
  gemini_exists="yes"
  if head -5 GEMINI.md | grep -q "^@CLAUDE.md"; then
    gemini_uses_import="yes"
  fi
fi
```

### Step 4: Execute Based on Mode

#### Status Mode

```bash
if [ "$mode" = "status" ]; then
  echo "## Context Sync Status"
  echo ""
  echo "| File | Status |"
  echo "|------|--------|"
  echo "| CLAUDE.md | EXISTS |"
  echo "| GEMINI.md | $gemini_exists |"
  echo "| Uses @import | $gemini_uses_import |"
  echo ""
  echo "**CLAUDE.md Hash:** $claude_hash"
  echo "**Stored Hash:** ${stored_hash:-none}"
  echo "**Last Sync:** $last_sync"
  echo ""

  if [ "$claude_hash" = "$stored_hash" ]; then
    echo "**Status:** IN SYNC"
  else
    echo "**Status:** CLAUDE.md has changed since last sync"
  fi

  if [ "$gemini_uses_import" = "yes" ]; then
    echo ""
    echo "**Note:** GEMINI.md uses @import pattern - automatically in sync"
  fi
fi
```

#### Init Mode

```bash
if [ "$mode" = "init" ]; then
  if [ "$gemini_exists" = "yes" ]; then
    echo "GEMINI.md already exists. Use --force to regenerate."
    exit 1
  fi

  cat > GEMINI.md << 'GEMINI_EOF'
# GEMINI.md

@CLAUDE.md

## Gemini-Specific Overrides

You are Gemini CLI. Your unique capabilities include:

- **Large context window** (Flash) / Very large (Pro)
- **Interactive PTY shell** - vim, git rebase -i, htop, psql
- **Checkpointing** - Git-based snapshots with instant rollback
- **Policy engine** - TOML-based tool execution control
- **Native Google Cloud authentication**

### When to Leverage Your Strengths

Use your large context for:
- Full codebase exploration and architecture analysis
- Bulk file processing and pattern detection
- Large log file analysis

Use your interactive shell for:
- vim, nano, emacs editing sessions
- git rebase -i, git add -p
- Database CLIs (psql, mysql, redis-cli)
- System monitors (htop, top)

Use checkpointing for:
- Risky refactoring operations
- Experimental changes
- Database migrations

### Model Selection

- **Flash** (gemini-2.5-flash): Bulk analysis, simple tasks, cost-effective
- **Pro** (gemini-2.5-pro): Complex reasoning, quality-critical, very large contexts
GEMINI_EOF

  # Update sync state
  echo "{\"claude_hash\": \"$claude_hash\", \"last_sync\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" > .claude/temp/sync-state.json

  echo "GEMINI.md created with @import to CLAUDE.md"
  echo "Sync state initialized"
fi
```

#### Force Mode

```bash
if [ "$mode" = "force" ]; then
  # Backup existing
  if [ -f "GEMINI.md" ]; then
    cp GEMINI.md "GEMINI.md.backup.$(date +%Y%m%d%H%M%S)"
    echo "Backed up existing GEMINI.md"
  fi

  # Same as init
  cat > GEMINI.md << 'GEMINI_EOF'
# GEMINI.md

@CLAUDE.md

## Gemini-Specific Overrides

You are Gemini CLI. Your unique capabilities include:

- **Large context window** (Flash) / Very large (Pro)
- **Interactive PTY shell** - vim, git rebase -i, htop, psql
- **Checkpointing** - Git-based snapshots with instant rollback
- **Policy engine** - TOML-based tool execution control
- **Native Google Cloud authentication**

### When to Leverage Your Strengths

Use your large context for:
- Full codebase exploration and architecture analysis
- Bulk file processing and pattern detection
- Large log file analysis

Use your interactive shell for:
- vim, nano, emacs editing sessions
- git rebase -i, git add -p
- Database CLIs (psql, mysql, redis-cli)
- System monitors (htop, top)

Use checkpointing for:
- Risky refactoring operations
- Experimental changes
- Database migrations

### Model Selection

- **Flash** (gemini-2.5-flash): Bulk analysis, simple tasks, cost-effective
- **Pro** (gemini-2.5-pro): Complex reasoning, quality-critical, very large contexts
GEMINI_EOF

  # Update sync state
  echo "{\"claude_hash\": \"$claude_hash\", \"last_sync\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" > .claude/temp/sync-state.json

  echo "GEMINI.md regenerated with @import to CLAUDE.md"
  echo "Sync state updated"
fi
```

## Output Examples

### Status Check

```text
## Context Sync Status

| File | Status |
|------|--------|
| CLAUDE.md | EXISTS |
| GEMINI.md | yes |
| Uses @import | yes |

**CLAUDE.md Hash:** a1b2c3d4e5f6
**Stored Hash:** a1b2c3d4e5f6
**Last Sync:** 2025-11-30T12:00:00Z

**Status:** IN SYNC

**Note:** GEMINI.md uses @import pattern - automatically in sync
```

### Init Success

```text
GEMINI.md created with @import to CLAUDE.md
Sync state initialized
```

## Notes

- CLAUDE.md is always the source of truth
- GEMINI.md should use @import pattern for automatic sync
- Sync state stored in `.claude/temp/sync-state.json`
- Backups created automatically with --force
- The @import pattern means GEMINI.md is always in sync with CLAUDE.md
