---
name: python
description: Adaptive Python development guide with tiered complexity levels (Minimal/Standard/Full). Automatically selects appropriate guidance based on project context - from simple scripts (just clean Python code) to full production systems (complete tooling ecosystem). Covers modern conventions, testing, tooling, security, and best practices. Use when writing Python code, converting scripts, setting up projects, or building production systems. Keywords: PEP-8, Ruff, pytest, mypy, simple scripts, project structure, PyPI, packaging, type hints, clean code
allowed-tools: Read, Bash, Glob, Grep
---

# Python Development Skill

Comprehensive guide to modern Python development covering conventions, testing, tooling, security, performance, and ecosystem best practices (2024-2025 standards).

## Tier 2 Quick Start

**For multi-file projects, team collaboration, and maintained code:**

```bash
# Install Python 3.12 and uv (see Installation guides)
# Windows: winget install Python.Python.3.12 && winget install astral-sh.uv
# macOS: brew install python@3.13 uv
# Linux: apt install python3.13 && curl -LsSf https://astral.sh/uv/install.sh | sh

# Create new project with modern structure
uv init my-project
cd my-project

# Add dependencies
uv add requests httpx pydantic

# Add development dependencies
uv add --dev pytest pytest-cov ruff mypy

# Set up code quality (create pyproject.toml config - see assets/pyproject-toml-template.toml)
# Configure Ruff, mypy, pytest

# Write tests (pytest)
# tests/test_example.py - mirror src/ structure

# Run quality checks
uv run ruff check .          # Linting
uv run ruff format .         # Formatting
uv run mypy .                # Type checking
uv run pytest                # Run tests
uv run pytest --cov          # With coverage
```

## When to Use This Skill

Invoke this skill when you need guidance on:

- **Installation & Setup**: Installing Python 3.12/3.14, uv, setting up development environment
- **Code Style**: Following PEP-8, configuring Ruff/Black, naming conventions
- **Project Structure**: Organizing code with src/ layout, imports, package structure
- **Dependency Management**: Using uv, Poetry, pip, virtual environments, pyproject.toml
- **Testing**: Writing pytest tests, fixtures, parametrization, coverage, mocking
- **Type Hints**: Modern typing patterns, mypy configuration, protocols, generics
- **Code Quality**: Setting up Ruff, mypy, Bandit, pre-commit hooks, CI/CD
- **Async Programming**: asyncio patterns, async/await, TaskGroup, structured concurrency
- **Security**: OWASP best practices, input validation, dependency scanning
- **Performance**: Profiling, optimization patterns, Cython
- **Packaging**: pyproject.toml, PyPI publishing, versioning, distribution
- **Common Libraries**: Standard library essentials, ecosystem overview
- **Documentation**: Docstrings (PEP-257), Sphinx, documentation generation

## Overview

This skill provides modern Python development guidance aligned with current best practices (2024-2025):

**Core Standards:**

- **Style**: PEP-8 (enforced via Ruff)
- **Type Hints**: PEP-484, PEP-526, modern syntax (PEP-604: `str | None`)
- **Packaging**: PEP-517, PEP-518 (pyproject.toml)
- **Docstrings**: PEP-257
- **Testing**: pytest (industry standard)
- **Dependency Management**: uv (fastest) or Poetry (feature-rich)

**Modern Tooling (2024-2025):**

- **Linter/Formatter**: Ruff (replaces flake8, isort, optionally Black)
- **Type Checker**: mypy with strict mode
- **Test Framework**: pytest
- **Dependency Manager**: uv or Poetry
- **Security Scanner**: Bandit + pip-audit
- **Project Config**: pyproject.toml (universal)

**Project Structure:**

- src/ layout (modern standard, not flat layout)
- Absolute imports preferred over relative
- Tests mirror src/ structure
- pyproject.toml for all configuration

**Official Sources:**
All guidance backed by official Python documentation, PEPs, and tool documentation:

- docs.python.org
- peps.python.org
- docs.astral.sh/ruff
- docs.astral.sh/uv
- mypy-lang.org
- docs.pytest.org

## Quick Tier Selection

**Choose your complexity level:**

### 🎯 Tier 1: Minimal (Simple Scripts)

→ Single-file utilities, converting scripts, one-off automation
→ Just Python code - no tooling overhead
→ [Jump to Minimal Guidance](#tier-1-minimal-simple-scripts)

### 📦 Tier 2: Standard (Organized Projects)

→ Multi-file modules, team projects, maintained code
→ Modern project structure + testing
→ [Jump to Standard Guidance](#tier-2-standard-organized-projects)

### 🚀 Tier 3: Full (Production Systems)

→ PyPI packages, enterprise systems, production deployments
→ Complete tooling ecosystem
→ [Jump to Full Guidance](#tier-3-full-production-systems)

**Not sure?** Default to Tier 2 (Standard) - it covers most use cases.

---

## Tier 1: Minimal (Simple Scripts)

**For:** Single-file utilities, script conversions, and simple automation.

### Setup

Just Python 3.12+ - no additional tooling required:

- ✅ No uv, no virtual environment needed
- ✅ No pyproject.toml, no src/ layout
- ✅ Optional: Install Ruff for quick linting (`pip install ruff`)

### Code Standards

Follow these simple principles:

- **PEP-8 naming**: `snake_case` for functions/variables, `PascalCase` for classes
- **Type hints**: Add for clarity (helps readers understand your code)
- **Docstrings**: Simple descriptions of what functions do
- **pathlib**: Use `pathlib.Path` for file operations (not `os.path`)
- **Built-ins**: Use Python's built-in `json`, `datetime`, `sys` modules

### Example: Simple Logging Script

```python
#!/usr/bin/env python3
"""Simple logging utility - converts event to JSON."""

import json
import sys
from datetime import datetime, timezone
from pathlib import Path


def log_event(event_name: str, data: dict) -> None:
    """
    Log an event to daily JSONL file.

    Args:
        event_name: Name of the event
        data: Event data to log
    """
    log_dir = Path(__file__).parent / "logs"
    log_dir.mkdir(exist_ok=True)

    now = datetime.now(timezone.utc)
    log_file = log_dir / f"{now:%Y-%m-%d}.jsonl"

    entry = {
        "timestamp": now.isoformat(),
        "event": event_name,
        "data": data
    }

    with open(log_file, "a", encoding="utf-8") as f:
        f.write(json.dumps(entry) + "\n")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: script.py <event_name>", file=sys.stderr)
        sys.exit(1)
    event_name = sys.argv[1]
    data = json.loads(sys.stdin.read())
    log_event(event_name, data)
```

### Optional: Quick Linting

If you want to check your code style:

```bash
# Install Ruff (optional)
pip install ruff

# Check code
ruff check script.py

# Format code
ruff format script.py
```

### When to Upgrade to Tier 2

Consider upgrading to Tier 2 (Standard) when:

- ✅ Script grows to 3+ files
- ✅ Multiple people working on code
- ✅ Need automated testing
- ✅ Managing external dependencies
- ✅ Code will be maintained long-term

---

## Tier 2: Standard (Organized Projects)

**For:** Multi-file modules, team projects, and maintained code.

Modern Python project setup with proper structure, testing, and quality tools.

### Installation

Install Python 3.12+ and uv (modern dependency manager). See platform-specific guides:

- [Installation Overview](references/installation/overview.md) - Concepts and version policy
- [Windows Installation](references/installation/windows.md) - WinGet, Python Launcher
- [macOS Installation](references/installation/macos.md) - Homebrew installation
- [Linux Installation](references/installation/linux.md) - apt/dnf or build from source

### Project Setup and Organization

**Conventions and Style** - Follow PEP-8 with Ruff for linting and formatting:

- See [Conventions and Style Guide](references/conventions-and-style.md)

**Project Structure** - Use modern src/ layout for proper packaging:

- See [Project Structure Guide](references/project-structure.md)

**Dependency Management** - Choose between uv (fastest), Poetry (feature-rich), or pip+venv:

- See [Dependency Management Guide](references/dependency-management.md)

### Testing and Quality

**Testing** - Use pytest with fixtures, parametrization, and coverage:

- See [Testing Methodology Guide](references/testing-methodology.md)

**Type Hints** - Modern typing with mypy, protocols, and generics:

- See [Type Hints Guide](references/type-hints.md)

**Code Quality** - Set up Ruff, mypy, Bandit, and pre-commit hooks:

- See [Code Quality Tools Guide](references/code-quality-tools.md)

### Advanced Development

**Async Programming** - asyncio patterns, TaskGroup, structured concurrency:

- See [Async Patterns Guide](references/async-patterns.md)

**Security** - OWASP best practices, input validation, secrets management:

- See [Security Best Practices Guide](references/security-best-practices.md)

**Performance** - Profiling, optimization patterns, memory efficiency:

- See [Performance Optimization Guide](references/performance-optimization.md)

**Packaging** - Publish to PyPI with pyproject.toml and semantic versioning:

- See [Packaging and Distribution Guide](references/packaging-distribution.md)

**Libraries** - Standard library essentials and ecosystem overview:

- See [Common Libraries Guide](references/common-libraries.md)

**Documentation** - PEP-257 docstrings, Sphinx, ReadTheDocs:

- See [Docstrings and Documentation Guide](references/docstrings-documentation.md)

---

## Tier 3: Full (Production Systems)

**For:** PyPI packages, enterprise systems, and production deployments.

Everything in Tier 2 (Standard) PLUS:

### Security & Quality

- **Security scanning**: Bandit for code security, pip-audit for dependency vulnerabilities
- **Pre-commit hooks**: Automated checks before every commit
- **Comprehensive type coverage**: mypy strict mode across entire codebase
- **Code coverage enforcement**: Minimum coverage requirements in CI/CD

### Distribution

- **PyPI packaging**: Build and publish Python packages to PyPI
- **Semantic versioning**: Follow semver for version management
- **Binary distributions**: Create wheels for faster installation
- **Multi-platform support**: Test and build for Windows/macOS/Linux

### CI/CD

- **GitHub Actions / GitLab CI**: Automated testing on every push
- **Multi-version testing**: Test against Python 3.12, 3.13, 3.14
- **Coverage tracking**: Automated coverage reports and enforcement
- **Release automation**: Automatic PyPI publishing on tags

### Documentation

- **Sphinx**: Generate API documentation from docstrings
- **ReadTheDocs**: Host documentation with versioning
- **Comprehensive docstrings**: Google or NumPy style for all public APIs
- **Examples and tutorials**: User-facing documentation with examples

### Detailed Guides

See these reference files for comprehensive production guidance:

- [Security Best Practices](references/security-best-practices.md) - OWASP, Bandit, pip-audit
- [Packaging and Distribution](references/packaging-distribution.md) - PyPI publishing, versioning
- [Code Quality Tools](references/code-quality-tools.md) - Pre-commit hooks, CI/CD setup
- [Docstrings and Documentation](references/docstrings-documentation.md) - Sphinx, ReadTheDocs

---

## Reference Files

All detailed guidance is in the references/ directory:

**Installation:**

- [Installation Overview](references/installation/overview.md) - Platform-independent concepts
- [Windows Installation](references/installation/windows.md) - Python + uv on Windows
- [macOS Installation](references/installation/macos.md) - Python + uv on macOS
- [Linux Installation](references/installation/linux.md) - Python + uv on Linux

**Core Development:**

- [Conventions and Style](references/conventions-and-style.md) - PEP-8, Ruff, Black, naming
- [Project Structure](references/project-structure.md) - src/ layout, imports, organization
- [Dependency Management](references/dependency-management.md) - uv, Poetry, pip, venv
- [Testing Methodology](references/testing-methodology.md) - pytest, fixtures, coverage
- [Type Hints](references/type-hints.md) - Modern typing, mypy, protocols
- [Code Quality Tools](references/code-quality-tools.md) - Ruff, mypy, Bandit setup

**Advanced Topics:**

- [Async Patterns](references/async-patterns.md) - asyncio, TaskGroup, structured concurrency
- [Security Best Practices](references/security-best-practices.md) - OWASP, validation, scanning
- [Performance Optimization](references/performance-optimization.md) - Profiling, patterns, Cython
- [Packaging and Distribution](references/packaging-distribution.md) - pyproject.toml, PyPI, versioning
- [Common Libraries](references/common-libraries.md) - Standard library + ecosystem essentials
- [Docstrings and Documentation](references/docstrings-documentation.md) - PEP-257, Sphinx

## Assets

**Template Files:**

- [pyproject.toml Template](assets/pyproject-toml-template.toml) - Modern project configuration template

## Testing and Evaluation

This skill includes formal evaluation scenarios to validate effectiveness:

- See [Skill Evaluation Scenarios](references/skill-evaluation-scenarios.md) for test cases covering:
  - Minimal Tier (simple scripts)
  - Standard Tier (new projects, code quality tools)
  - Full Tier (production systems)
  - Alternative workflows (Poetry vs uv)
  - Success criteria and testing methodology

## Related Skills

- **git-commit**: Git commit workflow (complements Python project workflow)
- **git-config**: Git configuration (Python projects use Git)
- **code-quality:markdown-linting**: Markdown linting via plugin (Python projects have READMEs)

## Version History

- **1.1.2** (2025-11-25): Comprehensive improvements
  - Fixed deprecated `datetime.utcnow()` in example code (use `datetime.now(timezone.utc)`)
  - Added Python 3.13 coverage (was missing between 3.12 and 3.14)
  - Updated PEP URLs to modern format (peps.python.org instead of python.org/dev/peps/)
  - Added UTF-8 encoding to file open in example code
  - Added error handling for missing CLI arguments in example
- **1.1.1** (2025-11-25): Version audit update
  - Updated tool version references (Ruff 0.14.x, mypy 1.18.x, pytest 9.x)
  - Verified all reference file links exist and are correct
  - Validated YAML frontmatter against official requirements
- **1.1.0** (2025-11-18): Adaptive tiered guidance
  - Added three-tier complexity system (Minimal/Standard/Full)
  - Tier 1: Minimal guidance for simple scripts (no tooling overhead)
  - Tier 2: Standard guidance for organized projects (original Quick Start)
  - Tier 3: Full guidance for production systems (comprehensive tooling)
  - Context-aware skill automatically selects appropriate tier based on query
  - Prevents "big bang" overengineering for simple scenarios
- **1.0.0** (2025-11-17): Initial release
  - Comprehensive modern Python guidance (2024-2025 standards)
  - Migrated installation docs from `docs/python/`
  - Added 12 detailed reference files
  - Modern tooling: Ruff, uv, pytest, mypy
  - pyproject.toml template

## Official Documentation

**Python:**

- Official Python Documentation: <https://docs.python.org/>
- Python 3.12 What's New: <https://docs.python.org/3.12/whatsnew/3.12.html>
- Python 3.13 What's New: <https://docs.python.org/3.13/whatsnew/3.13.html>
- Python 3.14 What's New: <https://docs.python.org/3.14/whatsnew/3.14.html>
- Python Enhancement Proposals (PEPs): <https://peps.python.org/>

**Tools:**

- uv Documentation: <https://docs.astral.sh/uv/>
- Ruff Documentation: <https://docs.astral.sh/ruff/>
- mypy Documentation: <https://mypy-lang.org/>
- pytest Documentation: <https://docs.pytest.org/>
- Poetry Documentation: <https://python-poetry.org/docs/>

**PEPs (Python Enhancement Proposals):**

- PEP-8 (Style Guide): <https://peps.python.org/pep-0008/>
- PEP-257 (Docstring Conventions): <https://peps.python.org/pep-0257/>
- PEP-484 (Type Hints): <https://peps.python.org/pep-0484/>
- PEP-517 (Build System): <https://peps.python.org/pep-0517/>
- PEP-518 (pyproject.toml): <https://peps.python.org/pep-0518/>
- PEP-604 (Union Types with |): <https://peps.python.org/pep-0604/>

## Last Updated

**Date:** 2025-11-28
**Model:** claude-opus-4-5-20251101
