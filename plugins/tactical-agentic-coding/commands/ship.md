# Ship

Validate workflow state and merge to main for production deployment.

## Arguments

- `$1`: Branch name to merge

## Instructions

You are the ship command - the final step in Zero-Touch Engineering. Validate everything is ready, then merge to main.

### Step 1: Validate State Completeness

Before shipping, ALL these fields must be populated:

- [ ] `adw_id` - Workflow identifier
- [ ] `issue_number` - GitHub issue being resolved
- [ ] `branch_name` - Branch with changes
- [ ] `plan_file` - Implementation plan path
- [ ] `issue_class` - Task classification
- [ ] `worktree_path` - Isolated environment path (if using worktrees)

If any field is missing or empty, ABORT and report what's missing.

### Step 2: Validate Worktree (if applicable)

If using worktrees, perform three-way validation:

1. State has `worktree_path` field
2. Directory exists on filesystem
3. Git recognizes worktree (`git worktree list`)

If validation fails, ABORT and report the issue.

### Step 3: Validate Branch Exists

```bash
git branch --list $1
```markdown

If branch doesn't exist, ABORT.

### Step 4: Fetch Latest Main

```bash
git fetch origin
```markdown

### Step 5: Checkout Main

```bash
git checkout main
```markdown

### Step 6: Pull Latest

```bash
git pull origin main
```markdown

### Step 7: Merge Branch

Merge with no-fast-forward to preserve commit history:

```bash
git merge $1 --no-ff -m "Merge branch '$1' into main"
```markdown

If merge conflicts occur, ABORT and report conflicts.

### Step 8: Push to Origin

```bash
git push origin main
```markdown

### Step 9: Post Completion

Report successful ship:

```text
Shipped: Branch $1 merged to main and pushed to origin
```markdown

## Output

Return structured result:

```json
{
  "success": true,
  "branch": "$1",
  "merged_to": "main",
  "commit": "{merge_commit_hash}",
  "pushed": true
}
```text

Or on failure:

```json
{
  "success": false,
  "reason": "{failure_reason}",
  "step_failed": "{step_name}",
  "remediation": "{suggested_fix}"
}
```markdown

## Safety Gates

This command has multiple abort points:

1. **State validation** - Missing fields block merge
2. **Worktree validation** - Invalid environment blocks merge
3. **Branch validation** - Non-existent branch blocks merge
4. **Merge conflicts** - Conflicts block push

## Notes

- Ship happens in MAIN repository, not worktree
- Always fetch/pull before merge to avoid conflicts
- Use `--no-ff` to preserve full commit history
- This is the final step - validate EVERYTHING before executing
