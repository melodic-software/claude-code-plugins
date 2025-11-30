# Python Project Structure Guide

A well-organized project structure is the foundation of maintainable Python code. This guide covers modern best practices for organizing Python projects, from simple scripts to distributable packages.

**Official Sources:**

- Python Packaging User Guide: <https://packaging.python.org/>
- Python Packaging Tutorial: <https://packaging.python.org/tutorials/packaging-projects/>
- pytest Documentation: <https://docs.pytest.org/en/stable/explanation/goodpractices.html>
- PEP 420 (Namespace Packages): <https://peps.python.org/pep-0420/>
- PEP 8 (Style Guide): <https://peps.python.org/pep-0008/>

## Table of Contents

- [Modern Standard: src/ Layout](#modern-standard-src-layout)
- [Flat Layout (Legacy/Simple Projects)](#flat-layout-legacysimple-projects)
- [Complete Project Structure](#complete-project-structure)
- [Import Strategies](#import-strategies)
- [**init**.py Files](#initpy-files)
- [Tests Organization](#tests-organization)
- [File and Directory Naming Conventions](#file-and-directory-naming-conventions)
- [Project Metadata and Configuration](#project-metadata-and-configuration)
- [Additional Directories](#additional-directories)
- [Package vs Application Structure](#package-vs-application-structure)
- [Summary](#summary)
- [Official Documentation](#official-documentation)

## Modern Standard: src/ Layout

The **src/ layout** is the modern standard for Python packages intended for distribution. As of 2024-2025, the official Python Packaging User Guide tutorial uses and recommends this structure.

### Why src/ Layout?

The src/ layout provides critical benefits that prevent common packaging bugs:

1. **Prevents Import Shadowing**: By placing your package inside `src/`, you avoid accidentally importing your package from the project root rather than the installed location. This catches missing or undeclared dependencies early.

2. **Forces Proper Installation**: You cannot import your package without installing it (via `pip install -e .` for development). This ensures your package metadata and dependencies are properly configured.

3. **Aligns with Modern Tooling**: Modern build backends like setuptools, Hatchling, and PDM are designed to work seamlessly with the src/ layout.

4. **Clarity and Scalability**: Keeps source code separate from project configuration, tests, and metadata, making larger projects easier to navigate and less error-prone.

5. **Better Testing**: Tests run against the installed package, not the source tree, which catches packaging issues that might otherwise slip through.

### Basic src/ Layout Structure

```text
my-project/
├── LICENSE
├── README.md
├── pyproject.toml
├── src/
│   └── my_package/
│       ├── __init__.py
│       ├── module1.py
│       ├── module2.py
│       └── subpackage/
│           ├── __init__.py
│           └── module3.py
└── tests/
    ├── __init__.py
    ├── test_module1.py
    ├── test_module2.py
    └── subpackage/
        ├── __init__.py
        └── test_module3.py
```

**Key points:**

- Package lives in `src/my_package/` (not at root)
- Package name uses underscores (`my_package`), not hyphens
- Tests mirror the package structure
- Configuration files at project root

### Installing for Development

With src/ layout, you must install your package before you can import it:

```bash
# Create virtual environment
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install in editable mode (for development)
pip install -e .
```

The `-e` flag installs in "editable" mode, allowing you to change source code and see changes immediately without reinstalling.

## Flat Layout (Legacy/Simple Projects)

The **flat layout** places the package directory at the project root. This is acceptable for simple scripts, non-distributed projects, or very small tools, but is **not recommended** for packages intended for distribution.

### Flat Layout Structure

```text
my-project/
├── LICENSE
├── README.md
├── pyproject.toml
├── my_package/
│   ├── __init__.py
│   ├── module1.py
│   └── module2.py
└── tests/
    ├── __init__.py
    └── test_module1.py
```

### When Flat Layout is Acceptable

Use flat layout only when:

- Creating standalone scripts (not packages)
- Building non-distributable internal tools
- Working on very simple one-off projects
- Explicitly choosing simplicity over best practices (and accepting the trade-offs)

### Trade-offs vs src/ Layout

**Advantages:**

- Simpler structure (fewer directories)
- Can import directly without installation (during development)
- Less initial setup

**Disadvantages:**

- Risk of import shadowing (importing uninstalled code)
- Harder to catch packaging bugs early
- Can accidentally import package before it's properly installed
- Not recommended by official packaging guide

**Official guidance**: Use src/ layout for libraries and packages intended for reuse and distribution.

## Complete Project Structure

Here's a comprehensive example showing all common directories and files:

```text
my-project/
├── .github/                      # GitHub-specific files
│   ├── workflows/
│   │   └── tests.yml            # CI/CD workflows
│   └── ISSUE_TEMPLATE/
├── .gitignore                    # Git ignore patterns
├── LICENSE                       # License file (required for PyPI)
├── README.md                     # Project description
├── pyproject.toml                # Project metadata and build config
├── src/
│   └── my_package/
│       ├── __init__.py           # Package initialization
│       ├── __main__.py           # Entry point for `python -m my_package`
│       ├── cli.py                # Command-line interface
│       ├── core.py               # Core functionality
│       ├── utils.py              # Utility functions
│       └── subpackage/
│           ├── __init__.py
│           ├── module_a.py
│           └── module_b.py
├── tests/                        # Test directory (mirrors src/)
│   ├── __init__.py
│   ├── conftest.py               # pytest fixtures and configuration
│   ├── test_cli.py
│   ├── test_core.py
│   ├── test_utils.py
│   └── subpackage/
│       ├── __init__.py
│       ├── test_module_a.py
│       └── test_module_b.py
├── docs/                         # Documentation
│   ├── conf.py                   # Sphinx configuration
│   ├── index.rst
│   └── api/
├── scripts/                      # Utility scripts
│   ├── setup_dev.sh
│   └── release.py
├── examples/                     # Example code
│   └── basic_usage.py
└── data/                         # Data files (if needed)
    └── sample_data.csv
```

## Import Strategies

Python supports two types of imports: absolute and relative. Understanding when to use each is critical for maintainable code.

### Absolute Imports (Recommended)

Absolute imports specify the full path from the package root. They are **the recommended default** for most situations.

```python
# In src/my_package/subpackage/module_a.py

# Absolute imports (PREFERRED)
from my_package.core import process_data
from my_package.utils import helper_function
from my_package.subpackage.module_b import ClassB
```

**Advantages:**

- Clear and unambiguous
- Location-agnostic (still works if file is moved)
- Explicitly shows where imports come from
- Recommended by PEP 8
- Better for large codebases
- Easier for newcomers to understand

**When to use:**

- By default in all situations
- In large or shared codebases
- When code might be refactored or reorganized
- For public APIs and user-facing modules

### Relative Imports (Use Sparingly)

Relative imports use dots to specify locations relative to the current module.

```python
# In src/my_package/subpackage/module_a.py

# Relative imports (use sparingly)
from . import module_b              # Same package (subpackage)
from .module_b import ClassB        # Same package, specific import
from .. import core                 # Parent package (my_package)
from ..utils import helper_function # Parent package module
from ..core import process_data     # Parent package module
```

**Advantages:**

- Concise for neighboring modules
- Reduces repetition in deeply nested packages
- Makes package more self-contained

**Disadvantages:**

- Only works when module is run as part of a package
- Cannot be used in scripts meant to be executed directly (`python script.py`)
- Harder to read and understand
- More fragile during refactoring

**When to use:**

- Within a tightly connected package for sibling/parent modules
- When package structure is stable and unlikely to change
- To avoid excessively long import paths in deeply nested packages
- Only when the brevity genuinely improves readability

**Important**: Never use relative imports in:

- Scripts intended for direct execution
- Top-level modules
- Code that might become a standalone module later

### Circular Import Prevention

Both absolute and relative imports can suffer from circular dependencies. Best practices:

1. **Restructure code** to eliminate circular dependencies
2. **Use local imports** (inside functions) as a last resort
3. **Create a common module** for shared types/constants
4. **Use type hints with `TYPE_CHECKING`** for import-time type checking

```python
# Good: avoid circular imports with TYPE_CHECKING
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from my_package.other_module import SomeClass

def process(data: 'SomeClass') -> None:
    # Local import to break circular dependency
    from my_package.other_module import SomeClass
    # Function implementation
    pass
```

## **init**.py Files

The `__init__.py` file marks a directory as a Python package and controls package initialization and the public API.

### Purpose of **init**.py

1. **Mark directory as a package**: Allows importing the directory as a package
2. **Control public API**: Define what gets imported with `from package import *`
3. **Package initialization**: Execute setup code when package is imported
4. **Namespace management**: Expose or hide submodules

### Basic **init**.py (Empty)

For simple packages, an empty `__init__.py` is perfectly acceptable:

```python
# src/my_package/__init__.py
# Empty file - just marks this directory as a package
```

This allows:

```python
import my_package
from my_package.module1 import function
```

### Controlling Public API

Use `__init__.py` to expose a clean public API:

```python
# src/my_package/__init__.py

from .core import process_data, analyze
from .utils import helper_function
from .models import DataModel, ResultModel

__all__ = [
    'process_data',
    'analyze',
    'helper_function',
    'DataModel',
    'ResultModel',
]
```

This allows users to import directly from the package:

```python
from my_package import process_data, DataModel
```

Instead of:

```python
from my_package.core import process_data
from my_package.models import DataModel
```

### Package Initialization

`__init__.py` can execute initialization code:

```python
# src/my_package/__init__.py

import logging

# Set up package-level logging
logger = logging.getLogger(__name__)
logger.addHandler(logging.NullHandler())

# Package metadata
__version__ = '1.0.0'
__author__ = 'Your Name'

# Import public API
from .core import process_data
from .models import DataModel

__all__ = ['process_data', 'DataModel', '__version__']
```

**Best practice**: Keep initialization minimal and avoid side effects (I/O, network calls, expensive computations).

### Namespace Packages (PEP 420)

Since Python 3.3, directories without `__init__.py` are treated as **namespace packages**. These allow multiple distributions to contribute to the same package namespace.

**Use namespace packages when:**

- Creating plugin systems
- Distributing packages across multiple repositories
- Building multi-root packages

**Use regular packages (with `__init__.py`) when:**

- Building standard libraries or applications
- Need package initialization
- Want explicit control over the public API

**Example namespace package structure:**

```text
# Distribution 1
my_namespace/
└── pluginA/
    └── module.py

# Distribution 2
my_namespace/
└── pluginB/
    └── module.py

# Both installed, both available under my_namespace
```

**Important**: For beginners and standard projects, use regular packages with `__init__.py`.

## Tests Organization

Tests should mirror your source structure and use pytest's discovery conventions.

### Standard Test Layout

```text
my-project/
├── src/
│   └── my_package/
│       ├── __init__.py
│       ├── core.py
│       ├── utils.py
│       └── models/
│           ├── __init__.py
│           └── data.py
└── tests/
    ├── __init__.py
    ├── conftest.py
    ├── test_core.py
    ├── test_utils.py
    └── models/
        ├── __init__.py
        └── test_data.py
```

**Key principles:**

- Tests live outside `src/` (separate from application code)
- Test directory structure mirrors package structure
- Test files named `test_*.py` or `*_test.py`
- Use `conftest.py` for shared fixtures

### Test File Naming

pytest discovers tests using these patterns:

- `test_*.py` (preferred)
- `*_test.py` (alternative)

Within test files:

- `test_*` functions (outside classes)
- `Test*` classes (without `__init__`)
- `test_*` methods inside `Test*` classes

```python
# tests/test_core.py

import pytest
from my_package.core import process_data

def test_process_data_with_valid_input():
    result = process_data([1, 2, 3])
    assert result == [2, 4, 6]

def test_process_data_with_empty_input():
    result = process_data([])
    assert result == []

class TestDataProcessor:
    def test_initialization(self):
        # Test code
        pass

    def test_processing(self):
        # Test code
        pass
```

### conftest.py for Shared Fixtures

`conftest.py` provides fixtures and configuration shared across tests:

```python
# tests/conftest.py

import pytest
from my_package.models import DataModel

@pytest.fixture
def sample_data():
    """Provide sample data for tests."""
    return {
        'key1': 'value1',
        'key2': 'value2',
    }

@pytest.fixture
def data_model(sample_data):
    """Provide initialized DataModel for tests."""
    return DataModel(sample_data)
```

Use in tests:

```python
# tests/test_models.py

def test_model_creation(data_model):
    assert data_model.is_valid()

def test_model_data(sample_data):
    assert 'key1' in sample_data
```

### Running Tests

```bash
# Run all tests
pytest

# Run specific test file
pytest tests/test_core.py

# Run tests matching pattern
pytest -k "test_process"

# Run with coverage
pytest --cov=my_package
```

## File and Directory Naming Conventions

Consistent naming is critical for Python imports and discoverability.

### Modules (Files)

Use **snake_case** for Python module names:

```text
✅ Correct:
my_module.py
data_processor.py
user_authentication.py

❌ Incorrect:
MyModule.py          # CamelCase
dataProcessor.py     # mixedCase
my-module.py         # Hyphens (cannot be imported)
```

**Rationale**: Module names become part of import statements. `my-module.py` cannot be imported as `import my-module`.

### Packages (Directories)

Use **snake_case** for package directory names:

```text
✅ Correct:
my_package/
data_models/
user_auth/

❌ Incorrect:
MyPackage/
dataModels/
my-package/
```

### Test Files

Use `test_` prefix or `_test` suffix:

```text
✅ Correct:
test_module.py       # Preferred
test_core.py
module_test.py       # Alternative

❌ Incorrect:
module_tests.py      # Not discovered by pytest
moduleTest.py
```

### Special Files

Common special file names:

```text
__init__.py          # Package initialization
__main__.py          # Entry point for `python -m package`
conftest.py          # pytest configuration and fixtures
setup.py             # Legacy build configuration (use pyproject.toml)
```

### Naming Rules Summary

| Type         | Convention  | Example             |
| ------------ | ----------- | ------------------- |
| Module       | snake_case  | `data_processor.py` |
| Package      | snake_case  | `my_package/`       |
| Test file    | test_*.py   | `test_processor.py` |
| Class        | PascalCase  | `DataProcessor`     |
| Function     | snake_case  | `process_data()`    |
| Constant     | UPPER_CASE  | `MAX_SIZE`          |
| Private      | _prefix     | `_internal_func()`  |

## Project Metadata and Configuration

Modern Python projects use `pyproject.toml` for metadata and configuration.

### pyproject.toml (Modern Standard)

`pyproject.toml` is the modern, standardized way to configure Python projects:

```toml
[build-system]
requires = ["hatchling>=1.26"]
build-backend = "hatchling.build"

[project]
name = "my-package"
version = "1.0.0"
description = "A sample Python package"
readme = "README.md"
requires-python = ">=3.9"
license = "MIT"
authors = [
    { name = "Your Name", email = "you@example.com" },
]
keywords = ["example", "package", "tutorial"]
classifiers = [
    "Development Status :: 4 - Beta",
    "Intended Audience :: Developers",
    "License :: OSI Approved :: MIT License",
    "Programming Language :: Python :: 3",
    "Programming Language :: Python :: 3.9",
    "Programming Language :: Python :: 3.10",
    "Programming Language :: Python :: 3.11",
    "Programming Language :: Python :: 3.12",
]

dependencies = [
    "requests>=2.28.0",
    "pandas>=1.5.0",
]

[project.optional-dependencies]
dev = [
    "pytest>=7.0",
    "pytest-cov>=4.0",
    "black>=23.0",
    "ruff>=0.1.0",
]
docs = [
    "sphinx>=6.0",
    "sphinx-rtd-theme>=1.0",
]

[project.urls]
Homepage = "https://github.com/yourusername/my-package"
Documentation = "https://my-package.readthedocs.io"
Repository = "https://github.com/yourusername/my-package"
Issues = "https://github.com/yourusername/my-package/issues"

[project.scripts]
my-cli = "my_package.cli:main"

[tool.pytest.ini_options]
testpaths = ["tests"]
python_files = ["test_*.py"]
python_classes = ["Test*"]
python_functions = ["test_*"]
addopts = "--strict-markers --strict-config -ra"

[tool.coverage.run]
source = ["src"]
branch = true

[tool.coverage.report]
exclude_lines = [
    "pragma: no cover",
    "def __repr__",
    "raise AssertionError",
    "raise NotImplementedError",
    "if __name__ == .__main__.:",
]

[tool.ruff]
line-length = 100
target-version = "py39"

[tool.black]
line-length = 100
target-version = ["py39", "py310", "py311"]
```

**Key sections:**

- `[build-system]`: Specifies build backend (Hatchling, setuptools, etc.)
- `[project]`: Core metadata (name, version, dependencies)
- `[project.optional-dependencies]`: Optional dependency groups (dev, docs, etc.)
- `[project.urls]`: Project URLs (homepage, repository, etc.)
- `[project.scripts]`: Command-line entry points
- `[tool.*]`: Tool-specific configuration (pytest, black, ruff, etc.)

### README.md

Every project should have a README with:

```markdown
# My Package

Brief description of what your package does.

## Installation

```bash
pip install my-package
```

## Quick Start

```python
from my_package import process_data

result = process_data([1, 2, 3])
```

## Documentation

Full documentation: <https://my-package.readthedocs.io>

## Contributing

See CONTRIBUTING.md

## License

MIT License - see LICENSE file

### LICENSE

Choose an appropriate license and include the full text:

- MIT: Permissive, simple
- Apache 2.0: Permissive with patent protection
- GPL: Copyleft
- See <https://choosealicense.com/> for guidance

### .gitignore

Exclude generated files from version control:

```gitignore
# Python
__pycache__/
*.py[cod]
*$py.class
*.so
.Python
build/
develop-eggs/
dist/
downloads/
eggs/
.eggs/
lib/
lib64/
parts/
sdist/
var/
wheels/
*.egg-info/
.installed.cfg
*.egg

# Virtual environments
venv/
env/
ENV/

# Testing
.pytest_cache/
.coverage
htmlcov/

# IDEs
.vscode/
.idea/
*.swp
*.swo

# OS
.DS_Store
Thumbs.db
```

### requirements.txt vs pyproject.toml

**Modern best practice**: Use `pyproject.toml` for dependencies.

`requirements.txt` is legacy and has limitations:

```bash
# Legacy approach (avoid for new projects)
pip install -r requirements.txt
pip install -r requirements-dev.txt
```

With `pyproject.toml`:

```bash
# Install runtime dependencies
pip install .

# Install with dev dependencies
pip install -e ".[dev]"

# Install with docs dependencies
pip install -e ".[docs]"

# Install with all optional dependencies
pip install -e ".[dev,docs]"
```

## Additional Directories

### docs/ - Documentation

For Sphinx documentation:

```text
docs/
├── conf.py              # Sphinx configuration
├── index.rst            # Documentation home
├── api/                 # API reference
│   ├── core.rst
│   └── utils.rst
├── tutorials/           # Tutorials
│   └── quickstart.rst
└── _static/             # Static files (images, CSS)
    └── logo.png
```

Build documentation:

```bash
cd docs
make html
```

### scripts/ - Utility Scripts

Helper scripts not part of the package:

```text
scripts/
├── setup_dev.sh         # Development environment setup
├── release.py           # Release automation
└── benchmark.py         # Performance benchmarks
```

### examples/ - Example Code

Usage examples for users:

```text
examples/
├── basic_usage.py
├── advanced_features.py
└── integration_example.py
```

### data/ - Data Files

Static data files (use sparingly):

```text
data/
├── sample_input.csv
└── config_template.json
```

**Best practice**: Avoid committing large data files. Use Git LFS or external storage.

### .github/ - GitHub-Specific Files

```text
.github/
├── workflows/
│   ├── tests.yml        # CI testing
│   ├── release.yml      # Release automation
│   └── docs.yml         # Documentation builds
├── ISSUE_TEMPLATE/
│   ├── bug_report.md
│   └── feature_request.md
└── PULL_REQUEST_TEMPLATE.md
```

## Package vs Application Structure

### Libraries (Packages)

For distributable libraries, always use **src/ layout**:

```text
my-library/
├── pyproject.toml
├── README.md
├── LICENSE
├── src/
│   └── my_library/
│       ├── __init__.py
│       └── ...
└── tests/
```

**Characteristics:**

- Intended for `pip install`
- Published to PyPI
- Used by other projects
- Strong API stability guarantees
- Comprehensive documentation

### Applications (Scripts, Services)

For applications, structure depends on complexity:

**Simple application (flat layout acceptable):**

```text
my-app/
├── pyproject.toml
├── my_app/
│   ├── __init__.py
│   ├── main.py
│   └── config.py
└── tests/
```

**Complex application (use src/ layout):**

```text
my-service/
├── pyproject.toml
├── src/
│   └── my_service/
│       ├── __init__.py
│       ├── api/
│       ├── database/
│       ├── models/
│       └── utils/
├── tests/
├── docker/
└── deploy/
```

**Key differences:**

| Aspect       | Library                    | Application                           |
| ------------ | -------------------------- | ------------------------------------- |
| Structure    | src/ layout required       | src/ or flat depending on complexity  |
| Dependencies | Minimal, loose constraints | Exact versions (lockfile)             |
| Entry points | Importable modules         | CLI or service                        |
| Distribution | PyPI                       | Docker, executable, etc.              |
| Versioning   | Semantic versioning        | Internal versioning                   |

## Summary

**For new projects:**

1. **Use src/ layout** for any package intended for distribution
2. **Use pyproject.toml** for all configuration
3. **Prefer absolute imports** over relative imports
4. **Mirror test structure** to source structure
5. **Follow naming conventions**: snake_case for modules/packages
6. **Keep **init**.py minimal** and focused on public API
7. **Write comprehensive README** and choose appropriate license

**Decision tree:**

```text
Is this a distributable package?
├─ Yes → Use src/ layout
└─ No → Is it complex (10+ modules)?
    ├─ Yes → Use src/ layout anyway
    └─ No → Flat layout acceptable (but src/ still recommended)
```

The modern Python packaging ecosystem strongly favors src/ layout. When in doubt, use it—you'll avoid common pitfalls and align with community best practices.

## Official Documentation

- **Python Packaging User Guide**: <https://packaging.python.org/>
- **Packaging Tutorial**: <https://packaging.python.org/tutorials/packaging-projects/>
- **pytest Good Practices**: <https://docs.pytest.org/en/stable/explanation/goodpractices.html>
- **PEP 420 (Namespace Packages)**: <https://peps.python.org/pep-0420/>
- **PEP 8 (Style Guide)**: <https://peps.python.org/pep-0008/>
- **PEP 621 (Project Metadata)**: <https://peps.python.org/pep-0621/>

---

**Last Verified:** 2025-01-17
**Sources:** Python Packaging User Guide, pytest documentation, Perplexity research on modern best practices
