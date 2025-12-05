# Scaffold Layer

Create a minimum viable agentic layer structure for a project.

## Arguments

- `$ARGUMENTS`: Project name or target directory

## Instructions

You are scaffolding a minimum viable agentic layer for a project.

### Step 1: Create Directory Structure

```bash
mkdir -p specs
mkdir -p .claude/commands
mkdir -p adws/adw_modules
mkdir -p agents
```

### Step 2: Create Chore Template

Create `.claude/commands/chore.md`:

```markdown
# Chore Planning

Create a detailed implementation plan for this chore task.

## Task Description
$ARGUMENTS

## Instructions

1. Analyze the task requirements
2. Identify files to modify
3. Create step-by-step implementation plan
4. Define validation criteria

## Output

Create a spec file at: `specs/chore-{timestamp}-{name}.md`

Include:
- Task overview
- Files to modify
- Implementation steps
- Validation checklist
```

### Step 3: Create Implement Template

Create `.claude/commands/implement.md`:

```markdown
# Implementation

Implement the plan provided.

## Plan File
$ARGUMENTS

## Instructions

1. Read the plan file completely
2. Implement each step in order
3. Validate against criteria
4. Report changes

## Output

Report with:
- Changes made (git diff --stat)
- Validation results
- Any issues encountered
```

### Step 4: Create Agent Module Stub

Create `adws/adw_modules/__init__.py`:

```python
"""
ADW Modules - Core agent execution utilities.

To implement:
- agent.py: Claude Code subprocess execution
- data_types.py: Pydantic request/response models
"""
```

### Step 5: Create README

Create `adws/README.md`:

```markdown
# AI Developer Workflows

This directory contains the agentic layer for this project.

## Structure

- `adw_modules/`: Core execution modules
- `adw_*.py`: Workflow scripts

## Getting Started

1. Implement `adw_modules/agent.py` with Claude Code execution
2. Create gateway scripts (e.g., `adw_prompt.py`)
3. Build composed workflows (e.g., `adw_chore_implement.py`)

## Usage

Run workflows from project root:
```bash
python adws/adw_prompt.py "Your prompt here"
```

```

### Step 6: Report Structure

## Output

Report created structure:

```markdown
## Agentic Layer Scaffolded

**Project:** {name}
**Date:** {today}

### Created Directories
- specs/
- .claude/commands/
- adws/adw_modules/
- agents/

### Created Files
- .claude/commands/chore.md
- .claude/commands/implement.md
- adws/adw_modules/__init__.py
- adws/README.md

### Next Steps
1. Implement `adws/adw_modules/agent.py`:
   - Claude Code subprocess execution
   - Request/response data models
   - Output file handling

2. Create gateway script `adws/adw_prompt.py`:
   - CLI interface with click
   - Unique ID generation
   - Rich console output

3. Create composed workflow `adws/adw_chore_implement.py`:
   - Execute /chore to generate plan
   - Execute /implement with plan

### Time to Production
Estimated 5-8 hours to complete MVP
```

## Notes

- This creates the bare minimum structure
- Next step is implementing agent.py execution module
- See @minimum-viable-agentic skill for full implementation guide
