# Alternative Date Formats

Different output formats for the current-date skill beyond the default.

## UTC date only (simple)

```bash
date -u +"%Y-%m-%d"
# Output: 2025-11-09
```

## UTC timestamp (compact for filenames)

```bash
date -u +"%Y%m%d-%H%M%S"
# Output: 20251109-183115
```

## Unix timestamp (seconds since epoch)

```bash
date +"%s"
# Output: 1731175870
```

## ISO 8601 with UTC timezone

```bash
date -u +"%Y-%m-%dT%H:%M:%SZ"
# Output: 2025-11-09T18:31:10Z
```

## Local timezone (when specifically needed)

```bash
date +"%Y-%m-%d %H:%M:%S %Z (%A)"
# Output: 2025-11-09 13:31:10 EST (Sunday)
```

**Note:** Local timezone should only be used when specifically required for user-facing content. Default to UTC for all other operations.

---

**Parent:** [SKILL.md](../SKILL.md)
