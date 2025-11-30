# Platform Alternatives

Cross-platform compatibility and PowerShell alternatives for the current-date skill.

## Cross-Platform Compatibility

The Unix `date` command works consistently across Unix-like platforms:

- **Git Bash (Windows)**: Uses GNU coreutils `date`
- **WSL (Windows)**: Uses GNU coreutils `date` (same as Linux)
- **Linux**: Native GNU coreutils `date`
- **macOS**: BSD `date` supports same format specifiers

**Note:** Native Windows (cmd.exe/PowerShell) does not include the Unix `date` command. Windows users have two options:

1. Use Git Bash (recommended for consistency with Unix environments)
2. Use PowerShell's `Get-Date` cmdlet (see below)

## PowerShell Alternatives (Windows)

For Windows users without Git Bash, use PowerShell's `Get-Date` cmdlet:

### UTC date and time (PowerShell 7+)

```powershell
Get-Date -Format "yyyy-MM-dd HH:mm:ss 'UTC' (dddd)" -AsUTC
# Output: 2025-11-09 18:31:10 UTC (Sunday)
```

### UTC date and time (Windows PowerShell 5.1)

```powershell
(Get-Date).ToUniversalTime().ToString("yyyy-MM-dd HH:mm:ss 'UTC' (dddd)")
# Output: 2025-11-09 18:31:10 UTC (Sunday)
```

### UTC date only

```powershell
Get-Date -Format "yyyy-MM-dd" -AsUTC
# Output: 2025-11-09
```

### ISO 8601 with UTC timezone

```powershell
Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ" -AsUTC
# Output: 2025-11-09T18:31:10Z
```

### Unix timestamp (seconds since epoch)

```powershell
[int](Get-Date -UFormat %s)
# Output: 1731175870
```

**Note:** The `-AsUTC` parameter was added in PowerShell 7.0. For Windows PowerShell 5.1, use the `.ToUniversalTime()` method as shown above.

---

**Parent:** [SKILL.md](../SKILL.md)
