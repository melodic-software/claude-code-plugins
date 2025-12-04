# Lesson 6 Analysis: Let Your Agents Focus - Agentic Review and Documentation

## Content Summary

### Core Tactic

**One Agent, One Prompt, One Purpose** - Specialized agents with focused prompts to achieve a single purpose well. This frees up the context window, lets agents focus on what matters most, and creates reproducible, improvable prompts you can commit to your codebase.

### Key Frameworks

#### SDLC as Questions and Answers

| Step | Question | Purpose |
| ---- | -------- | ------- |
| **Plan** | "What are we building?" | Define requirements |
| **Build** | "Did we make it real?" | Implement solution |
| **Test** | "Does it work?" | Validate functionality |
| **Review** | "Is what we built what we planned?" | Validate alignment |
| **Document** | "How does it work?" | Create reference for future |

#### Review vs Testing - Critical Distinction

| Aspect | Testing | Review |
| ------ | ------- | ------ |
| **Question** | Does it work? | Is what we built what we asked for? |
| **Focus** | Functionality | Alignment with spec |
| **Validation** | Code execution | Spec comparison |
| **Asset** | Test results | Screenshots, proof artifacts |

#### Three Constraints of Agentic Engineers

1. **Context window** - Limited tokens available
2. **Codebase complexity** - Problem difficulty
3. **Our abilities** - Skill and expertise

Specialized agents bypass TWO of these constraints (context window and abilities).

### The Minimum Context Principle

> "You want to context engineer as little as possible. You want the minimum context in your prompt required to solve the problem. Every piece of context you add increases the number of variables your agent has to reason about."

### Implementation Patterns from Repo (tac-6)

1. **Review Workflow** (`/review`):
   - Find spec from current branch
   - Review implementation against spec
   - Capture screenshots of critical functionality
   - Report success or blocking issues
   - If blockers exist, run patch workflow to fix

2. **Patch Workflow** (`/patch`):

   ```markdown
   # Create a Focused Patch Plan
   Resolve a specific issue with minimal targeted changes.

   ## Instructions
   Follow the instructions to create a concise plan to address the issue.
   ```

3. **Document Workflow** (`/document`):
   - Generate concise markdown documentation
   - Create documentation in `app/docs/`
   - Update conditional documentation for future agents

4. **Conditional Documentation** - The key innovation:

   ```markdown
   # Conditional Documentation
   This prompt helps you determine what documentation you should read based on
   specific changes you need to make in the codebase.

   ## When working on export features
   Read: app/docs/export-features.md

   ## When working on query system
   Read: app/docs/query-system.md
   ```

5. **Issue Severity Classification**:

   ```python
   class ReviewIssue(BaseModel):
       severity: Literal["skippable", "tech_debt", "blocker"]
       description: str
       # Only block on "blocker" severity
   ```

6. **Proof of Value Pattern** - Screenshots uploaded to R2/S3:
   - Review captures screenshots
   - Uploads to public bucket
   - Attaches to GitHub issue/PR
   - Human can verify at a glance

### Anti-Patterns Identified

- **Context pollution/overloading**: Massive context windows lead to distracted, confused agents
- **God model thinking**: Expecting one agent to do everything
- **Skipping test step**: Review alone is not enough (caught visual bug, but tests would have too)
- **In-loop babysitting**: Doing work agents could do autonomously
- **Manual documentation**: Letting documentation become stale

### Metrics/KPIs

From the lesson's concrete example:

- **Attempts**: Target 1 (achieved 2 due to patch)
- **Size**: Good (full export feature shipped)
- **Streak**: Broken (reset to 1 due to patch)
- **Presence**: ~3 (prompt, review, patch confirmation)

Optimal presence: 2 (prompt input + final review/merge)

## Extracted Components

### Skills

| Name | Purpose | Keywords |
| ---- | ------- | -------- |
| `agent-specialization` | Guide creation of focused agents | specialized, focus, one purpose, context |
| `review-workflow-design` | Design review workflows with proof | review, screenshot, spec, alignment |
| `conditional-docs` | Set up conditional documentation | documentation, conditional, context, when |
| `patch-design` | Create surgical patch workflows | patch, fix, minimal, targeted |

### Subagents

| Name | Purpose | Tools |
| ---- | ------- | ----- |
| `spec-reviewer` | Review implementation against spec | Read, Bash, MCP (Playwright) |
| `patch-planner` | Create minimal patch plans | Read, Write, Glob |
| `patch-implementer` | Execute patch plans | Read, Write, Edit, Bash |
| `documentation-generator` | Generate and update docs | Read, Write, Glob, Grep |
| `conditional-docs-updater` | Update conditional documentation | Read, Edit |

### Commands

| Name | Purpose | Arguments |
| ---- | ------- | --------- |
| `/review` | Review implementation against spec | `$1` spec file, `$2` adw_id, `$3` agent_name |
| `/patch` | Create minimal targeted fix | `$ARGUMENTS` - issue description |
| `/document` | Generate feature documentation | `$1` adw_id, `$2` agent_name |
| `/conditional_docs` | Load relevant documentation | Context-dependent |

### Memory Files

| Name | Purpose | Load Condition |
| ---- | ------- | -------------- |
| `one-agent-one-purpose.md` | Agent specialization principles | When designing agents |
| `review-vs-test.md` | Distinction between test and review | When setting up validation |
| `minimum-context-principle.md` | Context engineering guidance | When writing prompts |
| `conditional-docs-pattern.md` | How to set up conditional loading | When creating documentation |
| `proof-of-value.md` | Screenshot/artifact patterns for review | When implementing review |

## Key Insights for Plugin Development

### High-Value Components from Lesson 6

1. **Memory File: `one-agent-one-purpose.md`**
   - Benefits of specialization
   - Context window freedom
   - Eval creation side effect
   - Commit and improve pattern

2. **Memory File: `minimum-context-principle.md`**
   - Why less context is better
   - Variables increase reasoning complexity
   - Adopt agent's perspective

3. **Conditional Documentation Pattern**
   - Include in bug/feature/chore templates
   - Automatic documentation updates
   - Future agent awareness

4. **Review Workflow with Proof**
   - Screenshot capture pattern
   - R2/S3 upload for public URLs
   - Issue/PR attachment

### Agent Architecture Guidance

Agents should be:

- **Isolated**: One prompt per agent run
- **Focused**: Single purpose
- **Improvable**: Committed to codebase
- **Evaluatable**: Can rerun with different models

### Conditional Docs Integration

Where conditional docs should be referenced:

```markdown
## Relevant Files
- Read `.claude/commands/conditional_docs.md` to check if your task requires
  additional documentation. If your task matches any conditions listed,
  include those documentation files.
```

### Key Quotes

> "Context pollution, context overloading, toxic context - whatever you call it, when you overload the context window, your agent has a harder time focusing on what matters most."
>
> "The whole point here is that we are putting in the effort to build the system that builds the system."
>
> "Review answers the critical question: Is what we built what we asked for?"
>
> "A focused engineer working on a single task is a productive engineer. Agents are the same."
>
> "By using individualized agents with specific prompts for one purpose, you effectively create evals for the agentic layer of your codebase."
>
> "Model intelligence is not a constraint. Don't use this as an excuse. It will set you back. This is a losing mindset."

### ADW Composition Pattern

```text
adw_plan.py          (Plan step)
adw_build.py         (Build step)
adw_test.py          (Test step)
adw_review.py        (Review step)
adw_document.py      (Document step)
adw_patch.py         (Fix issues)

Compositions:
adw_plan_build.py           (Plan + Build)
adw_plan_build_test.py      (Plan + Build + Test)
adw_plan_build_review.py    (Plan + Build + Review)
adw_plan_build_test_review.py  (Full minus docs)
adw_plan_build_document.py  (Plan + Build + Document)
```

## Validation Checklist

- [x] Read video.md (metadata)
- [x] Read lesson.md (structured summary)
- [x] Read captions.txt (full transcript - 57:17 of content!)
- [x] Identified tac-6 repository patterns
- [x] Understood review workflow structure
- [x] Understood documentation workflow structure
- [x] Understood conditional documentation pattern
- [x] Understood patch workflow for fixes
- [x] Explored full tac-6 repository (fourth pass - 2025-12-04)
- [x] Validated against official docs (2025-12-04) - See DOCUMENTATION_AUDIT.md

## Cross-Lesson Dependencies

- **Builds on Lesson 3**: Meta-prompts for review and document
- **Builds on Lesson 4**: PITER framework for out-loop review
- **Builds on Lesson 5**: Testing step distinction from review
- **Sets up Lesson 7**: ZTE (Zero Touch Engineering) secret
- **Sets up Lesson 8**: The Agentic Layer complete picture

## Notable Implementation Details

### Review Image Upload Pattern

```python
# Initialize R2 uploader for public image hosting
r2_uploader = R2Uploader(
    bucket_name="review-screenshots",
    public_url="https://cdn.example.com"
)

# Upload screenshot and get public URL
public_url = r2_uploader.upload(screenshot_path)

# Attach to GitHub issue
make_issue_comment(issue_number, f"![Review Screenshot]({public_url})")
```

### State Management Across ADWs

```python
class ADWState(BaseModel):
    adw_id: str
    branch_name: str
    plan_file: str
    issue_class: str
    issue_number: str
    # Persisted to agents/<adw_id>/state.json
```

State enables chaining: Plan -> Build -> Test -> Review -> Document

### Issue Severity Filtering

```python
# Only resolve blocking issues, not tech debt or skippable
blocking_issues = [i for i in review.issues if i.severity == "blocker"]
for issue in blocking_issues:
    create_and_implement_patch(issue)
```

---

## Full tac-6 Repository Exploration (Fourth Pass)

### Complete Slash Command Inventory (23 Commands)

| Category | Command | Purpose |
| -------- | ------- | ------- |
| **Planning** | `/bug` | Bug fix planning with root cause analysis |
| | `/chore` | Maintenance/refactoring task planning |
| | `/feature` | Feature planning with user story format |
| **Classification** | `/classify_issue` | Routes issues to `/chore`, `/bug`, `/feature`, `/patch` |
| | `/classify_adw` | Extracts ADW workflow commands from text |
| **Implementation** | `/implement` | Executes a generated plan |
| | `/patch` | Creates minimal targeted patch plans |
| **Testing** | `/test` | Full test suite (syntax, lint, pytest, TS, build) |
| | `/test_e2e` | Playwright E2E tests with screenshots |
| | `/resolve_failed_test` | Fixes specific failing unit tests |
| | `/resolve_failed_e2e_test` | Fixes specific failing E2E tests |
| **Review/Docs** | `/review` | Reviews implementation against spec with screenshots |
| | `/document` | Generates markdown docs in `app_docs/` |
| | `/conditional_docs` | Maps documentation to task conditions |
| **Git/Workflow** | `/commit` | Semantic commits: `{agent}: {class}: {msg}` |
| | `/pull_request` | Creates PR with summary and checklist |
| | `/generate_branch_name` | `{type}-{issue}-{adw_id}-{slug}` format |
| **Setup** | `/install` | Backend (uv) + frontend (bun) setup |
| | `/start` | Starts backend and frontend services |
| | `/prepare_app` | Resets DB, starts servers for review |
| **Utility** | `/tools` | Lists available tools |
| | `/prime` | Initialization utility |

### Complete ADW Script Inventory

**Single-Phase Scripts:**

- `adw_plan.py` - Planning phase only
- `adw_build.py` - Implementation phase only
- `adw_test.py` - Testing phase only
- `adw_review.py` - Review phase only (26,957 bytes)
- `adw_document.py` - Documentation phase only
- `adw_patch.py` - Direct patching workflow

**Orchestrator Scripts (Compositions):**

- `adw_plan_build.py` - Plan + Build
- `adw_plan_build_test.py` - Plan + Build + Test
- `adw_plan_build_review.py` - Plan + Build + Review (skip test)
- `adw_plan_build_document.py` - Plan + Build + Document (skip test/review)
- `adw_plan_build_test_review.py` - Plan + Build + Test + Review
- `adw_sdlc.py` - Complete: Plan + Build + Test + Review + Document

**ADW Modules (`adw_modules/`):**

- `agent.py` - Claude Code CLI integration
- `data_types.py` - Pydantic models
- `github.py` - GitHub API operations
- `git_ops.py` - Git operations
- `state.py` - State management
- `workflow_ops.py` - Core business logic
- `utils.py` - Utilities
- `r2_uploader.py` - Cloud storage integration

**Triggers (`adw_triggers/`):**

- `trigger_cron.py` - Polls GitHub every 20 seconds
- `trigger_webhook.py` - Webhook server on port 8001

### adw_review.py Deep Dive

**Workflow Phases:**

1. **State Loading** - Loads `agents/{adw_id}/adw_state.json`
2. **Spec Retrieval** - Finds spec file from git branch
3. **Screenshot Capture** - 1-5 critical path screenshots
4. **R2 Upload** - Screenshots to cloud storage
5. **Review Execution** - `/review` command with JSON output
6. **Blocker Resolution Loop** (up to 3 attempts):
   - Filters to `blocker` severity only
   - Creates patch plans via `/patch`
   - Implements patches
   - Re-reviews to validate
7. **GitHub Comment** - Posts review with severity-grouped issues
8. **Finalization** - Commits, pushes, updates PR

**Review Issue Severity:**

- `blocker` - Prevents release, auto-resolved
- `tech_debt` - Non-blocking, documented
- `skippable` - Polish items, ignored

### adw_document.py Deep Dive

**Documentation Structure Generated:**

```markdown
# Feature: {adw_id} - {name}
## Overview
## Screenshots
## What Was Built
## Technical Implementation
## How to Use
## Configuration
## Testing
## Notes
```

**Asset Management:**

- Creates `app_docs/assets/` directory
- Copies screenshots from review phase
- Uses relative paths in documentation
- Updates `conditional_docs.md` with new entry

### Settings Configuration

**Permissions (`.claude/settings.json`):**

- `allow`: mkdir, uv, find, mv, grep, npm, ls, cp, Write, chmod, touch, scripts
- `deny`: git push --force, rm -rf

**Hooks (7 total):**

1. PreToolUse - `pre_tool_use.py`
2. PostToolUse - `post_tool_use.py`
3. Notification - `notification.py`
4. Stop - `stop.py`
5. SubagentStop - `subagent_stop.py`
6. PreCompact - `pre_compact.py`
7. UserPromptSubmit - `user_prompt_submit.py`

### Key Patterns Discovered

**ADW ID Tracking:**

- 8-character unique identifier
- Appears in: comments, file paths, commits, PRs
- Enables workflow resumption and debugging

**State-Based Chaining:**

```json
{
  "adw_id": "abc12345",
  "issue_number": "123",
  "branch_name": "feat-123-abc12345-feature-name",
  "plan_file": "specs/issue-123-adw-abc12345-sdlc_planner-feature.md",
  "issue_class": "/feature",
  "review_screenshots": ["url1", "url2"]
}
```

**Blocker Auto-Resolution:**

- Review identifies blockers
- Creates targeted patch plans
- Auto-implements patches
- Re-reviews to validate
- Retries up to 3 times

---

**Analysis Date:** 2025-12-04
**Analyzed By:** Claude Code (claude-opus-4-5-20251101)
**Fourth Pass:** 2025-12-04 - Full tac-6 repository exploration completed
