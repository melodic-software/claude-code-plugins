# Out-of-Loop Deployment Checklist

Verify readiness before deploying AFK agents to production.

## Environment Checklist

### Dedicated Environment

- [ ] **Separate machine or VM** available for agent execution
- [ ] **Not your development machine** - agents run independently
- [ ] **Sufficient resources** - CPU, memory, disk for agent workloads
- [ ] **Stable network** - reliable connection to GitHub and APIs

### API Configuration

- [ ] **ANTHROPIC_API_KEY** configured and valid
- [ ] **GITHUB_TOKEN** or `gh auth login` completed
- [ ] **Optional: GITHUB_PAT** for alternate account access
- [ ] **Keys stored securely** - not in code, using env vars or secrets

### Repository Access

- [ ] **Repository cloned** to agent environment
- [ ] **Write access** to create branches and PRs
- [ ] **Webhook access** if using webhook triggers
- [ ] **Issue access** to read and comment on issues

### Claude Code Setup

- [ ] **Claude Code CLI installed** and accessible
- [ ] **CLAUDE_CODE_PATH** configured if non-standard location
- [ ] **Permissions configured** in `.claude/settings.json`
- [ ] **Templates tested** (/chore, /bug, /feature, /implement)

---

## Trigger Checklist

### For Webhook Triggers

- [ ] **Webhook server running** and healthy
- [ ] **Public endpoint reachable** (ngrok, Cloudflare tunnel, or public IP)
- [ ] **GitHub webhook configured** pointing to your endpoint
- [ ] **Webhook secret** configured for security
- [ ] **Event types selected**: Issues, Issue comments

### For Cron Triggers

- [ ] **Polling script running** (systemd, cron, or background process)
- [ ] **Polling interval configured** (e.g., every 20 seconds)
- [ ] **Issue detection logic** working (no comments, or "adw" comment)
- [ ] **Rate limiting considered** - don't hit GitHub API limits

### For Manual Triggers

- [ ] **CLI access** to agent environment
- [ ] **Commands documented** for team members
- [ ] **Quick start guide** available

---

## Workflow Checklist

### Template Testing

- [ ] **Chore template** generates valid plans
- [ ] **Bug template** generates valid plans with root cause analysis
- [ ] **Feature template** generates valid plans with implementation phases
- [ ] **Implement command** successfully executes plans

### Issue Classification

- [ ] **Classifier accuracy** tested on sample issues
- [ ] **Edge cases handled** (unclear issues, multi-type issues)
- [ ] **Fallback behavior** defined for unclassifiable issues

### Branch and Commit Patterns

- [ ] **Branch naming** follows convention: `{type}-{issue#}-{adw_id}-{slug}`
- [ ] **Commit messages** include agent attribution
- [ ] **No branch conflicts** - unique ADW IDs prevent collisions

### PR Creation

- [ ] **PR template** includes all required information
- [ ] **Issue linking** works correctly
- [ ] **Plan reference** included in PR body
- [ ] **Labels applied** if configured

---

## Observability Checklist

### Logging

- [ ] **Structured logging** configured (JSON or JSONL)
- [ ] **Log directory** exists and writable
- [ ] **Log rotation** configured for long-running agents
- [ ] **Error logs** captured separately for alerting

### Issue Comments

- [ ] **Progress comments** posted at each phase
- [ ] **ADW ID included** in all comments
- [ ] **Error comments** posted on failures
- [ ] **Final status** (success or failure) reported

### Monitoring

- [ ] **Health check endpoint** available
- [ ] **Alerting** configured for failures
- [ ] **Dashboard** for tracking ADW metrics (optional)

---

## Security Checklist

### Permissions

- [ ] **Minimal permissions** - only what's needed
- [ ] **No secrets in code** - all via environment variables
- [ ] **Webhook secret** validates incoming requests
- [ ] **Branch protection** - can't push directly to main

### Safety

- [ ] **Dangerous commands blocked** - no `rm -rf`, no force push
- [ ] **Environment isolation** - agent can't affect other systems
- [ ] **Rate limiting** - prevent runaway agents
- [ ] **Emergency stop** - way to halt all agents quickly

---

## Review Process Checklist

### PR Review Workflow

- [ ] **Reviewers assigned** automatically or manually
- [ ] **Review criteria** documented
- [ ] **Approval required** before merge
- [ ] **Tests must pass** before merge allowed

### Rollback Procedure

- [ ] **Revert process** documented
- [ ] **Rollback tested** - can you undo a bad merge?
- [ ] **Communication plan** for rollback notifications

### Zero Touch Engineering (Optional)

- [ ] **Comprehensive test suite** with high coverage
- [ ] **Auto-merge rules** configured
- [ ] **Monitoring for regressions** in place
- [ ] **Fast rollback** capability

---

## Go-Live Checklist

### Final Verification

- [ ] **Full workflow test** - issue to merged PR
- [ ] **Error handling** - verify graceful failure
- [ ] **Recovery** - can resume after failure?
- [ ] **Documentation** complete for operators

### Communication

- [ ] **Team notified** of AFK agent deployment
- [ ] **Runbook available** for common issues
- [ ] **Escalation path** defined
- [ ] **Success metrics** defined

---

## Quick Validation Commands

```bash
# Verify Claude Code
claude --version

# Verify GitHub access
gh auth status

# Test issue fetch
gh issue view 1 --json title,body

# Test webhook endpoint (if using)
curl -I https://your-webhook-endpoint/health

# Test classification
claude -p "/classify_issue 'Update dependencies to latest versions'"

# Test plan generation
claude -p "/chore update dependencies"
```yaml

---

## Related Memory Files

- @piter-framework.md - PITER element details
- @adw-anatomy.md - ADW structure and components
- @inloop-vs-outloop.md - When to use out-of-loop
