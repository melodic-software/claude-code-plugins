# Python Code Quality Tools

Comprehensive guide to code quality tools for Python projects (2024-2025), covering linting, formatting, type checking, security scanning, and automation.

**Official Documentation:**

- Ruff: <https://docs.astral.sh/ruff/>
- mypy: <https://mypy-lang.org/> | <https://mypy.readthedocs.io/>
- Bandit: <https://bandit.readthedocs.io/>
- pre-commit: <https://pre-commit.com/>

**Last Verified:** 2025-11-25

---

## Table of Contents

1. [Tool Ecosystem Overview](#tool-ecosystem-overview)
2. [Ruff - All-in-One Linter and Formatter](#ruff---all-in-one-linter-and-formatter)
3. [mypy - Static Type Checker](#mypy---static-type-checker)
4. [Bandit - Security Linter](#bandit---security-linter)
5. [pre-commit - Git Hooks Framework](#pre-commit---git-hooks-framework)
6. [Editor Integration](#editor-integration)
7. [CI/CD Integration](#cicd-integration)
8. [Complete Configuration Examples](#complete-configuration-examples)
9. [Workflow and Best Practices](#workflow-and-best-practices)

---

## Tool Ecosystem Overview

### Modern Python Code Quality Stack (2024-2025)

The recommended modern stack for Python code quality:

| Tool | Purpose | Replaces | Speed | Installation |
| --- | --- | --- | --- | --- |
| **Ruff** | Linter + Formatter | Flake8, Black, isort, pyupgrade, autoflake | 10-100x faster | `pip install ruff` |
| **mypy** | Type Checker | - | Fast | `pip install mypy` |
| **Bandit** | Security Scanner | - | Fast | `pip install bandit` |
| **pre-commit** | Automation | Manual hooks | N/A | `pip install pre-commit` |

### Why Ruff?

**Speed:** Ruff is written in Rust and is 10-100x faster than traditional Python linters:

- **Flake8:** ~20 seconds → **Ruff:** ~0.2 seconds (on large codebases)
- Fast enough to run as a commit hook without noticeable delay

**Consolidation:** Replaces multiple tools with a single, unified tool:

- Linter (Flake8 + 50+ plugins)
- Formatter (Black)
- Import sorter (isort)
- Code modernizer (pyupgrade)
- Unused code remover (autoflake)

**Compatibility:** Drop-in replacement for Black with 99.9%+ compatibility on existing Black-formatted code.

### Legacy vs Modern Tools

**Legacy Stack (pre-2024):**

```text
Flake8 (linting) + Black (formatting) + isort (imports) + pyupgrade (syntax) + autoflake (unused)
= 5 separate tools, 5 configs, slower execution
```

**Modern Stack (2024+):**

```text
Ruff (linting + formatting + imports + syntax + unused)
= 1 tool, 1 config, 10-100x faster
```

**Migration Note:** Most projects should migrate to Ruff unless they have specific requirements for legacy tools.

---

## Ruff - All-in-One Linter and Formatter

**Official Docs:** <https://docs.astral.sh/ruff/>

Ruff is an extremely fast Python linter and code formatter, designed as a drop-in replacement for Flake8, Black, isort, and more.

### Installation

**Using pip:**

```bash
pip install ruff
```

**Using uv (recommended):**

```bash
uv tool install ruff@latest
```

**Using standalone installers:**

```bash
# macOS and Linux
curl -LsSf https://astral.sh/ruff/install.sh | sh

# Windows (PowerShell)
powershell -c "irm https://astral.sh/ruff/install.ps1 | iex"
```

**Verification:**

```bash
ruff --version
# Expected: ruff 0.14.0+ (or newer)
```

### Basic Usage

**Linting:**

```bash
# Lint all files in current directory
ruff check .

# Lint specific directory
ruff check src/

# Lint with auto-fix
ruff check --fix

# Lint with unsafe fixes enabled
ruff check --fix --unsafe-fixes
```

**Formatting:**

```bash
# Format all files in current directory
ruff format .

# Format specific directory
ruff format src/

# Check formatting without changes
ruff format --check
```

**Combined workflow:**

```bash
# Fix imports, then lint, then format
ruff check --select I --fix    # Sort imports
ruff check --fix                # Fix other issues
ruff format                     # Format code
```

### Configuration in pyproject.toml

**Minimal configuration:**

```toml
[tool.ruff]
line-length = 88  # Same as Black
target-version = "py312"  # Your Python version

[tool.ruff.lint]
select = ["E", "F"]  # Enable Pyflakes (F) and pycodestyle errors (E)
ignore = []

[tool.ruff.format]
quote-style = "double"
indent-style = "space"
```

**Recommended configuration (2025):**

```toml
[tool.ruff]
line-length = 88
target-version = "py312"

# Exclude common directories
exclude = [
    ".git",
    ".venv",
    "__pycache__",
    "build",
    "dist",
]

[tool.ruff.lint]
# Select comprehensive rule set
select = [
    "E",      # pycodestyle errors
    "F",      # Pyflakes
    "W",      # pycodestyle warnings
    "UP",     # pyupgrade - modern Python syntax
    "I",      # isort - import sorting
    "B",      # flake8-bugbear
    "SIM",    # flake8-simplify
    "RET",    # flake8-return
    "C4",     # flake8-comprehensions
    "TID",    # flake8-tidy-imports
    "ICN",    # flake8-import-conventions
    "TD",     # flake8-todos
]

# Allow auto-fixing for all enabled rules
fixable = ["ALL"]
unfixable = []

# Ignore specific rules globally
ignore = [
    "E501",   # Line too long (handled by formatter)
]

[tool.ruff.lint.per-file-ignores]
# Ignore specific rules in specific files
"__init__.py" = ["F401"]  # Unused imports in __init__.py
"tests/*" = ["S101"]      # Allow assert in tests

[tool.ruff.format]
quote-style = "double"
indent-style = "space"
skip-magic-trailing-comma = false
line-ending = "auto"

# Enable docstring code formatting
docstring-code-format = true
```

### Rule Selection

**Common rule prefixes:**

- `E` - pycodestyle errors (E4, E7, E9)
- `F` - Pyflakes (unused imports, undefined names)
- `W` - pycodestyle warnings
- `I` - isort (import sorting)
- `B` - flake8-bugbear (common bugs and design issues)
- `SIM` - flake8-simplify (code simplification)
- `UP` - pyupgrade (modern Python syntax)
- `RET` - flake8-return (return statement issues)
- `S` - flake8-bandit (security issues)

**Full rule reference:** <https://docs.astral.sh/ruff/rules/>

**Enabling all rules (advanced):**

```toml
[tool.ruff.lint]
select = ["ALL"]  # Enable everything
ignore = [
    "D",      # Disable pydocstyle (documentation)
    "ANN",    # Disable flake8-annotations (type hints)
    "COM",    # Disable flake8-commas (trailing commas)
]
```

### Fix Safety

Ruff categorizes fixes as "safe" or "unsafe":

- **Safe fixes:** Preserve code meaning and behavior
- **Unsafe fixes:** May change behavior or remove comments

**Enabling unsafe fixes:**

```bash
# Show unsafe fixes
ruff check --unsafe-fixes

# Apply unsafe fixes
ruff check --fix --unsafe-fixes
```

**Configuring fix safety:**

```toml
[tool.ruff.lint]
# Promote unsafe fixes to safe
extend-safe-fixes = ["F601"]

# Demote safe fixes to unsafe
extend-unsafe-fixes = ["UP034"]
```

### Suppression Comments

**Inline suppression:**

```python
# Ignore specific rule
x = 1  # noqa: F841

# Ignore multiple rules
i = 1  # noqa: E741, F841

# Ignore all violations
x = 1  # noqa
```

**File-level suppression:**

```python
# ruff: noqa
# This file is exempt from all Ruff checks

# ruff: noqa: F841
# This file is exempt from F841 checks only
```

**Detecting unused noqa comments:**

```bash
# Find unused suppression comments
ruff check --select RUF100

# Remove unused suppression comments
ruff check --select RUF100 --fix
```

### Pre-commit Integration

```yaml
repos:
  - repo: https://github.com/astral-sh/ruff-pre-commit
    rev: v0.14.5  # Use latest version
    hooks:
      # Run the linter
      - id: ruff
        args: [--fix]
      # Run the formatter
      - id: ruff-format
```

---

## mypy - Static Type Checker

**Official Docs:** <https://mypy-lang.org/> | <https://mypy.readthedocs.io/>

mypy is an optional static type checker for Python that combines the benefits of dynamic typing with compile-time type checking.

### mypy Installation

```bash
pip install mypy
```

**Verification:**

```bash
mypy --version
# Expected: mypy 1.0+ (or newer)
```

### mypy Basic Usage

```bash
# Type check all files in current directory
mypy .

# Type check specific file or directory
mypy src/

# Type check with strict mode
mypy --strict .

# Show error codes
mypy --show-error-codes .
```

### mypy Configuration in pyproject.toml

**Minimal configuration:**

```toml
[tool.mypy]
python_version = "3.12"
warn_return_any = true
warn_unused_configs = true
```

**Strict mode (recommended for new projects):**

```toml
[tool.mypy]
strict = true
python_version = "3.12"

# Exclude directories
exclude = [
    "build/",
    "dist/",
    "tests/",
]
```

**What `strict = true` enables:**

- `disallow_untyped_defs` - Require type annotations on functions
- `disallow_incomplete_defs` - Disallow partially typed functions
- `disallow_untyped_calls` - Disallow calling untyped functions
- `disallow_untyped_decorators` - Require typed decorators
- `warn_return_any` - Warn when returning Any
- `warn_unused_ignores` - Warn about unused `# type: ignore` comments
- And more...

**Custom configuration (fine-grained control):**

```toml
[tool.mypy]
python_version = "3.12"

# Import discovery
namespace_packages = true
explicit_package_bases = true

# Warnings
warn_return_any = true
warn_unused_configs = true
warn_redundant_casts = true
warn_unused_ignores = true
warn_no_return = true
warn_unreachable = true

# Strictness
disallow_untyped_defs = true
disallow_incomplete_defs = true
check_untyped_defs = true
disallow_untyped_decorators = true

# Error reporting
show_error_codes = true
show_column_numbers = true
pretty = true

# Exclude directories
exclude = [
    "build/",
    "dist/",
]
```

**Per-module overrides:**

```toml
[[tool.mypy.overrides]]
module = "tests.*"
ignore_missing_imports = true
disallow_untyped_defs = false

[[tool.mypy.overrides]]
module = "legacy.*"
strict = false
```

### Inline Type Annotations

**Function annotations:**

```python
def greet(name: str) -> str:
    return f"Hello, {name}"

def process_items(items: list[str]) -> None:
    for item in items:
        print(item)
```

**Variable annotations:**

```python
# Simple types
count: int = 0
name: str = "Alice"
is_valid: bool = True

# Collections
numbers: list[int] = [1, 2, 3]
mapping: dict[str, int] = {"a": 1, "b": 2}
unique_items: set[str] = {"x", "y"}

# Optional types
from typing import Optional
maybe_name: Optional[str] = None
```

**Type aliases:**

```python
from typing import TypeAlias

UserId: TypeAlias = int
UserMap: TypeAlias = dict[UserId, str]

def get_user(user_id: UserId) -> str:
    users: UserMap = {1: "Alice", 2: "Bob"}
    return users.get(user_id, "Unknown")
```

### Ignoring Errors

**Inline ignore:**

```python
# Ignore all errors on this line
result = some_untyped_function()  # type: ignore

# Ignore specific error code
result = some_untyped_function()  # type: ignore[no-untyped-call]
```

**Common error codes:**

- `arg-type` - Argument has incompatible type
- `no-untyped-call` - Call to untyped function
- `no-untyped-def` - Function is missing type annotation
- `import` - Cannot find implementation or library stub
- `assignment` - Incompatible types in assignment

**Finding error codes:**

```bash
mypy --show-error-codes src/
```

### Common Issues and Solutions

#### Issue: Missing imports or library stubs

```python
import numpy as np  # error: Cannot find implementation or library stub
```

#### Solution: Install type stubs

```bash
pip install types-numpy
```

#### Issue: Third-party library without type hints

```toml
[[tool.mypy.overrides]]
module = "untyped_library.*"
ignore_missing_imports = true
```

#### Issue: Gradual typing migration

Start with:

```toml
[tool.mypy]
check_untyped_defs = true  # Check typed functions only
```

Then progressively enable:

```toml
disallow_incomplete_defs = true
disallow_untyped_defs = true
strict = true
```

---

## Bandit - Security Linter

**Official Docs:** <https://bandit.readthedocs.io/>

Bandit is a tool designed to find common security issues in Python code by analyzing the AST (Abstract Syntax Tree).

### Bandit Installation

```bash
pip install bandit
```

**Verification:**

```bash
bandit --version
# Expected: bandit 1.7+ (or newer)
```

### Bandit Basic Usage

```bash
# Scan current directory recursively
bandit -r .

# Scan specific directory
bandit -r src/

# Show only high-severity issues
bandit -r . -ll

# Generate report in different formats
bandit -r . -f json -o report.json
bandit -r . -f html -o report.html
```

### Configuration

**Using .bandit file:**

```yaml
# .bandit
exclude_dirs:
  - /test
  - /venv
  - /.venv

skips:
  - B101  # Skip assert_used test
  - B601  # Skip paramiko calls

tests:
  - B201
  - B301
```

**Using pyproject.toml:**

```toml
[tool.bandit]
exclude_dirs = ["tests", "venv", ".venv"]
skips = ["B101", "B601"]
```

### Common Security Issues Detected

**Hardcoded passwords (B105, B106, B107):**

```python
# BAD
password = "hardcoded_password"  # Bandit: B105
```

**SQL injection (B608):**

```python
# BAD
query = f"SELECT * FROM users WHERE id = {user_id}"  # Bandit: B608

# GOOD
query = "SELECT * FROM users WHERE id = ?"
cursor.execute(query, (user_id,))
```

**Using eval/exec (B307, B102):**

```python
# BAD
result = eval(user_input)  # Bandit: B307

# GOOD - Use ast.literal_eval for safe evaluation
import ast
result = ast.literal_eval(user_input)
```

**Insecure random (B311):**

```python
# BAD - For security/crypto purposes
import random
token = random.randint(0, 1000000)  # Bandit: B311

# GOOD - Use secrets module
import secrets
token = secrets.randbelow(1000000)
```

**Try/except with bare except (B110):**

```python
# BAD
try:
    risky_operation()
except:  # Bandit: B110
    pass

# GOOD
try:
    risky_operation()
except SpecificException as e:
    logger.error(f"Operation failed: {e}")
```

### Skipping False Positives

**Inline skip:**

```python
# Skip specific test
password = get_password_from_env()  # nosec B105

# Skip all tests on this line
result = eval(safe_expression)  # nosec
```

**Per-file skip in configuration:**

```toml
[tool.bandit.assert_used]
skips = ["*/test_*.py", "*/tests.py"]
```

### Pre-commit Integration (Bandit)

```yaml
repos:
  - repo: https://github.com/PyCQA/bandit
    rev: 1.7.10
    hooks:
      - id: bandit
        args: ["-c", "pyproject.toml"]
```

---

## pre-commit - Git Hooks Framework

**Official Docs:** <https://pre-commit.com/>

pre-commit is a framework for managing and maintaining multi-language pre-commit hooks.

### pre-commit Installation

```bash
pip install pre-commit
```

**Verification:**

```bash
pre-commit --version
# Expected: pre-commit 3.0+ (or newer)
```

### Quick Start

**1. Create `.pre-commit-config.yaml`:**

```yaml
repos:
  - repo: https://github.com/astral-sh/ruff-pre-commit
    rev: v0.14.5
    hooks:
      - id: ruff
        args: [--fix]
      - id: ruff-format

  - repo: https://github.com/pre-commit/mirrors-mypy
    rev: v1.18.2
    hooks:
      - id: mypy
        additional_dependencies: [types-requests]

  - repo: https://github.com/PyCQA/bandit
    rev: 1.7.10
    hooks:
      - id: bandit
        args: ["-c", "pyproject.toml"]
```

**2. Install the git hook:**

```bash
pre-commit install
```

**3. Run against all files (optional):**

```bash
pre-commit run --all-files
```

### Configuration Details

**Hook structure:**

```yaml
repos:
  - repo: <repository-url>
    rev: <version>
    hooks:
      - id: <hook-id>
        args: [<arguments>]
        files: <file-pattern>
        exclude: <exclude-pattern>
        additional_dependencies: [<packages>]
```

**Common pre-commit hooks:**

```yaml
repos:
  # General file checks
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v5.0.0
    hooks:
      - id: trailing-whitespace
      - id: end-of-file-fixer
      - id: check-yaml
      - id: check-json
      - id: check-toml
      - id: check-merge-conflict
      - id: check-added-large-files
      - id: detect-private-key

  # Python-specific
  - repo: https://github.com/astral-sh/ruff-pre-commit
    rev: v0.14.5
    hooks:
      - id: ruff
        args: [--fix]
      - id: ruff-format

  - repo: https://github.com/pre-commit/mirrors-mypy
    rev: v1.18.2
    hooks:
      - id: mypy
        additional_dependencies: [types-requests, types-pyyaml]

  - repo: https://github.com/PyCQA/bandit
    rev: 1.7.10
    hooks:
      - id: bandit
        args: ["-c", "pyproject.toml"]
```

### Advanced Configuration

**Per-file patterns:**

```yaml
hooks:
  - id: mypy
    files: ^src/
    exclude: ^tests/
```

**Custom stages:**

```yaml
repos:
  - repo: local
    hooks:
      - id: pytest
        name: pytest
        entry: pytest
        language: system
        pass_filenames: false
        always_run: true
        stages: [push]  # Only run on git push
```

**Local hooks:**

```yaml
repos:
  - repo: local
    hooks:
      - id: custom-script
        name: Run custom validation
        entry: python scripts/validate.py
        language: python
        types: [python]
```

### Running Hooks

**Automatically on commit:**

```bash
git commit -m "Your message"
# pre-commit runs automatically
```

**Manually:**

```bash
# Run all hooks on all files
pre-commit run --all-files

# Run specific hook
pre-commit run ruff --all-files

# Run on staged files only
pre-commit run
```

**Skip hooks temporarily:**

```bash
# Skip all hooks
git commit --no-verify

# Skip specific hook
SKIP=mypy git commit -m "Skip mypy for this commit"
```

### Updating Hooks

```bash
# Update all hooks to latest versions
pre-commit autoupdate

# Update specific repository
pre-commit autoupdate --repo https://github.com/astral-sh/ruff-pre-commit
```

---

## Editor Integration

### VS Code

**Install extensions:**

1. **Ruff:** `charliermarsh.ruff`
2. **Mypy Type Checker:** `ms-python.mypy-type-checker`

**Settings (`.vscode/settings.json`):**

```json
{
  "[python]": {
    "editor.formatOnSave": true,
    "editor.codeActionsOnSave": {
      "source.fixAll": "explicit",
      "source.organizeImports": "explicit"
    },
    "editor.defaultFormatter": "charliermarsh.ruff"
  },
  "ruff.lint.args": ["--config=pyproject.toml"],
  "ruff.format.args": ["--config=pyproject.toml"],
  "mypy-type-checker.args": ["--config-file=pyproject.toml"],
  "mypy-type-checker.severity": {
    "error": "Error",
    "note": "Information"
  }
}
```

**Keyboard shortcuts:**

- `Shift+Alt+F` - Format document (Ruff)
- `Ctrl+.` - Quick fix (Ruff auto-fix)

### PyCharm / IntelliJ IDEA

**Ruff integration:**

1. Go to **Settings** → **Tools** → **External Tools**
2. Add new tool:
   - **Name:** Ruff Format
   - **Program:** `ruff`
   - **Arguments:** `format $FilePath$`
   - **Working directory:** `$ProjectFileDir$`

3. Add another tool:
   - **Name:** Ruff Check
   - **Program:** `ruff`
   - **Arguments:** `check --fix $FilePath$`
   - **Working directory:** `$ProjectFileDir$`

**mypy integration:**

1. Install mypy plugin from marketplace
2. Configure in **Settings** → **mypy**
3. Set path to mypy executable
4. Enable "Run mypy on save"

**File watchers (auto-format on save):**

1. Go to **Settings** → **Tools** → **File Watchers**
2. Add Ruff file watcher:
   - **File type:** Python
   - **Scope:** Project Files
   - **Program:** `ruff`
   - **Arguments:** `format $FilePath$`

---

## CI/CD Integration

### GitHub Actions

**Complete workflow (`.github/workflows/quality.yml`):**

```yaml
name: Code Quality

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main, develop]

jobs:
  quality:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        python-version: ["3.10", "3.11", "3.12"]

    steps:
      - uses: actions/checkout@v4

      - name: Set up Python ${{ matrix.python-version }}
        uses: actions/setup-python@v5
        with:
          python-version: ${{ matrix.python-version }}

      - name: Install dependencies
        run: |
          python -m pip install --upgrade pip
          pip install ruff mypy bandit pytest

      - name: Cache pre-commit
        uses: actions/cache@v4
        with:
          path: ~/.cache/pre-commit
          key: pre-commit-${{ hashFiles('.pre-commit-config.yaml') }}

      - name: Run Ruff linter
        run: ruff check .

      - name: Run Ruff formatter check
        run: ruff format --check .

      - name: Run mypy type checker
        run: mypy .

      - name: Run Bandit security scanner
        run: bandit -r src/

      - name: Run tests
        run: pytest tests/
```

**Using pre-commit in CI:**

```yaml
steps:
  - uses: actions/checkout@v4
  - uses: actions/setup-python@v5
  - name: Install pre-commit
    run: pip install pre-commit
  - name: Run pre-commit
    run: pre-commit run --all-files
```

**Ruff-specific action:**

```yaml
steps:
  - uses: actions/checkout@v4
  - uses: astral-sh/ruff-action@v3
    with:
      args: check --output-format=github
```

### GitLab CI

```yaml
# .gitlab-ci.yml
stages:
  - quality
  - test

quality:
  stage: quality
  image: python:3.12
  script:
    - pip install ruff mypy bandit
    - ruff check .
    - ruff format --check .
    - mypy .
    - bandit -r src/
  cache:
    paths:
      - .cache/pre-commit
  only:
    - merge_requests
    - main
```

### Docker Integration

```dockerfile
# Dockerfile for CI
FROM python:3.12-slim

WORKDIR /app

# Install quality tools
RUN pip install --no-cache-dir ruff mypy bandit pre-commit

# Copy project files
COPY . .

# Run quality checks
RUN ruff check . && \
    ruff format --check . && \
    mypy . && \
    bandit -r src/
```

---

## Complete Configuration Examples

### Example 1: Simple Project

**pyproject.toml:**

```toml
[project]
name = "simple-project"
version = "0.1.0"
requires-python = ">=3.10"

[tool.ruff]
line-length = 88
target-version = "py310"

[tool.ruff.lint]
select = ["E", "F", "I"]
fixable = ["ALL"]

[tool.ruff.format]
quote-style = "double"

[tool.mypy]
python_version = "3.10"
warn_return_any = true
warn_unused_configs = true

[tool.bandit]
exclude_dirs = ["tests"]
```

**.pre-commit-config.yaml:**

```yaml
repos:
  - repo: https://github.com/astral-sh/ruff-pre-commit
    rev: v0.14.5
    hooks:
      - id: ruff
        args: [--fix]
      - id: ruff-format
```

### Example 2: Production Project

**pyproject.toml:**

```toml
[project]
name = "production-app"
version = "1.0.0"
requires-python = ">=3.12"
dependencies = [
    "fastapi>=0.100.0",
    "pydantic>=2.0.0",
]

[tool.ruff]
line-length = 100
target-version = "py312"
exclude = [
    ".git",
    ".venv",
    "__pycache__",
    "build",
    "dist",
    "migrations",
]

[tool.ruff.lint]
select = [
    "E",      # pycodestyle errors
    "F",      # Pyflakes
    "W",      # pycodestyle warnings
    "UP",     # pyupgrade
    "I",      # isort
    "B",      # flake8-bugbear
    "SIM",    # flake8-simplify
    "RET",    # flake8-return
    "C4",     # flake8-comprehensions
    "TID",    # flake8-tidy-imports
    "S",      # flake8-bandit security
]

fixable = ["ALL"]
unfixable = ["B"]

ignore = [
    "E501",   # Line too long (formatter handles)
    "S101",   # Use of assert (OK in tests)
]

[tool.ruff.lint.per-file-ignores]
"__init__.py" = ["F401", "F403"]
"tests/*" = ["S101", "S105", "S106"]
"migrations/*" = ["ALL"]

[tool.ruff.lint.isort]
known-first-party = ["app"]
force-single-line = false
lines-after-imports = 2

[tool.ruff.format]
quote-style = "double"
indent-style = "space"
skip-magic-trailing-comma = false
line-ending = "auto"
docstring-code-format = true
docstring-code-line-length = 80

[tool.mypy]
strict = true
python_version = "3.12"
warn_return_any = true
warn_unused_configs = true
disallow_untyped_defs = true

# Per-module overrides
[[tool.mypy.overrides]]
module = "tests.*"
disallow_untyped_defs = false

[[tool.mypy.overrides]]
module = "migrations.*"
ignore_errors = true

[tool.bandit]
exclude_dirs = ["tests", "venv", ".venv", "migrations"]
skips = ["B101"]

[tool.pytest.ini_options]
testpaths = ["tests"]
python_files = ["test_*.py"]
addopts = "-v --strict-markers"
```

**.pre-commit-config.yaml:**

```yaml
default_language_version:
  python: python3.12

repos:
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v5.0.0
    hooks:
      - id: trailing-whitespace
      - id: end-of-file-fixer
      - id: check-yaml
      - id: check-json
      - id: check-toml
      - id: check-merge-conflict
      - id: check-added-large-files
      - id: detect-private-key

  - repo: https://github.com/astral-sh/ruff-pre-commit
    rev: v0.14.5
    hooks:
      - id: ruff
        args: [--fix]
      - id: ruff-format

  - repo: https://github.com/pre-commit/mirrors-mypy
    rev: v1.18.2
    hooks:
      - id: mypy
        additional_dependencies:
          - types-requests
          - pydantic

  - repo: https://github.com/PyCQA/bandit
    rev: 1.7.10
    hooks:
      - id: bandit
        args: ["-c", "pyproject.toml"]
        additional_dependencies: ["bandit[toml]"]
```

---

## Workflow and Best Practices

### Development Workflow

**1. Local development:**

```bash
# Before committing
ruff check --fix .          # Fix linting issues
ruff format .               # Format code
mypy .                      # Type check
pytest tests/               # Run tests
```

**2. Pre-commit hooks (automatic):**

```bash
git add .
git commit -m "feat: Add new feature"
# pre-commit runs automatically:
# - Ruff linting with auto-fix
# - Ruff formatting
# - mypy type checking
# - Bandit security scanning
```

**3. CI/CD (automatic):**

- Push triggers GitHub Actions
- Runs all quality checks in CI
- Blocks merge if checks fail

### Incremental Adoption Strategy

**For existing projects without quality tools:**

#### Phase 1: Add Ruff (formatting only)

```toml
[tool.ruff.format]
quote-style = "double"
```

```bash
ruff format .
git add -A
git commit -m "style: Apply Ruff formatting"
```

#### Phase 2: Add basic linting

```toml
[tool.ruff.lint]
select = ["E", "F"]  # Start with basics
```

```bash
ruff check --fix .
# Fix remaining issues manually
git commit -m "style: Fix basic linting issues"
```

#### Phase 3: Expand rule set

```toml
[tool.ruff.lint]
select = ["E", "F", "I", "B", "SIM"]  # Add more rules gradually
```

#### Phase 4: Add type checking

```bash
pip install mypy
mypy --install-types
```

```toml
[tool.mypy]
check_untyped_defs = true  # Start lenient
```

#### Phase 5: Enable strict mode

```toml
[tool.mypy]
strict = true  # Full type safety
```

#### Phase 6: Add security scanning

```bash
pip install bandit
bandit -r src/
# Fix security issues
```

#### Phase 7: Automate with pre-commit

```bash
pip install pre-commit
pre-commit install
pre-commit run --all-files
```

### Best Practices

**1. Fix automatically when possible:**

```bash
# Let tools fix what they can
ruff check --fix .
ruff format .
```

**2. Use pre-commit hooks for enforcement:**

- Catches issues before they reach code review
- Ensures consistency across team
- Reduces CI failures

**3. Run in CI as safety net:**

- Pre-commit hooks can be skipped (`--no-verify`)
- CI provides final enforcement
- Catches issues from developers without hooks installed

**4. Configure once in pyproject.toml:**

- Single source of truth for all tools
- Easier to maintain than separate config files
- Better discoverability

**5. Start strict for new projects:**

```toml
[tool.mypy]
strict = true

[tool.ruff.lint]
select = ["ALL"]
ignore = ["D"]  # Skip docstrings initially
```

**6. Gradually tighten for legacy projects:**

- Start with basic rules
- Fix issues incrementally
- Add stricter rules over time
- Use per-file ignores for legacy code

**7. Document exceptions:**

```python
# Acceptable use of eval for safe DSL parsing
result = eval(expression)  # nosec B307
```

```toml
[tool.ruff.lint.per-file-ignores]
"legacy/old_module.py" = ["ALL"]  # TODO: Refactor legacy code
```

**8. Monitor and iterate:**

- Review suppression comments periodically
- Remove obsolete ignores
- Update rules as project matures
- Keep tools updated: `pre-commit autoupdate`

### Common Pitfalls

**❌ Don't:**

- Run formatters before linters (linter fixes may need reformatting)
- Ignore errors without understanding them
- Disable all checks for a file without justification
- Commit without running quality checks
- Mix configuration formats (use pyproject.toml consistently)

**✅ Do:**

- Run in order: `ruff check --fix` → `ruff format`
- Document why you're ignoring specific rules
- Use per-file ignores sparingly and temporarily
- Set up pre-commit hooks from day one
- Centralize configuration in pyproject.toml

### Performance Tips

**1. Run checks in parallel in CI:**

```yaml
jobs:
  ruff:
    runs-on: ubuntu-latest
    steps:
      - run: ruff check .
  mypy:
    runs-on: ubuntu-latest
    steps:
      - run: mypy .
```

**2. Cache tool environments:**

```yaml
- uses: actions/cache@v4
  with:
    path: ~/.cache/pre-commit
    key: pre-commit-${{ hashFiles('.pre-commit-config.yaml') }}
```

**3. Use Ruff's speed to your advantage:**

- Ruff is fast enough for real-time linting in editors
- Run on every save without performance impact
- Include in pre-commit hooks without delay

**4. Limit mypy scope for faster feedback:**

```bash
# Type check only changed files during development
mypy $(git diff --name-only --diff-filter=d "*.py")
```

---

## Summary

**Modern Python quality stack (2025):**

1. **Ruff** - All-in-one linter and formatter (replaces Flake8, Black, isort, pyupgrade, autoflake)
2. **mypy** - Static type checker for type safety
3. **Bandit** - Security vulnerability scanner
4. **pre-commit** - Automation framework for git hooks

**Key advantages:**

- **Speed:** 10-100x faster than legacy tools
- **Simplicity:** Single tool (Ruff) replaces multiple
- **Consistency:** One configuration file (pyproject.toml)
- **Automation:** Pre-commit hooks + CI/CD enforcement

**Getting started:**

```bash
# Install tools
pip install ruff mypy bandit pre-commit

# Create config (see examples above)
# pyproject.toml
# .pre-commit-config.yaml

# Install pre-commit hooks
pre-commit install

# Run initial validation
pre-commit run --all-files
```

**Resources:**

- Ruff docs: <https://docs.astral.sh/ruff/>
- mypy docs: <https://mypy.readthedocs.io/>
- Bandit docs: <https://bandit.readthedocs.io/>
- pre-commit docs: <https://pre-commit.com/>

---

**Last Verified:** 2025-11-25
