# Lesson 7 Analysis: ZTE - The Secret of Agentic Engineering

## Content Summary

### Core Tactic

**Target Zero-Touch Engineering** - Zero-Touch Engineering is the third level of agentic coding where your presence KPI drops from two touchpoints (prompt and review) to just one (prompt only). Build systems so reliable that human review becomes a bottleneck, not a safety net.

### Key Frameworks

#### Three Levels of Agentic Coding

| Level | Description | Presence KPI |
| ----- | ----------- | ------------ |
| **In-Loop** | Interactive prompting, back-and-forth with agent | High (constant) |
| **Out-Loop** | AFK agents, PITER framework, trigger-based | Medium (prompt + review) |
| **Zero-Touch** | Codebase ships itself, automated end-to-end | Low (prompt only) |

#### ZTE Workflow: Plan -> Build -> Test -> Review -> Generate -> Ship

The complete Zero-Touch Engineering workflow:

1. **Plan** the feature (isolated)
2. **Build** the implementation (isolated)
3. **Test** functionality (isolated)
4. **Review** quality (isolated)
5. **Document** (generate) documentation (isolated)
6. **Ship** to production (approve & merge PR)

#### The Secret of Tactical Agentic Coding

> "The secret of tactical agentic coding is that it's not about the software developer lifecycle at all. It's about composable agentic primitives you can use to solve any engineering problem class."

Key insight: The SDLC is just one composition of primitives. Different organizations will have unique primitive compositions.

### Implementation Patterns from Repo (tac-7)

**ZTE Workflow** (`adw_sdlc_zte_iso.py`):

```python
# Complete SDLC with automatic shipping
# 1. adw_plan_iso.py - Planning phase (isolated)
# 2. adw_build_iso.py - Implementation phase (isolated)
# 3. adw_test_iso.py - Testing phase (isolated)
# 4. adw_review_iso.py - Review phase (isolated)
# 5. adw_document_iso.py - Documentation phase (isolated)
# 6. adw_ship_iso.py - Ship phase (approve & merge PR)
```yaml

**Ship Workflow** (`adw_ship_iso.py`):

- Validates all state fields are populated
- Validates worktree exists
- Performs manual git merge to main
- Posts success message and closes issue

**Git Worktrees for Parallelization**:

- Each ADW runs in isolated worktree: `trees/<adw_id>/`
- Supports 15 concurrent instances
- Dedicated port ranges:
  - Backend: 9100-9114
  - Frontend: 9200-9214
- Complete filesystem isolation

**Install Worktree Command** (`/install_worktree`):

- Sets up isolated worktree environment
- Creates `.ports.env` with custom ports
- Copies and updates MCP configuration files
- Installs dependencies in isolation

**Model Set Pattern** (Heavy vs Base):

```python
# agents.py maps commands to model sets
AGENT_PLANNER = "sdlc_planner"  # Uses heavy model for complex reasoning
AGENT_IMPLEMENTOR = "sdlc_implementor"  # Uses heavy model
# heavy models = Opus for critical work
# base models = Sonnet for standard work
```yaml

**KPI Tracking Command** (`/track_agentic_kpis`):

- Updates `app_docs/agentic_kpis.md`
- Tracks: Current Streak, Longest Streak, Total Plan Size
- Calculates: Attempts, Plan Size, Diff Statistics

**State Management Across Workflows**:

```python
class ADWState:
    adw_id: str
    issue_number: str
    branch_name: str
    plan_file: str
    issue_class: str
    worktree_path: str
    backend_port: int
    frontend_port: int
    all_adws: list  # Track all workflows run
```markdown

### Anti-Patterns Identified

- **Staying In-Loop**: Constant prompting back and forth wastes time
- **Manual review bottleneck**: When review adds no value, it slows things down
- **Single agent environment**: Not parallelizing across multiple worktrees
- **Rejecting future ideas**: Not believing ZTE is possible prevents progress
- **All-or-nothing thinking**: Not progressing incrementally toward Out-Loop/ZTE

### Metrics/KPIs

ZTE is the culmination of all KPIs:

- **Attempts: 1** - Single attempt success
- **Size: UP** - Constantly scaling up
- **Streak: UP** - Consecutive successes increasing
- **Presence: 1** - Only the prompt, no review

## Extracted Components

### Skills

| Name | Purpose | Keywords |
| ---- | ------- | -------- |
| `zte-progression` | Guide progression from In-Loop to ZTE | ZTE, zero touch, out loop, presence |
| `git-worktree-setup` | Set up Git worktrees for agent parallelization | worktree, isolation, parallel, concurrent |
| `agentic-kpi-tracking` | Track and measure agentic coding KPIs | KPI, streak, attempts, presence, size |
| `composable-primitives` | Design composable agentic primitives | primitives, compose, SDLC, workflow |

### Subagents

| Name | Purpose | Tools |
| ---- | ------- | ----- |
| `shipper` | Validate state and merge to main | Read, Bash (git) |
| `worktree-installer` | Set up isolated worktree environments | Read, Write, Bash |
| `kpi-tracker` | Calculate and update agentic KPIs | Read, Write, Bash |

### Commands

| Name | Purpose | Arguments |
| ---- | ------- | --------- |
| `/install_worktree` | Set up isolated worktree environment | `$1` worktree_path, `$2` backend_port, `$3` frontend_port |
| `/track_agentic_kpis` | Update KPI tracking tables | `$ARGUMENTS` - state JSON |
| `/cleanup_worktrees` | Clean up stale worktrees | None |
| `/in_loop_review` | Human-in-loop review for validation | `$1` branch |

### Memory Files

| Name | Purpose | Load Condition |
| ---- | ------- | -------------- |
| `zte-progression.md` | Three levels of agentic coding | When discussing scale/velocity |
| `git-worktree-patterns.md` | Worktree setup and isolation | When parallelizing agents |
| `composable-primitives.md` | The secret of agentic coding | When designing workflows |
| `belief-change-required.md` | The mindset shift required for ZTE | When introducing ZTE concept |

## Key Insights for Plugin Development

### High-Value Components from Lesson 7

1. **Memory File: `zte-progression.md`**
   - Three levels: In-Loop -> Out-Loop -> ZTE
   - Presence KPI targets for each level
   - Progression path: chores -> bugs -> features

2. **Memory File: `composable-primitives.md`**
   - The "secret" of TAC
   - Not about SDLC, about primitives
   - Each organization has unique compositions

3. **Skill: `git-worktree-setup`**
   - Enable parallel agent execution
   - Port allocation strategies
   - Filesystem isolation patterns

4. **Command: `/track_agentic_kpis`**
   - Measure progress toward ZTE
   - Calculate streaks, attempts, presence
   - Track improvement over time

### ZTE Progression Path

```text
Start Small:
1. Ship chores with ZTE (simple, low risk)
2. Ship bugs with ZTE (more complex)
3. Ship features with ZTE (full automation)

Build Confidence:
- First 5 successful ZTE runs
- Then 20 successful runs
- Then 5 in a row with zero failures
- Then you realize: "I add no value by reviewing"

Decision Point:
- When human review becomes bottleneck
- When confidence hits 90%+
- When review catches nothing
- THEN: Enable ZTE for that problem class
```markdown

### Worktree Architecture

```text
Repository Root/
├── trees/
│   ├── a1b2c3d4/    # ADW instance 1 (ports 9100/9200)
│   ├── e5f6g7h8/    # ADW instance 2 (ports 9101/9201)
│   └── ...          # Up to 15 concurrent instances
├── agents/
│   ├── a1b2c3d4/
│   │   └── adw_state.json  # Persistent state
│   └── e5f6g7h8/
│       └── adw_state.json
└── adws/
├── adw_plan_iso.py
├── adw_build_iso.py
├── adw_test_iso.py
├── adw_review_iso.py
├── adw_document_iso.py
├── adw_ship_iso.py
├── adw_sdlc_iso.py       # Complete SDLC
└── adw_sdlc_zte_iso.py   # ZTE (auto-ship)
```markdown

### Key Quotes
>
> "Zero-Touch Engineering is YOLO mode for your AI developer workflows. This is high confidence mode for agentic engineering. Maximum confidence mode. No review."
>
> "Progress happens one step at a time, one day at a time. First, go after chores, then go after bugs, then go after features."
>
> "The best Outloop agent coders have a presence of two. You show up at the prompt and you show up at the review. In the future, you'll realize that you're wasting time reviewing."
>
> "The real secret is that it's about the composable units, the agentic primitives, all the way down to the prompt level."
>
> "If you don't believe that your agents can run your codebase, you're cooked."
>
> "The real challenge of tactical agentic coding is about your belief. You have to believe that the agentic layer is worth investing into."

### Ship Workflow Pattern

```python
def ship_workflow():
    # 1. Validate ALL state fields have values
    validate_state_completeness(state)

    # 2. Validate worktree exists
    validate_worktree(adw_id, state)

    # 3. Manual merge to main
    git_fetch_origin()
    git_checkout_main()
    git_pull_origin_main()
    git_merge_branch(branch_name, no_ff=True)
    git_push_origin_main()

    # 4. Post success and close issue
    make_issue_comment("Code shipped to production!")
```markdown

### Isolated Port Allocation

```python
# Port ranges for 15 concurrent instances
BACKEND_PORT_START = 9100   # 9100-9114
FRONTEND_PORT_START = 9200  # 9200-9214

# Deterministic port allocation from ADW ID
def allocate_ports(adw_id: str) -> tuple[int, int]:
    # Hash adw_id to get consistent slot (0-14)
    slot = hash(adw_id) % 15
    return (BACKEND_PORT_START + slot, FRONTEND_PORT_START + slot)
```markdown

## Validation Checklist

- [x] Read video.md (metadata)
- [x] Read lesson.md (structured summary)
- [x] Read captions.txt (full transcript - 53:22 of content!)
- [x] Explored tac-7 repository structure
- [x] Read adws/adw_sdlc_zte_iso.py (ZTE workflow)
- [x] Read adws/adw_ship_iso.py (ship/merge workflow)
- [x] Read .claude/commands/install_worktree.md
- [x] Read .claude/commands/track_agentic_kpis.md
- [x] Read adws/README.md (comprehensive documentation)
- [x] Identified worktree isolation pattern
- [x] Understood state management across workflows
- [x] Validated against official docs (2025-12-04) - See DOCUMENTATION_AUDIT.md

## Cross-Lesson Dependencies

- **Builds on Lesson 1**: Stop coding - now stop reviewing too
- **Builds on Lesson 2**: KPIs lead to ZTE (Presence -> 1)
- **Builds on Lesson 3**: Templates enable consistent automation
- **Builds on Lesson 4**: PITER framework -> PITE (drop Review)
- **Builds on Lesson 5**: Tests enable confidence for ZTE
- **Builds on Lesson 6**: Specialized agents execute each step
- **Sets up Lesson 8**: The Agentic Layer complete picture

## Notable Implementation Details

### Model Set Configuration

```python
# agents.py - Model selection by workflow step
MODEL_SETS = {
    "base": {
        "/chore": "sonnet",
        "/bug": "sonnet",
        "/feature": "sonnet",
        "/implement": "sonnet",
    },
    "heavy": {
        "/chore": "opus",
        "/bug": "opus",
        "/feature": "opus",
        "/implement": "opus",
    }
}

# Pass model_set in issue body
# "ADW: SDLC ISO model_set: heavy"
```markdown

### ZTE Safety Gates

```python
# In adw_sdlc_zte_iso.py
if test.returncode != 0:
    make_issue_comment("ZTE Aborted - Test phase failed")
    sys.exit(1)  # Stop before shipping

if review.returncode != 0:
    make_issue_comment("ZTE Aborted - Review phase failed")
    sys.exit(1)  # Stop before shipping

# Documentation failure doesn't block shipping
if document.returncode != 0:
    print("WARNING: Documentation failed but continuing with shipping")
```markdown

### ADW Module Architecture

```text
adw_modules/
├── __init__.py
├── agent.py         # Claude Code execution
├── data_types.py    # Pydantic models
├── git_ops.py       # Git operations
├── github.py        # GitHub API
├── r2_uploader.py   # Screenshot upload
├── state.py         # ADWState management
├── utils.py         # Logging, env vars
├── workflow_ops.py  # Workflow operations
└── worktree_ops.py  # Worktree management
```yaml

---

**Analysis Date:** 2025-12-04
**Analyzed By:** Claude Code (claude-opus-4-5-20251101)
