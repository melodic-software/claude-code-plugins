# Git Worktree Patterns for Agent Parallelization

## Why Worktrees?

Agents need isolated environments to execute simultaneously without interference. Git worktrees provide filesystem isolation while sharing the same repository.

## Benefits

| Benefit | Description |
| --------- | ------------- |
| **Isolation** | Each agent has its own working directory |
| **Parallelization** | Multiple agents execute simultaneously |
| **Clean state** | Fresh checkout from origin/main |
| **Port separation** | Each instance uses unique ports |
| **Easy cleanup** | Remove directory, remove worktree |

## Directory Structure

```text
repository_root/
├── trees/                    # All worktrees live here
│   ├── {adw_id_1}/          # Instance 1
│   │   ├── src/
│   │   ├── .ports.env       # Port configuration
│   │   └── ...
│   ├── {adw_id_2}/          # Instance 2
│   │   └── ...
│   └── ...                   # Up to 15 concurrent instances
├── agents/                   # State storage
│   ├── {adw_id_1}/
│   │   └── adw_state.json
│   └── {adw_id_2}/
│       └── adw_state.json
└── main codebase/           # Original repository
```markdown

## Port Allocation Strategy

### Deterministic Assignment

```text
Backend ports:  9100-9114 (15 slots)
Frontend ports: 9200-9214 (15 slots)

Formula: slot = hash(adw_id) % 15
Backend:  9100 + slot
Frontend: 9200 + slot
```markdown

### Why Deterministic?

- Same ADW ID always gets same ports
- Easy to debug specific instances
- No port collision tracking needed
- Predictable configuration

### Port Configuration File

Create `.ports.env` in worktree:

```bash
BACKEND_PORT=9105
FRONTEND_PORT=9205
VITE_BACKEND_URL=http://localhost:9105
```markdown

## Worktree Operations

### Create Worktree

```bash
# Fetch latest
git fetch origin

# Create worktree branching from origin/main
git worktree add trees/{adw_id} -b {branch_name} origin/main
```markdown

### Validate Worktree

Three-way validation:

1. State has worktree_path field
2. Directory exists on filesystem
3. Git knows about worktree (`git worktree list`)

### List Worktrees

```bash
git worktree list
```markdown

### Remove Worktree

```bash
# Remove the worktree reference
git worktree remove trees/{adw_id}

# Or force remove if there are changes
git worktree remove trees/{adw_id} --force
```markdown

### Cleanup All Stale Worktrees

```bash
# Prune worktrees that no longer exist on filesystem
git worktree prune
```markdown

## Setup Workflow

### Step 1: Create Worktree

```bash
git worktree add trees/{adw_id} -b {branch_name} origin/main
```markdown

### Step 2: Configure Ports

Create `trees/{adw_id}/.ports.env` with allocated ports.

### Step 3: Copy Environment

```bash
# Copy main .env
cp .env trees/{adw_id}/.env

# Append port overrides
cat trees/{adw_id}/.ports.env >> trees/{adw_id}/.env
```markdown

### Step 4: Update Paths

For any configuration that uses absolute paths (like MCP configs), update to worktree paths.

### Step 5: Install Dependencies

```bash
cd trees/{adw_id}
# Backend
cd app/server && uv sync --all-extras
# Frontend
cd app/client && bun install
```markdown

### Step 6: Initialize Database

```bash
cd trees/{adw_id}
./scripts/reset_db.sh
```markdown

## Parallelization Patterns

### Independent Execution

Each worktree is completely independent:

- Own filesystem state
- Own git branch
- Own ports
- Own dependencies

### Shared Repository

All worktrees share:

- Git object database
- Remote references
- Repository configuration

### Merge Strategy

Changes merge back from worktree to main repository:

1. Validate worktree work complete
2. Checkout main in main repo (NOT worktree)
3. Merge worktree branch
4. Push to origin

## Alternatives to Worktrees

| Alternative | Pros | Cons |
| ------------- | ------ | ------ |
| **Docker containers** | Full isolation, reproducible | More setup, resource heavy |
| **Virtual machines** | Complete isolation | Very resource heavy |
| **Separate clones** | Simple | Disk space, sync issues |
| **Git worktrees** | Lightweight, shared objects | Git expertise needed |

## Capacity Planning

With 15 concurrent instances:

- 15 backend ports (9100-9114)
- 15 frontend ports (9200-9214)
- 15 worktree directories
- 15 state files

For more capacity, extend port ranges or use dynamic allocation.

## Cross-References

- @zte-progression.md - ZTE requires parallel execution
- @adw-anatomy.md - ADW uses worktrees for isolation
- @outloop-checklist.md - Worktree setup checklist
