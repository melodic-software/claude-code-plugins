# Script-Based Automation

This document covers when and how to use script-based automation effectively, including language selection criteria and script creation guidelines.

## Philosophy: Automate When Beneficial

**Prefer scripts over manual operations when:**

- **Template generation**: Creating files with predictable structure (skills, configs, documentation)
- **File scaffolding**: Setting up directory structures with multiple files
- **Batch operations**: Performing the same operation on multiple files/directories
- **Validation/linting**: Checking structure, syntax, or content quality
- **Report generation**: Producing formatted output from data analysis
- **Repetitive tasks**: Operations that will be performed multiple times

**Prefer manual operations when:**

- **One-off tasks**: Single file edits or unique operations
- **Simple edits**: Minor changes to existing content
- **Exploratory work**: Understanding codebase before automating
- **User-driven decisions**: Tasks requiring judgment calls or clarification

## Benefits of Script-Based Automation

**Token Efficiency:**

- Scripts execute without consuming context window tokens
- File generation happens outside LLM processing
- Only script invocation and results appear in conversation
- Saves potentially thousands of tokens per operation

**Determinism:**

- Scripts produce consistent, predictable output
- No variation in structure or formatting
- Reduces risk of human error or oversight
- Easier to validate and test

**Speed:**

- Scripts run faster than manual file generation
- No need to compose content token-by-token
- Batch operations complete in single execution
- Less time spent on mechanical tasks

**Maintainability:**

- Scripts serve as living documentation of process
- Easy to update when templates evolve
- Version controlled alongside repository
- Team members can run same automation

**Reusability:**

- Scripts can be invoked multiple times
- Consistent results across different contexts
- Shareable across projects and teams
- Foundation for building more complex automation

## Language Selection Criteria

### Default Preference: PowerShell Core (pwsh 7+)

Use PowerShell Core as the default choice for new scripts:

- **Cross-platform**: Runs on Windows, macOS, Linux
- **System administration strength**: Native Windows integration, excellent for file/registry/process operations
- **Object-oriented pipelines**: Rich data manipulation without text parsing
- **Windows native feel**: Familiar to Windows developers while being cross-platform
- **Modern language features**: Strong typing, error handling, module system

**When PowerShell Core is Ideal:**

- File system operations (creating/copying/moving files and directories)
- System configuration tasks (environment variables, registry, services)
- Windows-centric automation (COM objects, .NET framework integration)
- Cross-platform scripting where Windows is primary target
- Scenarios requiring rich object manipulation in pipelines

### Alternative Languages: Best Tool for the Job

**Use Python when:**

- Data processing, analysis, or transformation (pandas, numpy)
- Complex automation with rich library ecosystem (requests, BeautifulSoup)
- Cross-platform with strong community libraries
- Team expertise is primarily Python
- Scientific computing, machine learning, or data science tasks

**Use Bash when:**

- Unix/Linux environment-specific tasks
- Simple text processing with grep/sed/awk integration
- Traditional Unix toolchain integration
- Lightweight automation without dependencies
- Team expertise is primarily Linux/Unix

**Use TypeScript/JavaScript (Node.js) when:**

- Web API integration or HTTP requests
- JSON manipulation and validation
- npm ecosystem integration (existing Node.js project)
- Frontend tooling integration
- Team expertise is primarily web development

**Decision Framework:**

```text
What kind of task is this?

File/system operations     -> PowerShell Core
Data processing            -> Python
Unix toolchain             -> Bash
Web/API integration        -> Node.js/TypeScript
Platform-specific          -> Native platform language
```

**Consider:**

- **Task requirements**: What does the script need to accomplish?
- **Platform needs**: Cross-platform vs platform-specific?
- **Team expertise**: What languages does the team know?
- **Existing toolchain**: What's already in use in the project?
- **Dependencies**: What libraries/tools are required?
- **Maintainability**: Who will maintain this script long-term?

## Script Creation Guidelines

### 1. Proper Error Handling

```powershell
# PowerShell example
try {
    # Operation that might fail
    Copy-Item $source $destination -ErrorAction Stop
    Write-Host "File copied successfully" -ForegroundColor Green
}
catch {
    Write-Error "Failed to copy file: $_"
    exit 1
}
```

```python
# Python example
import sys

try:
    # Operation that might fail
    shutil.copy(source, destination)
    print("File copied successfully")
except Exception as e:
    print(f"Failed to copy file: {e}", file=sys.stderr)
    sys.exit(1)
```

### 2. Usage Documentation

Include comprehensive help text in script header:

```powershell
<#
.SYNOPSIS
    Example script demonstrating PowerShell documentation
.DESCRIPTION
    Performs automated operations with proper parameter handling
.PARAMETER InputFile
    Path to the input file to process
.PARAMETER OutputPath
    Destination directory for results (default: ./output)
.EXAMPLE
    .\example_script.ps1 -InputFile data.json -OutputPath ./results
#>
```

```python
#!/usr/bin/env python3
"""
Example Script - Demonstrates proper documentation

Performs automated operations with clear usage instructions
and comprehensive help text.

Usage:
    example_script.py <input> --option <value>

Examples:
    example_script.py data.json --format pretty
    example_script.py input.txt --output results.txt
"""
```

### 3. Cross-Platform Considerations

```powershell
# PowerShell - already cross-platform
$separator = [System.IO.Path]::DirectorySeparatorChar
$configPath = Join-Path $HOME ".claude" "config.json"
```

```python
# Python - use pathlib for cross-platform paths
from pathlib import Path

config_path = Path.home() / ".claude" / "config.json"
```

### 4. Executable Permissions

For Unix/Linux compatibility:

```bash
# Add shebang to scripts
#!/usr/bin/env pwsh     # PowerShell
#!/usr/bin/env python3  # Python
#!/bin/bash             # Bash

# Set executable permission
chmod +x script-name.ps1
chmod +x script-name.py
chmod +x script-name.sh
```

### 5. Validation and Testing

Before committing new scripts:

- Test on target platform(s)
- Verify error handling works correctly
- Confirm help text is accurate
- Check exit codes (0 for success, non-zero for failure)
- Validate cross-platform compatibility (if applicable)
- Document any dependencies or prerequisites
- Add examples to script documentation

## Integration with Claude Code Workflow

**Recognition Pattern:**

When encountering tasks that involve:

- Creating multiple files with similar structure
- Generating content from templates
- Validating structure or syntax
- Batch processing operations
- Repetitive manual steps

**Decision Process:**

1. **Ask**: "Will this task be repeated?"
2. **Ask**: "Does this follow a predictable pattern?"
3. **Ask**: "Would a script save tokens and time?"
4. **Ask**: "Is there an existing script I should use?"

**If yes to 2+ questions**: Consider script-based automation

**If existing script available**: Use it instead of manual operations

**If no script exists but task is repetitive**: Propose creating a script

**Example Recognition:**

```markdown
User: "I need to validate all markdown files for linting compliance"

Bad approach: Manually open and review each file

Good approach: Use the markdown-linting skill:
  - Invoke markdown-linting skill
  - Request validation of all markdown files
  - Skill handles automated linting with proper configuration
```

## When to Propose New Scripts

**Propose creating a new script when:**

- Task will be repeated 3+ times
- Manual execution is error-prone
- Consistency is critical
- Token cost of manual operations is high
- Script would benefit future users

**Proposal format:**

```markdown
I notice this task involves [repetitive pattern]. This could be automated with a script.

Benefits:
- [Token savings estimate]
- [Consistency improvement]
- [Time savings]
- [Reusability for future tasks]

Proposed implementation:
- Language: [PowerShell Core / Python / Bash / Node.js]
- Location: [path/to/scripts/]
- Functionality: [brief description]

Would you like me to create this script?
```

---

**Last Updated:** 2025-11-30
