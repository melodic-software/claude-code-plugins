# audit-pass suppressions

Deliberately kept findings from `/claude-config:audit` and `/claude-config:audit-pass`, keyed by
`finding_id` per the marketplace's finding-suppression convention. Entries are derived by the audit
engine (`audit-engine.sh --table` prints a paste-ready `suppress:` line per finding); the
constituents below are authoritative and the key is their hash.

```yaml
suppressions:
  fce618a146f90b9c:
    check: claude-config/audit/B/baseline-ask-rules
    claim: "missing-pattern:Bash(git push *)"
    sites:
      - surface: .claude/settings.json
        anchor/v1: "e:b40d4d51d2c2:6e340b9c"
    reason: "Cloud sessions on this repository push to the task branch as part of the harness contract; an ask-gate on git push would prompt on every run and is never answered. Local operators keep whatever ask rule they want in their user settings."
    date: 2026-09-08
  52bccf5cafa7fd59:
    check: claude-config/audit/B/baseline-ask-rules
    claim: "missing-pattern:Bash(git push)"
    sites:
      - surface: .claude/settings.json
        anchor/v1: "e:b40d4d51d2c2:6e340b9c"
    reason: "Same posture as the argument-bearing form: the harness mandates the push in cloud sessions."
    date: 2026-09-08
```
