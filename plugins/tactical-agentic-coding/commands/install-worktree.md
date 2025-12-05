---
description: Set up isolated Git worktree environment for parallel agent execution
argument-hint: [worktree-path] [backend-port] [frontend-port]
---

# Install Worktree

Set up an isolated Git worktree environment for parallel agent execution.

## Arguments

- `$1`: Worktree path (e.g., `trees/abc123`)
- `$2`: Backend port (e.g., `9105`)
- `$3`: Frontend port (e.g., `9205`)

## Instructions

You are setting up an isolated worktree environment for agent parallelization.

### Step 1: Validate Arguments

Ensure all three arguments provided:

- Worktree path: `$1`
- Backend port: `$2`
- Frontend port: `$3`

If any missing, report what's needed.

### Step 2: Create Port Configuration

Create `.ports.env` file in the worktree:

```bash
BACKEND_PORT=$2
FRONTEND_PORT=$3
VITE_BACKEND_URL=http://localhost:$2
```

### Step 3: Copy Environment Files

Copy main environment file and append port overrides:

```bash
# Copy base .env
cp .env $1/.env

# Append port configuration
cat $1/.ports.env >> $1/.env
```

If there's a server-specific .env, do the same:

```bash
cp app/server/.env $1/app/server/.env
cat $1/.ports.env >> $1/app/server/.env
```

### Step 4: Update MCP Configuration

If `.mcp.json` exists, copy and update paths:

1. Copy `.mcp.json` to worktree
2. Update any paths to absolute paths for worktree
3. Copy any MCP-related configs (e.g., `playwright-mcp-config.json`)

### Step 5: Install Dependencies

Backend:

```bash
cd $1/app/server && uv sync --all-extras
```

Frontend:

```bash
cd $1/app/client && bun install
```

### Step 6: Initialize Database (if applicable)

If there's a database reset script:

```bash
cd $1 && ./scripts/reset_db.sh
```

### Step 7: Validate Installation

Run validation checks:

- [ ] Directory exists
- [ ] `.ports.env` created
- [ ] `.env` files configured
- [ ] Dependencies installed

## Output

Report installation status:

```json
{
  "success": true,
  "worktree_path": "$1",
  "backend_port": $2,
  "frontend_port": $3,
  "steps_completed": ["ports", "env", "deps", "db"]
}
```

## Notes

- Use deterministic port allocation: `slot = hash(adw_id) % 15`
- Backend ports: 9100-9114
- Frontend ports: 9200-9214
- Always use absolute paths in configurations
