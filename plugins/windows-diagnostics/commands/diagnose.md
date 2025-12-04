---
description: Run Windows system diagnostics to troubleshoot crashes, freezes, disk/memory issues, and hardware errors
argument-hint: [quick | events | disk | memory | stability | hardware | performance | crashes | full]
allowed-tools: Task, Bash, Read, Glob, Grep
---

# Windows Diagnostics Command

Run comprehensive Windows 11 system diagnostics using PowerShell to identify causes of crashes, freezes, unexpected reboots, and performance issues.

## Instructions

**Use the diagnostician agent to analyze system health based on the specified scope.**

The diagnostician agent uses the `windows-diagnostics:system-diagnostics` skill for:

- Event log analysis (crashes, errors, warnings)
- Disk health monitoring (SMART data, filesystem)
- Memory diagnostics (usage, leaks, hardware)
- Hardware error detection (WHEA, devices, drivers)
- Performance analysis (CPU, memory, disk bottlenecks)
- System stability metrics (uptime, restarts, BSOD)

**Parse the arguments and invoke the agent:**

```text
$ARGUMENTS

Based on the arguments, determine the diagnostic scope:

If 'quick' or no arguments:
  - Run quick health check (system info, uptime, recent errors, disk/memory snapshot)
  - Good for initial triage

If 'events':
  - Focus on Windows Event Viewer analysis
  - Look for critical and error events
  - Check System and Application logs

If 'disk':
  - Focus on disk health diagnostics
  - Check SMART data, reliability counters
  - Look for disk-related events

If 'memory':
  - Focus on memory diagnostics
  - Analyze memory usage, top consumers
  - Check for memory-related events

If 'stability':
  - Focus on system stability
  - Check uptime, restart patterns
  - Look for unexpected shutdowns

If 'hardware':
  - Focus on hardware error detection
  - Check device status, WHEA events
  - Look for driver issues

If 'performance':
  - Focus on performance analysis
  - Check CPU, memory, disk utilization
  - Identify bottlenecks

If 'crashes':
  - Focus on crash analysis
  - Check for BSOD events, minidumps
  - Look for application crashes

If 'full':
  - Run comprehensive diagnostic across all categories
  - Takes longer but provides complete picture

Default: quick health check
```

## Examples

### Quick Health Check

```text
/windows-diagnostics:diagnose
/windows-diagnostics:diagnose quick
```

### Event Log Analysis

```text
/windows-diagnostics:diagnose events
```

### Disk Health Check

```text
/windows-diagnostics:diagnose disk
```

### Memory Diagnostics

```text
/windows-diagnostics:diagnose memory
```

### System Stability Analysis

```text
/windows-diagnostics:diagnose stability
```

### Hardware Error Detection

```text
/windows-diagnostics:diagnose hardware
```

### Performance Analysis

```text
/windows-diagnostics:diagnose performance
```

### Crash Analysis

```text
/windows-diagnostics:diagnose crashes
```

### Full Comprehensive Scan

```text
/windows-diagnostics:diagnose full
```

## Output Format

The agent returns a structured diagnostic report:

```markdown
## Diagnostic Summary

**Scope**: [Category analyzed]
**System**: [Windows version, uptime]
**Timestamp**: [When diagnostic was run]

## Findings

### Critical Issues
[Issues requiring immediate attention]

### Warnings
[Potential problems to monitor]

### Observations
[General health observations]

## Recommendations

### Suggested Actions (User Runs)
[Commands/steps for user to execute manually]

### Further Investigation
[Areas that may need deeper analysis]

## Raw Data

[Key diagnostic output for reference]
```

## Safety Model

This command uses **read-only diagnostics**:

- Only gathers system information
- Never executes repair commands automatically
- Provides repair suggestions for user to run manually
- Notes when administrator privileges would be needed

## Command Design Notes

This command delegates to the diagnostician agent, which uses the `windows-diagnostics:system-diagnostics` skill. The skill provides:

- PowerShell commands for each diagnostic category
- Progressive disclosure of reference files based on scope
- Safety guidelines for read-only vs write operations
- Graceful degradation when not running as administrator
