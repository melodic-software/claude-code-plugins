# Troubleshooting

Common issues and solutions for the current-date skill.

## Issue: Command not found (Unix `date` command)

**Cause:** `date` command not available in environment

**Solution:**

- **Windows (cmd.exe/PowerShell)**: The Unix `date` command is not available natively. Use one of these options:
  - Install Git Bash (includes GNU coreutils)
  - Use WSL (Windows Subsystem for Linux)
  - Use PowerShell's `Get-Date` cmdlet instead (see [platform-alternatives.md](platform-alternatives.md))
- **Linux/macOS**: `date` should be pre-installed; reinstall coreutils (Linux) or verify system utilities (macOS) if missing

## Issue: `-u` flag not recognized

**Cause:** Using Windows cmd.exe or PowerShell native environment instead of Unix-like shell

**Solution:**

- **Windows**: Use Git Bash or WSL for Unix `date` command, or use PowerShell's `Get-Date -AsUTC` parameter
- **Linux/macOS**: The `-u` flag is standard in both GNU and BSD `date` implementations; reinstall if missing

## Issue: UTC time seems incorrect

**Cause:** Misunderstanding - UTC doesn't change for daylight saving time or timezones

**Clarification:**

- UTC is the universal time standard - it never changes based on location
- If you need local time, use the "Local timezone" alternative format (see [format-reference.md](format-reference.md))
- UTC is intentionally used to avoid timezone confusion across distributed teams

---

**Parent:** [SKILL.md](../SKILL.md)
