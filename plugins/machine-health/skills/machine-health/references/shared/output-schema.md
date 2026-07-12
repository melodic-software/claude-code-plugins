# Output schema

This skill emits structured JSON at three levels. The schemas below are normative — every check script, every remediation script, and the orchestrator must produce output validating against them. Keeping the schema stable across OSes is the reason `references/shared/` exists.

## 1. Check result

Emitted by `scripts/<os>/checks/Test-*.ps1`. Exactly one JSON object per invocation, written to stdout unless `-Human` is set.

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "CheckResult",
  "type": "object",
  "required": [
    "id", "category", "os", "ran_at", "severity", "summary",
    "needs_admin", "ran_successfully", "duration_ms"
  ],
  "properties": {
    "id":               { "type": "string", "description": "Catalog identifier, e.g., 'disk-space'." },
    "category":         { "type": "string", "description": "High-level grouping for the report, e.g., 'storage', 'security'." },
    "os":               { "type": "string", "enum": ["windows", "macos", "linux"] },
    "ran_at":           { "type": "string", "format": "date-time", "description": "ISO 8601 with offset." },
    "severity":         { "type": "string", "enum": ["OK", "INFO", "WARN", "CRIT", "UNKNOWN"] },
    "summary":          { "type": "string", "description": "One-line human summary." },
    "detail":           { "type": "object", "description": "Free-form structured data specific to the check." },
    "commands":         { "type": "array", "items": { "type": "string" }, "description": "Reproduction commands the human can run." },
    "needs_admin":      { "type": "boolean" },
    "ran_successfully": { "type": "boolean", "description": "False when the check returned UNKNOWN due to error/timeout." },
    "duration_ms":      { "type": "integer", "minimum": 0 },
    "trend":            { "type": ["object", "null"], "additionalProperties": false, "properties": {
                             "last_run":      { "type": ["string", "null"], "description": "run_id of the run this check last ran in." },
                             "delta":         { "type": ["string", "null"] },
                             "adjusted_from": { "type": ["string", "null"], "description": "Pre-adjustment severity when a trend rule changed it." }
                         }},
    "notes":            { "type": "string", "description": "Optional. Reason for severity adjustment, caveats, etc." },
    "error":            { "type": ["string", "null"], "description": "Populated when ran_successfully is false." }
  }
}
```

### Example (Windows disk-space WARN with trend)

```json
{
  "id": "disk-space",
  "category": "storage",
  "os": "windows",
  "ran_at": "2026-04-27T09:00:12-04:00",
  "severity": "WARN",
  "summary": "C: at 87% used (13% free)",
  "detail": {
    "volumes": [
      { "drive": "C:", "used_pct": 87, "free_gb": 59.4, "size_gb": 475.8, "filesystem": "NTFS" }
    ]
  },
  "commands": [
    "Get-Volume | Where-Object DriveType -eq 'Fixed'"
  ],
  "needs_admin": false,
  "ran_successfully": true,
  "duration_ms": 412,
  "trend": { "last_run": "2026-04-20T09:00:00-04:00", "delta": "used_pct: +8 vs prior", "adjusted_from": null },
  "notes": "Crossed 85% threshold this week."
}
```

## 2. Run snapshot (`state/latest.json`)

Emitted by the orchestrator at the end of every run. Overwrites the previous snapshot.

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "RunSnapshot",
  "type": "object",
  "required": [
    "run_id", "hostname", "os", "os_version", "elevated",
    "run_mode", "checks", "remediations", "discovered_checks", "duration_seconds"
  ],
  "properties": {
    "run_id":            { "type": "string", "format": "date-time" },
    "hostname":          { "type": "string" },
    "os":                { "type": "string", "enum": ["windows", "macos", "linux"] },
    "os_version":        { "type": "string" },
    "elevated":          { "type": "boolean" },
    "run_mode":          { "type": "string", "enum": ["weekly", "on-demand", "first-run"] },
    "dry_run":           { "type": "boolean" },
    "powershell_version": { "type": "string" },
    "checks":            { "type": "array", "items": { "$ref": "#/definitions/CheckResult" } },
    "remediations":      { "type": "array", "items": { "$ref": "#/definitions/RemediationAttempt" } },
    "discovered_checks": { "type": "array", "items": { "type": "object" } },
    "urls_called":       { "type": "array", "items": { "type": "string" }, "description": "Egress allowlist audit trail." },
    "duration_seconds":  { "type": "number", "minimum": 0 }
  }
}
```

## 3. Remediation attempt

Emitted by `scripts/<os>/remediations/*.ps1` and embedded in the run snapshot.

```json
{
  "title": "RemediationAttempt",
  "type": "object",
  "required": ["id", "target", "attempted_at", "succeeded", "before", "after"],
  "properties": {
    "id":            { "type": "string", "description": "Remediation identifier, e.g., 'restart-stopped-service'." },
    "target":        { "type": "string", "description": "What was acted on, e.g., service name, path." },
    "finding_id":    { "type": "string", "description": "The check result id that justified this remediation." },
    "attempted_at":  { "type": "string", "format": "date-time" },
    "succeeded":     { "type": "boolean" },
    "before":        { "type": "object", "description": "State captured before action." },
    "after":         { "type": "object", "description": "State captured after action." },
    "bytes_freed":   { "type": ["integer", "null"] },
    "error":         { "type": ["string", "null"] }
  }
}
```

## 4. History line (`state/history.jsonl`)

Compact. One line per run. Append-only — never rewrite.

```json
{
  "run_id": "2026-04-27T09:00:00-04:00",
  "hostname": "...",
  "os": "windows",
  "elevated": false,
  "severity_counts": {
    "storage":  { "OK": 0, "INFO": 0, "WARN": 1, "CRIT": 0, "UNKNOWN": 0 },
    "security": { "OK": 3, "INFO": 0, "WARN": 0, "CRIT": 0, "UNKNOWN": 0 }
  },
  "remediation_counts": { "attempted": 1, "succeeded": 1, "failed": 0 },
  "duration_seconds": 247,
  "checks_ran": ["disk-space", "event-log-errors"],
  "top_metrics": { "disk-space.used_pct": 87 }
}
```

`checks_ran` lists the ids of the checks the orchestrator dispatched this run — cadence-skipped and script-missing checks are absent. It is the authoritative per-check "when did it last run" signal for cadence selection and `trend.last_run`.

`top_metrics` is a small denormalization so trend queries don't rehydrate every run's full JSON. It captures every scalar detail key of every check that ran, keyed `<check.id>.<detailKey>`; the trend engine reads one well-known key per check (`Get-TrendRelevantKey`).

## Timestamp and text encoding

- Timestamps are always ISO 8601 with offset (`yyyy-MM-ddTHH:mm:sszzz`). `(Get-Date).ToString('o')` in PowerShell.
- All files are UTF-8 without BOM unless the file is written by `Out-File`/`Set-Content`, in which case pass `-Encoding utf8` (Windows PowerShell 5.1 defaults to UTF-16 LE with BOM).
- `state/history.jsonl` is LF-terminated regardless of host OS; git and most tools handle this cleanly.
