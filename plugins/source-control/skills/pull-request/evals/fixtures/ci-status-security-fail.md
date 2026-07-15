# Fixture: CI + comment state on PR #161 (readiness check)

Captured `gh` command output for PR #161.

## `gh pr view 161 --json state,mergeable`

```json
{ "state": "OPEN", "mergeable": "MERGEABLE" }
```

## `gh pr checks 161`

```
build-test-format    pass       2m40s
markdown-lint        pass       28s
shell-lint           pass       44s
security-check       fail       19s
static-analysis       pass       3m11s
```

## Comments

- Review-thread comments: (none)
- Issue-level comments: (none)
- PR reviews: (none)

## `fetch-logs 161` (security-check annotations)

```
::error::security-check detected a potential secret at
src/config/tests/fixtures/example-settings.test.json:14
  rule: generic-api-key
```
