# PowerShell Setup

## PowerShell 7+

```powershell
winget install --id Microsoft.Powershell -e --source winget
```

### Update Execution Policy

By default, Windows is configured to use a default execution policy of `Restricted`. Run the following commands in a PowerShell terminal as **Administrator**.

```powershell
Get-ExecutionPolicy # See what the current execution policy is set to
Set-ExecutionPolicy RemoteSigned # Set it to remote signed
```

### Update Help Files / Documentation

Run the following command in a new PowerShell terminal as **Administrator** once installed:

```powershell
Update-Help
```

## Pester

```powershell
Install-Module -Name Pester -Force -SkipPublisherCheck
```

## Common PowerShell Gotchas

### The `where` vs `where.exe` Problem

**The Issue:**

- `where` in PowerShell is an **alias** for the `Where-Object` cmdlet, which filters objects in the pipeline (similar to filtering/selecting items from a collection)
- `where.exe` is the **Windows executable** that locates programs in your PATH (similar to Unix `which`)

When you type `where gitkraken`, PowerShell interprets it as the `Where-Object` cmdlet and expects pipeline input, so it does nothing.

When you type `where.exe gitkraken`, you're explicitly calling the Windows executable that searches your PATH.

**PowerShell Alternatives:**

```powershell
# Use Get-Command instead (PowerShell native way)
Get-Command gitkraken

# Or use the gcm alias
gcm gitkraken

# To see all instances in PATH (like where.exe -a)
Get-Command gitkraken -All
```

**Quick Reference:**

| Command | What it does |
| ------- | ------------ |
| `where` | PowerShell alias for `Where-Object` (filters pipeline objects) |
| `where.exe` | Windows executable (finds programs in PATH) |
| `Get-Command` / `gcm` | PowerShell cmdlet (finds commands, shows full details) |

**Why this matters:** This is a common pitfall for developers coming from Unix/Linux backgrounds where `which` is the standard command. In PowerShell, prefer `Get-Command` (or `gcm`) for the native PowerShell experience, or use `where.exe` explicitly when you need the Windows PATH search behavior.
