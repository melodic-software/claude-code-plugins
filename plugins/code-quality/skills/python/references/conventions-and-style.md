# Python Conventions and Style Guide

This comprehensive guide covers Python code style conventions, naming patterns, formatting rules, and modern tooling for maintaining consistent, readable Python code. All guidance is based on official PEP standards and current best practices as of 2024-2025.

**Official Sources:**

- **PEP 8**: <https://peps.python.org/pep-0008/> (Style Guide for Python Code)
- **Ruff**: <https://docs.astral.sh/ruff/> (Modern linter and formatter)
- **Black**: <https://black.readthedocs.io/> (Opinionated code formatter)
- **PEP 257**: <https://peps.python.org/pep-0257/> (Docstring Conventions)

## Table of Contents

- [Why Code Style Matters](#why-code-style-matters)
- [PEP 8 Overview](#pep-8-overview)
- [Naming Conventions](#naming-conventions)
- [Code Formatting](#code-formatting)
- [Import Organization](#import-organization)
- [Modern Tooling (2024-2025)](#modern-tooling-2024-2025)
- [Configuration Examples](#configuration-examples)
- [Comments and Docstrings](#comments-and-docstrings)
- [Best Practices](#best-practices)
- [Line Length Trade-offs](#line-length-trade-offs)
- [Quick Reference Checklist](#quick-reference-checklist)
- [Migration Strategy](#migration-strategy)
- [Official Documentation](#official-documentation)
- [Summary](#summary)

## Why Code Style Matters

Code is read far more often than it is written. Consistent style across Python code improves readability, maintainability, and team collaboration. As PEP 20 (The Zen of Python) states: "Readability counts."

**Key Benefits:**

- **Consistency**: Makes code predictable and easier to navigate
- **Reduced cognitive load**: Familiar patterns allow focus on logic, not formatting
- **Better collaboration**: Team members can understand each other's code faster
- **Automated tooling**: Formatters and linters enforce consistency automatically
- **Fewer debates**: Established conventions reduce bike-shedding

## PEP 8 Overview

PEP 8 is the official style guide for Python code in the standard library and is widely adopted across the Python ecosystem. It provides conventions for code layout, naming, imports, comments, and more.

**Core Principle** (from PEP 8):

> "A Foolish Consistency is the Hobgoblin of Little Minds"

This means:

- Consistency with this style guide is important
- Consistency within a project is more important
- Consistency within one module or function is most important
- Know when to be inconsistent - sometimes guidelines don't apply

**When to Ignore PEP 8:**

1. Applying the guideline makes code less readable
2. To be consistent with surrounding code (especially legacy code)
3. Code predates the guideline with no reason to modify
4. Need compatibility with older Python versions

## Naming Conventions

### Functions and Variables: snake_case

Use lowercase with underscores separating words:

```python
# Correct
def calculate_total_price(items):
    total_sum = 0
    for item in items:
        total_sum += item.price
    return total_sum

user_count = 42
is_valid = True
max_retries = 3
```

```python
# Wrong
def calculateTotalPrice(items):  # camelCase - avoid
    totalSum = 0  # camelCase - avoid
    return totalSum

def CalculateTotalPrice(items):  # PascalCase - reserved for classes
    pass
```

### Classes: PascalCase (CapWords)

Use capitalized words without underscores:

```python
# Correct
class ShoppingCart:
    pass

class HTTPServerError:  # Acronyms: capitalize all letters
    pass

class XMLParser:
    pass
```

```python
# Wrong
class shopping_cart:  # snake_case - reserved for functions/variables
    pass

class HttpServerError:  # Mixed case acronyms - avoid
    pass
```

### Constants: UPPER_CASE

Module-level constants use all capitals with underscores:

```python
# Correct
MAX_OVERFLOW = 1000
DEFAULT_TIMEOUT = 30
API_BASE_URL = "https://api.example.com"
SUPPORTED_FORMATS = ["json", "xml", "yaml"]
```

```python
# Wrong
max_overflow = 1000  # Looks like a variable
MaxOverflow = 1000   # Looks like a class
```

### Private/Internal: _leading_underscore

Use single leading underscore for internal/private use:

```python
# Correct
class MyClass:
    def __init__(self):
        self._internal_state = {}  # Internal instance variable

    def _helper_method(self):  # Internal method
        pass

    def public_method(self):  # Public method
        return self._helper_method()

_module_private = "not exported"  # Module-level private
```

**Name Mangling with Double Underscores:**

```python
class Foo:
    def __init__(self):
        self.__private = "truly private"  # Name mangled to _Foo__private
        self._internal = "weak private"   # Not mangled
```

Use double underscores sparingly - mainly to avoid name conflicts in inheritance.

### Module and Package Names: snake_case

Modules should have short, lowercase names with underscores if needed:

```python
# Correct module names
utils.py
http_client.py
data_processor.py

# Package structure
my_package/
    __init__.py
    core.py
    utils.py
```

```python
# Wrong module names
Utils.py          # PascalCase - avoid
httpClient.py     # camelCase - avoid
HTTP-Client.py    # Hyphens invalid in Python
```

**Note**: Package names discourage underscores (short, all-lowercase preferred), but module names can use underscores for readability.

### Type Variables: Short CapWords

```python
from typing import TypeVar

T = TypeVar('T')  # Generic type
AnyStr = TypeVar('AnyStr', str, bytes)
Num = TypeVar('Num', int, float)

# Covariant/contravariant
VT_co = TypeVar('VT_co', covariant=True)
KT_contra = TypeVar('KT_contra', contravariant=True)
```

### Exception Names: PascalCase + "Error"

```python
# Correct
class ValidationError(Exception):
    pass

class DatabaseConnectionError(Exception):
    pass

class HTTPError(Exception):  # For actual errors
    pass
```

### Method Arguments

```python
class MyClass:
    def instance_method(self, arg):  # Always 'self' for instance methods
        pass

    @classmethod
    def class_method(cls, arg):  # Always 'cls' for class methods
        pass

    @staticmethod
    def static_method(arg):  # No special first argument
        pass
```

### Names to Avoid

Never use single-character names that are visually confusing:

```python
# Wrong - visually confusing
l = 5   # Lowercase 'el' looks like '1'
O = 0   # Uppercase 'oh' looks like '0'
I = 1   # Uppercase 'eye' looks like '1'

# Correct alternatives
line = 5
output = 0
index = 1
```

## Code Formatting

### Line Length

**PEP 8 Standard**: 79 characters for code, 72 for comments/docstrings

**Modern Practice**: Many teams use 88 (Black default) or 100 (Ruff default)

```toml
# PEP 8 strict
[tool.ruff]
line-length = 79

# Black default (recommended)
[tool.ruff]
line-length = 88

# Ruff default (alternative)
[tool.ruff]
line-length = 100
```

**Rationale for longer lines**: Modern displays accommodate wider code, reducing line breaks improves readability for many expressions.

### Indentation: 4 Spaces

Always use 4 spaces per indentation level. Never use tabs (unless maintaining tab-indented legacy code).

```python
# Correct
def long_function_name(
        var_one, var_two, var_three,
        var_four):
    print(var_one)

# Hanging indent
foo = long_function_name(
    var_one, var_two,
    var_three, var_four)

# Aligned with opening delimiter
foo = long_function_name(var_one, var_two,
                         var_three, var_four)
```

```python
# Wrong - mixing tabs and spaces
def function():
 print("tab indented")  # Python 3 disallows mixing
    print("space indented")
```

### Blank Lines

```python
# Two blank lines before top-level functions/classes
import os


def top_level_function():
    pass


class TopLevelClass:
    # One blank line between methods
    def method_one(self):
        pass

    def method_two(self):
        pass


def another_function():
    pass
```

### Whitespace in Expressions

```python
# Correct - no extra whitespace
spam(ham[1], {eggs: 2})
foo = (0,)
if x == 4: print(x, y); x, y = y, x

# Slices - colon acts like binary operator
ham[1:9], ham[1:9:3], ham[:9:3], ham[1::3]
ham[lower:upper], ham[lower+offset : upper+offset]

# Function calls
spam(1)
dct['key'] = lst[index]

# Assignments - one space on each side
x = 1
y = 2
long_variable = 3

# Operators - surround with single space
i = i + 1
submitted += 1
x = x*2 - 1  # Can group by precedence
hypot2 = x*x + y*y
c = (a+b) * (a-b)
```

```python
# Wrong - extraneous whitespace
spam( ham[ 1 ], { eggs: 2 } )
bar = (0, )
if x == 4 : print(x , y) ; x , y = y , x

ham[lower + offset:upper + offset]  # No space around slice colon
spam (1)  # Space before function call parens
dct ['key'] = lst [index]  # Space before brackets

# Wrong alignment
x             = 1
y             = 2
long_variable = 3
```

### String Quotes

**PEP 8**: No preference between single (`'`) and double (`"`) quotes. Pick one and be consistent.

**For Triple-Quoted Strings**: Always use double quotes (`"""`) to be consistent with PEP 257 docstring conventions.

```python
# Consistent single quotes
message = 'Hello, world!'
name = 'Alice'

# Or consistent double quotes
message = "Hello, world!"
name = "Alice"

# Use the other quote to avoid backslashes
text = "It's a beautiful day"  # Preferred over 'It\'s a beautiful day'
html = '<a href="link">Click</a>'  # Preferred over "<a href=\"link\">Click</a>"

# Triple-quoted strings: always double quotes
def function():
    """This is a docstring.

    Always use double quotes for docstrings.
    """
    pass
```

### Trailing Commas

Useful for version control (reduces diff noise) and future extensibility:

```python
# Single-element tuple - comma required
FILES = ('setup.cfg',)

# Multi-line collections - trailing comma recommended
FILES = [
    'setup.cfg',
    'tox.ini',
    'pytest.ini',
]

initialize(
    FILES,
    error=True,
    verbose=True,
)
```

```python
# Wrong
FILES = 'setup.cfg',  # Unclear without parentheses
FILES = ['setup.cfg', 'tox.ini',]  # Trailing comma on same line as bracket
```

## Import Organization

Imports should be grouped in the following order with blank lines between groups:

1. Standard library imports
2. Related third-party imports
3. Local application/library specific imports

```python
# Correct
import os
import sys
from pathlib import Path

import requests
from pydantic import BaseModel
import numpy as np

from my_package.utils import helper
from my_package.core import processor
```

### Import Style

```python
# Correct - separate lines for different modules
import os
import sys

# Correct - multiple imports from same module
from subprocess import Popen, PIPE

# Correct - absolute imports (preferred)
import mypkg.sibling
from mypkg import sibling
from mypkg.sibling import example

# Correct - explicit relative imports (acceptable in complex packages)
from . import sibling
from .sibling import example
```

```python
# Wrong - multiple modules on one line
import sys, os

# Wrong - wildcard imports (confusing namespace)
from module import *  # Avoid except for re-publishing interfaces
```

### Module-Level Dunders

Place after docstring, before imports (except `__future__`):

```python
"""This is the example module.

This module does stuff.
"""

from __future__ import annotations  # __future__ comes first

__all__ = ['public_function', 'PublicClass']
__version__ = '0.1.0'
__author__ = 'Your Name'

import os
import sys
```

## Modern Tooling (2024-2025)

### Ruff (Recommended - All-in-One Solution)

**Ruff** is an extremely fast Python linter and formatter written in Rust. It replaces Flake8, isort, Black (optionally), and dozens of plugins.

**Why Ruff?**

- **Speed**: 10-100x faster than alternatives (written in Rust)
- **Comprehensive**: Replaces multiple tools with one
- **Active development**: Rapidly improving and adding features
- **Black-compatible**: Can format like Black or use its own style
- **Extensive rules**: Supports 700+ linting rules from many sources

**Installation:**

```bash
pip install ruff
# or
uv pip install ruff
```

**Basic Usage:**

```bash
# Lint code
ruff check .

# Lint and auto-fix
ruff check --fix .

# Format code
ruff format .

# Combined workflow
ruff check --fix . && ruff format .
```

**Configuration (pyproject.toml):**

```toml
[tool.ruff]
# Line length: 100 is Ruff default, 88 matches Black
line-length = 100
target-version = "py312"

[tool.ruff.lint]
# Select rules: E (pycodestyle errors), F (Pyflakes), I (isort), N (naming), etc.
select = [
    "E",      # pycodestyle errors
    "F",      # Pyflakes
    "UP",     # pyupgrade
    "B",      # flake8-bugbear
    "SIM",    # flake8-simplify
    "I",      # isort
    "N",      # pep8-naming
    "W",      # pycodestyle warnings
    "C4",     # flake8-comprehensions
]

# Ignore specific rules
ignore = [
    "E501",   # Line too long (formatter handles this)
]

# Allow fixes for all enabled rules (when `--fix` is provided)
fixable = ["ALL"]
unfixable = []

# Per-file ignores
[tool.ruff.lint.per-file-ignores]
"__init__.py" = ["F401"]  # Unused imports OK in __init__.py
"tests/**/*" = ["S101"]   # Assert statements OK in tests

[tool.ruff.format]
# Ruff format configuration
quote-style = "double"
indent-style = "space"
skip-magic-trailing-comma = false
line-ending = "auto"

# Enable docstring code formatting
docstring-code-format = true
```

**Alternative: ruff.toml (Standalone Configuration):**

```toml
# Same options as pyproject.toml but without [tool.ruff] prefix
line-length = 100
target-version = "py312"

[lint]
select = ["E", "F", "I", "N", "W", "UP", "B", "C4"]
ignore = ["E501"]

[format]
quote-style = "double"
indent-style = "space"
```

### Black (Alternative Formatter)

**Black** is an opinionated Python code formatter with minimal configuration.

**Philosophy**: "Any color you like, as long as it's black." Minimal options to avoid debates.

**When to Use Black:**

- You want maximum opinionation (zero configuration)
- Your team prefers Black's specific style choices
- You're not using Ruff format

**Installation:**

```bash
pip install black
```

**Usage:**

```bash
# Format files
black .

# Check without formatting
black --check .

# Show diff
black --diff .
```

**Configuration (pyproject.toml):**

```toml
[tool.black]
line-length = 88  # Black's signature line length
target-version = ['py312']
include = '\.pyi?$'
extend-exclude = '''
/(
  # Directories
  \.eggs
  | \.git
  | \.hg
  | \.mypy_cache
  | \.tox
  | \.venv
  | _build
  | buck-out
  | build
  | dist
)/
'''
```

**Black-compatible Ruff Configuration:**

If you want Ruff format to match Black exactly:

```toml
[tool.ruff]
line-length = 88  # Match Black

[tool.ruff.format]
quote-style = "double"
indent-style = "space"
skip-magic-trailing-comma = false
line-ending = "auto"
```

### isort (Import Sorting - Integrated into Ruff)

**isort** sorts imports automatically. **Ruff includes isort functionality**, so standalone isort is optional.

**Using isort via Ruff (Recommended):**

```toml
[tool.ruff.lint]
select = ["I"]  # Enable isort rules

[tool.ruff.lint.isort]
known-first-party = ["my_package"]
force-single-line = false
lines-after-imports = 2
```

**Standalone isort (if not using Ruff):**

```bash
pip install isort

# Sort imports
isort .

# Check without sorting
isort --check-only .
```

**Configuration (pyproject.toml):**

```toml
[tool.isort]
profile = "black"  # Black-compatible settings
line_length = 88
multi_line_output = 3
include_trailing_comma = true
force_grid_wrap = 0
use_parentheses = true
ensure_newline_before_comments = true
```

### Recommended Tool Combinations

#### Option 1: Ruff Only (Simplest)

```bash
# Install
pip install ruff

# Usage
ruff check --fix .
ruff format .
```

Advantages: Single tool, fastest, simplest configuration.

#### Option 2: Ruff (Linter) + Black (Formatter)

```bash
# Install
pip install ruff black

# Usage
ruff check --fix .
black .
```

Advantages: Black's specific formatting style, Ruff's fast linting.

#### Option 3: Full Traditional Stack (Not Recommended for New Projects)

```bash
# Install
pip install flake8 black isort mypy

# Usage (requires multiple commands)
isort .
black .
flake8 .
mypy .
```

Disadvantages: Slower, more configuration, multiple tools to manage.

## Configuration Examples

### Comprehensive Ruff Configuration

```toml
[tool.ruff]
# Target Python 3.12+
target-version = "py312"

# Line length: 100 (Ruff default) or 88 (Black-compatible)
line-length = 100

# Exclude common directories
exclude = [
    ".bzr",
    ".direnv",
    ".eggs",
    ".git",
    ".git-rewrite",
    ".hg",
    ".ipynb_checkpoints",
    ".mypy_cache",
    ".nox",
    ".pants.d",
    ".pyenv",
    ".pytest_cache",
    ".pytype",
    ".ruff_cache",
    ".svn",
    ".tox",
    ".venv",
    ".vscode",
    "__pypackages__",
    "_build",
    "buck-out",
    "build",
    "dist",
    "node_modules",
    "site-packages",
    "venv",
]

[tool.ruff.lint]
# Enable rule categories
select = [
    "E",      # pycodestyle errors
    "W",      # pycodestyle warnings
    "F",      # Pyflakes
    "I",      # isort
    "N",      # pep8-naming
    "UP",     # pyupgrade
    "B",      # flake8-bugbear
    "C4",     # flake8-comprehensions
    "SIM",    # flake8-simplify
    "TCH",    # flake8-type-checking
    "TID",    # flake8-tidy-imports
    "RUF",    # Ruff-specific rules
]

# Ignore specific rules
ignore = [
    "E501",   # Line too long (formatter handles this)
    "B008",   # Do not perform function call in argument defaults (FastAPI uses this)
]

# Allow auto-fix for all enabled rules
fixable = ["ALL"]
unfixable = []

# Allow unused variables when underscore-prefixed
dummy-variable-rgx = "^(_+|(_+[a-zA-Z0-9_]*[a-zA-Z0-9]+?))$"

[tool.ruff.lint.per-file-ignores]
# Ignore import violations in __init__.py
"__init__.py" = ["F401", "F403"]
# Ignore assert statements in tests
"tests/**/*" = ["S101"]

[tool.ruff.lint.isort]
# isort configuration
known-first-party = ["my_package"]
section-order = [
    "future",
    "standard-library",
    "third-party",
    "first-party",
    "local-folder"
]

[tool.ruff.lint.pep8-naming]
# Allow certain naming patterns
classmethod-decorators = [
    "classmethod",
    "pydantic.validator",
    "pydantic.root_validator",
]

[tool.ruff.format]
# Formatter settings
quote-style = "double"
indent-style = "space"
skip-magic-trailing-comma = false
line-ending = "auto"

# Enable code formatting in docstrings
docstring-code-format = true
docstring-code-line-length = "dynamic"
```

### Black Configuration (If Using Black)

```toml
[tool.black]
line-length = 88
target-version = ['py312']
include = '\.pyi?$'

# Exclude patterns
extend-exclude = '''
/(
  # Directories to exclude
  \.git
  | \.hg
  | \.mypy_cache
  | \.tox
  | \.venv
  | _build
  | buck-out
  | build
  | dist
)/
'''

# Preview features (optional - enables upcoming style changes)
# preview = true
```

## Comments and Docstrings

### Inline Comments

Use sparingly - explain "why", not "what":

```python
# Wrong - stating the obvious
x = x + 1  # Increment x

# Correct - explaining why
x = x + 1  # Compensate for border offset

# Correct - clarifying non-obvious behavior
x = None  # Sentinel value for lazy initialization
```

**Style:**

- Separate from statement by at least two spaces
- Start with `#` and single space
- Use complete sentences when possible

### Block Comments

```python
# Block comments explain complex logic.
# Each line starts with # and single space.
# Paragraphs separated by line with single #.
#
# Use block comments for multi-line explanations
# of algorithms, business logic, or non-obvious code.

def complex_algorithm(data):
    # First, normalize the input data
    normalized = normalize(data)

    # Apply transformation based on business rules
    # Note: threshold value derived from requirements doc #123
    if normalized > THRESHOLD:
        return transform_a(normalized)
    else:
        return transform_b(normalized)
```

### Documentation Strings (Docstrings)

See the [Docstrings and Documentation](docstrings-documentation.md) reference for comprehensive guidance.

**Quick Examples:**

```python
def one_liner():
    """Return an ex-parrot."""
    pass

def multi_line(arg1, arg2):
    """Return a foobang.

    Optional plotz says to frobnicate the bizbaz first.

    Args:
        arg1: First argument description
        arg2: Second argument description

    Returns:
        Description of return value
    """
    pass
```

## Best Practices

### 1. Consistency Over Personal Preference

Follow project/team conventions even if you prefer different style. Consistency reduces friction and cognitive load.

### 2. Use Automated Formatters

**Benefits:**

- Eliminate style debates ("format on save" ends all arguments)
- Enforce consistency automatically
- Save time during code review (focus on logic, not style)
- Reduce merge conflicts (consistent formatting = fewer diffs)

**Recommendation**: Configure your editor to format on save.

### 3. Lint in CI/CD Pipelines

```yaml
# Example GitHub Actions workflow
name: Lint

on: [push, pull_request]

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: '3.12'
      - name: Install dependencies
        run: pip install ruff
      - name: Lint with Ruff
        run: ruff check .
      - name: Check formatting
        run: ruff format --check .
```

### 4. Pre-commit Hooks for Team Enforcement

```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/astral-sh/ruff-pre-commit
    rev: v0.9.0
    hooks:
      - id: ruff
        args: [--fix]
      - id: ruff-format
```

Install pre-commit:

```bash
pip install pre-commit
pre-commit install
```

### 5. Start Simple, Add Rules Incrementally

Don't enable all linting rules at once on existing codebases:

1. Start with minimal rules: `["E", "F"]` (errors + Pyflakes)
2. Add safe rules: `["E", "F", "I"]` (+ import sorting)
3. Gradually add: `["E", "F", "I", "N", "UP", "B"]`
4. Review and customize based on team needs

### 6. Document Deviations

When you must ignore a rule, document why:

```python
# ruff: noqa: E501 - Long regex pattern, splitting reduces readability
COMPLEX_PATTERN = r"^(?P<protocol>https?)://(?P<host>[\w.-]+)(?::(?P<port>\d+))?(?P<path>/[\w/.-]*)?(?:\?(?P<query>[\w=&-]+))?$"

# Specific violation suppression
result = some_function(very_long_arg1, very_long_arg2)  # noqa: E501
```

### 7. Balance Strictness and Pragmatism

- **Strict mode for new projects**: Enable many rules from start
- **Gradual adoption for legacy code**: Fix existing code incrementally
- **Team agreement**: Decide on rules together, avoid imposed standards
- **Continuous improvement**: Revisit style guide periodically

### 8. Keep Style Configuration in Version Control

Always commit `.ruff.toml`, `pyproject.toml`, or `.pre-commit-config.yaml`:

- Ensures all developers use same settings
- Documents team decisions
- Enables CI/CD to enforce same rules
- Prevents "works on my machine" formatting issues

## Line Length Trade-offs

| Line Length | Pros | Cons | Recommended For |
| --- | --- | --- | --- |
| **79** (PEP 8 strict) | Side-by-side diffs, strict PEP 8 compliance | More line breaks, can hurt readability | Standard library, conservative projects |
| **88** (Black default) | Balance of readability and PEP 8 spirit | Slightly longer than strict PEP 8 | General Python projects, Black users |
| **100** (Ruff default) | Fewer line breaks, modern displays | May exceed terminal width | Modern projects, teams preferring fewer breaks |
| **120** | Maximum readability, minimal breaks | Not PEP 8 compliant, wide displays required | Teams with modern tooling, larger displays |

**Recommendation**: Start with 88 or 100. Only go shorter (79) if strict PEP 8 compliance required. Only go longer (120) with full team agreement.

## Quick Reference Checklist

Before committing code, verify:

- [ ] Functions/variables use `snake_case`
- [ ] Classes use `PascalCase`
- [ ] Constants use `UPPER_CASE`
- [ ] Imports organized (stdlib, third-party, local)
- [ ] No wildcard imports (`from x import *`)
- [ ] 4 spaces for indentation (no tabs)
- [ ] Line length within limit (79/88/100)
- [ ] Two blank lines between top-level definitions
- [ ] One blank line between class methods
- [ ] Docstrings for public modules/classes/functions
- [ ] Code formatted with Ruff/Black
- [ ] Linting passes with no errors
- [ ] Meaningful comments explain "why", not "what"

## Migration Strategy

### Moving to Modern Tooling

If migrating from older tools to Ruff:

#### Step 1: Install Ruff

```bash
pip install ruff
```

#### Step 2: Run Ruff Check (Observe)

```bash
ruff check . --output-format=grouped
```

Review violations without fixing. Understand current state.

#### Step 3: Configure Ruff

Create `pyproject.toml` or `ruff.toml` with baseline configuration.

#### Step 4: Auto-fix Safe Issues

```bash
ruff check --fix .
```

#### Step 5: Format Code

```bash
ruff format .
```

#### Step 6: Update CI/CD

Replace old linter/formatter commands with Ruff.

#### Step 7: Enable Pre-commit Hooks

Add Ruff to `.pre-commit-config.yaml`.

#### Step 8: Gradually Enable More Rules

Add rules to `select` list incrementally.

## Official Documentation

- **PEP 8 (Style Guide)**: <https://peps.python.org/pep-0008/>
- **PEP 257 (Docstring Conventions)**: <https://peps.python.org/pep-0257/>
- **Ruff Documentation**: <https://docs.astral.sh/ruff/>
- **Ruff Linter**: <https://docs.astral.sh/ruff/linter/>
- **Ruff Formatter**: <https://docs.astral.sh/ruff/formatter/>
- **Ruff Rules**: <https://docs.astral.sh/ruff/rules/>
- **Black Documentation**: <https://black.readthedocs.io/>
- **Black Code Style**: <https://black.readthedocs.io/en/stable/the_black_code_style/>
- **isort Documentation**: <https://pycqa.github.io/isort/>

## Summary

**Modern Python style (2024-2025):**

1. **Follow PEP 8** for naming and structural conventions
2. **Use Ruff** as all-in-one linter + formatter (replaces Flake8, isort, Black)
3. **Automate everything** - format on save, lint in CI/CD, pre-commit hooks
4. **Consistency wins** - team agreement > personal preference
5. **Start simple** - enable rules incrementally, don't overwhelm existing codebases
6. **Document deviations** - when you must break rules, explain why

**Quick Start (New Project):**

```bash
# Install Ruff
pip install ruff

# Create pyproject.toml with Ruff config
# (Use comprehensive example from this guide)

# Format and lint
ruff format .
ruff check --fix .

# Add pre-commit hooks
pip install pre-commit
# Create .pre-commit-config.yaml
pre-commit install
```

Following these conventions ensures your Python code is readable, maintainable, and consistent with the broader Python ecosystem.
