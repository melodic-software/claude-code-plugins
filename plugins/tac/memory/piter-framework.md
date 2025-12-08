# PITER Framework

The four elements of AFK (Away From Keyboard) agents that enable out-of-loop autonomous development.

## What is PITER?

PITER is a framework for building autonomous agent systems that run without your direct involvement:

| Element | Purpose | Key Question |
| --------- | --------- | -------------- |
| **P** - Prompt Input | Source of work requests | Where do tasks come from? |
| **I** - (Implicit) | Issue classification | What type of work is this? |
| **T** - Trigger | What kicks off the workflow | When does work start? |
| **E** - Environment | Where agents run | Where do agents execute? |
| **R** - Review | Human oversight point | How is work validated? |

## P - Prompt Input

Your agents need a source of work. The prompt input is where tasks originate.

### GitHub Issues (Recommended)

```text
Issue Title + Issue Body = Agent Prompt

Title: "Add user authentication"
Body: "We need OAuth with Google and GitHub providers..."
```yaml

Benefits:

- Asynchronous - create from anywhere
- Structured - title, body, labels
- Trackable - comments, status
- Integrates with PR workflow

### Other Sources

| Source | Pros | Cons |
| -------- | ------ | ------ |
| Notion | Rich formatting, databases | Requires API integration |
| Slack | Real-time, conversational | Noisy, less structured |
| Email | Universal access | Parsing challenges |
| CLI | Direct control | Requires presence |

## I - (Implicit) Issue Classification

Before processing, classify the work type to route to the correct template:

```text
/classify_issue "Add OAuth authentication"
→ /feature

/classify_issue "Login form submits twice"
→ /bug

/classify_issue "Update dependencies to latest"
→ /chore
```markdown

Classification determines:

- Which template to use
- What plan structure to generate
- How thorough validation should be

## T - Trigger

What kicks off the agent workflow. Three main patterns:

### 1. Webhook (Real-Time)

```text
GitHub Issue Created
    ↓
Webhook POST to your server
    ↓
ADW workflow starts immediately
```yaml

Requires:

- Publicly reachable endpoint
- ngrok or Cloudflare tunnel for local dev
- Webhook secret for security

### 2. Cron (Polling)

```text
Every N seconds:
    ↓
Check for new/flagged issues
    ↓
Process if found
```yaml

Benefits:

- No public endpoint needed
- Simpler setup
- Works behind firewalls

Pattern: Poll GitHub every 20 seconds for issues with no comments OR latest comment = "adw"

### 3. Manual CLI

```bash
# Direct invocation
uv run adw_plan_build.py 123

# Or from Claude Code
claude -p "/implement specs/feature-auth.md"
```markdown

Best for:

- Testing workflows
- One-off tasks
- Debugging

## E - Environment

Your AFK agents need a dedicated environment to run:

### Isolation Requirements

```text
Development Machine    │    Agent Environment
                       │
Your IDE               │    Dedicated device
Your terminal          │    Isolated sandbox
Your context           │    Full permissions
                       │    Clean state
```markdown

### Why Dedicated Environment?

1. **Safety**: Agents can run with `--dangerously-skip-permissions`
2. **Isolation**: Won't interfere with your development
3. **Consistency**: Same environment every time
4. **Scalability**: Can run multiple ADWs in parallel

### Environment Checklist

- [ ] Separate machine or VM
- [ ] API keys configured
- [ ] Repository cloned
- [ ] Dependencies installed
- [ ] Permissions configured
- [ ] Health check passing

## R - Review

The human checkpoint before code ships:

### Pull Request Review (Recommended)

```text
ADW creates PR
    ↓
Human reviews changes
    ↓
Merge or request changes
```markdown

PR includes:

- Link to original issue
- Generated plan reference
- Implementation summary
- Diff of changes

### Zero Touch Engineering (ZTE)

For high-confidence workflows, skip review:

```text
ADW creates PR
    ↓
Auto-merge if tests pass
    ↓
Ship to production
```markdown

ZTE Requirements:

- Comprehensive test suite
- High-confidence templates
- Rollback automation
- Monitoring in place

See Lesson 7 for full ZTE implementation.

## PITER Flow

```text
P: Issue Created ──────────────────────┐
                                       │
I: Classify (chore/bug/feature) ───────┤
                                       │
T: Trigger (webhook/cron/manual) ──────┤
                                       │
E: Agent runs in dedicated env ────────┤
   │                                   │
   ├─→ Plan Phase (generate spec)      │
   │                                   │
   ├─→ Build Phase (implement)         │
   │                                   │
   └─→ PR Creation                     │
                                       │
R: Human reviews PR ───────────────────┘
   │
   └─→ Merge → Ship
```markdown

## Implementation Options Matrix

| Element | Simple | Intermediate | Advanced |
| --------- | -------- | -------------- | ---------- |
| **P** | Manual CLI | GitHub Issues | Multi-source integration |
| **I** | Manual classification | LLM classification | ML classifier |
| **T** | Manual CLI | Cron polling | Webhook real-time |
| **E** | Local sandbox | Dedicated VM | Cloud container |
| **R** | Always review | Review + auto-tests | ZTE auto-merge |

Start simple, add complexity as needed.

## Connection to Agentic KPIs

PITER enables the key KPI shifts:

| KPI | Direction | How PITER Helps |
| ----- | ----------- | ----------------- |
| **Presence** | DOWN (target: 1) | Out-of-loop execution |
| **Size** | UP | Automate entire features |
| **Streak** | UP | Consistent templated workflows |
| **Attempts** | DOWN | Well-defined problem classes |

## Related Memory Files

- @adw-anatomy.md - ADW structure and patterns
- @outloop-checklist.md - Deployment readiness checklist
- @inloop-vs-outloop.md - Architecture decision guide
