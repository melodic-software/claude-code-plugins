# Multi-Language Support Strategy

**Last Updated:** 2025-11-18

## Overview

Each hook supports multiple language implementations through subdirectories, enabling teams to choose the best tool for each task while maintaining a consistent interface.

## Current Implementation

All hooks currently use **bash** as the initial implementation:

- Cross-platform compatibility (via Git Bash on Windows)
- Simple, readable scripts
- Direct access to shell utilities (grep, sed, jq)
- Fast execution with minimal dependencies

## Multi-Language Directory Structure

Each hook supports multiple language implementations through subdirectories:

```text
.claude/hooks/prevent-backup-files/
├── bash/                           # Bash implementation
│   └── prevent-backup-files.sh
├── python/                         # Python implementation (future)
│   ├── prevent_backup_files.py
│   └── requirements.txt
├── typescript/                     # TypeScript implementation (future)
│   ├── src/
│   │   └── index.ts
│   ├── dist/
│   │   └── index.js
│   └── package.json
├── hook.yaml                       # Implementation metadata & selection
├── README.md
└── tests/
    ├── integration.test.sh         # Tests active implementation
    ├── bash.test.sh                # Bash-specific tests (optional)
    ├── python.test.sh              # Python-specific tests (future)
    └── fixtures/
```

## Configuration-Based Selection (hook.yaml)

Each hook has a `hook.yaml` file declaring available implementations:

```yaml
name: prevent-backup-files
version: 1.0.0

# Implementation Management
implementations:
  bash:
    entry_point: bash/prevent-backup-files.sh
    handler: main
    minimum_version: "4.0"
    available: true
  python:
    entry_point: python/prevent_backup_files.py
    handler: validate
    minimum_version: "3.8"
    dependencies: python/requirements.txt
    available: false  # Not yet implemented
  typescript:
    entry_point: typescript/dist/index.js
    handler: validate
    build_command: npm run build
    available: false

# Selection Strategy
selection:
  strategy: preference_order
  preference_order:
    - typescript  # Try TypeScript first (fastest when available)
    - python      # Fallback to Python
    - bash        # Final fallback (always available)
  active: bash    # Currently active implementation
```

## Adding Python Implementation

**Step-by-step migration example:**

### 1. Create python/ directory

```bash
mkdir .claude/hooks/prevent-backup-files/python
```

### 2. Create Python implementation

```python
# python/prevent_backup_files.py
import json
import sys

def validate(payload):
    # Your logic here
    pass

if __name__ == "__main__":
    payload = json.load(sys.stdin)
    validate(payload)
```

### 3. Update hook.yaml

```yaml
implementations:
  python:
    available: true  # Mark as available
selection:
  active: python     # Switch to Python
```

### 4. Update .claude/settings.json

```json
{
  "command": "python .claude/hooks/prevent-backup-files/python/prevent_backup_files.py"
}
```

### 5. Test both implementations

```bash
# Test Python
bash .claude/hooks/prevent-backup-files/tests/integration.test.sh

# Compare with bash (temporarily switch back)
```

## Best Tool for the Job

**Choose implementation based on requirements:**

- **Bash:** Simple string matching, git commands, file operations, universal availability
- **Python:** Complex parsing, regex, data processing, external libraries (PyYAML, etc.)
- **TypeScript/Node:** JSON processing, async operations, npm ecosystem, performance

## Migration Strategy

**Recommended approach:**

1. **Start with bash** (fast to implement, no dependencies)
2. **Migrate to Python** when logic complexity increases
3. **Use TypeScript** for performance-critical or async-heavy hooks

## Multi-Language Support Benefits

- **Language isolation:** bash/, python/, typescript/ subdirectories
- **Native conventions:** Each language follows its own project structure
- **Independent tooling:** Language-specific dependencies and build processes
- **Configuration-based selection:** Switch implementations without code changes
- **Migration support:** Run multiple implementations concurrently during transition
- **Fallback strategy:** Preference-order selection (try typescript → python → bash)

## Implementation Examples

### Bash Implementation

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source shared utilities
source "${SCRIPT_DIR}/../../shared/json-utils.sh"
source "${SCRIPT_DIR}/../../shared/config-utils.sh"

# Load config
CONFIG="${SCRIPT_DIR}/../hook.yaml"
is_hook_enabled "$CONFIG" || exit 0

# Your logic here
exit 0
```

### Python Implementation

```python
#!/usr/bin/env python3
import json
import sys
from pathlib import Path

def load_config(hook_dir):
    """Load hook.yaml configuration"""
    # Implementation here
    pass

def is_hook_enabled(config):
    """Check if hook is enabled"""
    return config.get('enabled', True)

def validate(payload):
    """Main validation logic"""
    # Your logic here
    pass

if __name__ == "__main__":
    # Load configuration
    script_dir = Path(__file__).parent
    hook_dir = script_dir.parent
    config = load_config(hook_dir)

    if not is_hook_enabled(config):
        sys.exit(0)

    # Read JSON payload
    payload = json.load(sys.stdin)

    # Validate
    validate(payload)

    sys.exit(0)
```

### TypeScript Implementation

```typescript
// typescript/src/index.ts
import * as fs from 'fs';
import * as path from 'path';
import * as yaml from 'js-yaml';

interface HookPayload {
  tool: string;
  file_path?: string;
  // ... other fields
}

interface HookConfig {
  enabled: boolean;
  enforcement: string;
  // ... other fields
}

function loadConfig(hookDir: string): HookConfig {
  const configPath = path.join(hookDir, 'hook.yaml');
  const configContent = fs.readFileSync(configPath, 'utf8');
  return yaml.load(configContent) as HookConfig;
}

function validate(payload: HookPayload, config: HookConfig): void {
  // Your logic here
}

async function main() {
  const hookDir = path.join(__dirname, '../..');
  const config = loadConfig(hookDir);

  if (!config.enabled) {
    process.exit(0);
  }

  const input = fs.readFileSync(0, 'utf8');
  const payload: HookPayload = JSON.parse(input);

  validate(payload, config);

  process.exit(0);
}

main().catch((error) => {
  console.error(error);
  process.exit(3);
});
```

## Testing Multi-Language Implementations

Each language can have its own test file, or use shared integration tests that test the active implementation:

```text
tests/
├── integration.test.sh         # Tests active implementation (language-agnostic)
├── bash.test.sh                # Bash-specific unit tests
├── python.test.sh              # Python-specific unit tests
├── typescript.test.sh          # TypeScript-specific unit tests
└── fixtures/
    └── payloads.json           # Shared test data
```

**Run tests for active implementation:**

```bash
bash .claude/hooks/<hook-name>/tests/integration.test.sh
```

**Run language-specific tests:**

```bash
# Bash
bash .claude/hooks/<hook-name>/tests/bash.test.sh

# Python (when available)
pytest .claude/hooks/<hook-name>/tests/

# TypeScript (when available)
npm test --prefix .claude/hooks/<hook-name>/typescript/
```
