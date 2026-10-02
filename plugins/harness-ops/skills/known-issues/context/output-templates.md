# Output Templates

## Bug Report (for `search` action)

```markdown
### Bug Report: `<feature-name>`

**Search scope**: `anthropics/claude-code` (or specified repo)
**Issues found**: N open, M closed (recent)

#### Blocking Issues
(table)

#### Degraded Issues
(table)

#### Recently Fixed
(table)

#### Local Documentation Status
(table cross-referencing the consumer project's quirks/workarounds docs, when present)

### Recommendation

- **SAFE TO PROCEED**: No blocking issues found.
- **PROCEED WITH CAUTION**: Degraded issues exist. Use workarounds.
- **DO NOT USE**: Blocking bug(s) found. Alternative needed.

### Suggested Actions

- Add to registry: (issues not yet tracked)
- Add to the consumer project's quirks/workarounds doc: (issues not yet documented)
- Add to the work-item tracker: (monitoring items)
```
