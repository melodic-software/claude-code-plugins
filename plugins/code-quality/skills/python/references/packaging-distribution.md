# Python Packaging and Distribution

Comprehensive guide to modern Python packaging, building, and distributing packages to PyPI using PEP 517/518/621 standards.

**Official Documentation:**

- [Python Packaging User Guide](https://packaging.python.org/)
- [PEP 517 - Build System Interface](https://peps.python.org/pep-0517/)
- [PEP 518 - Build System Dependencies](https://peps.python.org/pep-0518/)
- [PEP 621 - Project Metadata](https://peps.python.org/pep-0621/)
- [PEP 440 - Version Identification](https://peps.python.org/pep-0440/)
- [Semantic Versioning 2.0.0](https://semver.org/)

## Table of Contents

- [Modern Packaging Standards Overview](#modern-packaging-standards-overview)
- [Project Structure](#project-structure)
- [Build Backends Comparison](#build-backends-comparison)
- [Complete pyproject.toml Structure](#complete-pyprojecttoml-structure)
- [Project Metadata Fields](#project-metadata-fields)
- [Dependencies](#dependencies)
- [Semantic Versioning (SemVer)](#semantic-versioning-semver)
- [Entry Points and Console Scripts](#entry-points-and-console-scripts)
- [Building Distributions](#building-distributions)
- [Publishing to PyPI](#publishing-to-pypi)
- [Version Management](#version-management)
- [README, LICENSE, and Documentation](#readme-license-and-documentation)
- [CI/CD for Packaging](#cicd-for-packaging)
- [Common Pitfalls and Solutions](#common-pitfalls-and-solutions)
- [Complete Workflow Example](#complete-workflow-example)
- [Summary](#summary)

## Modern Packaging Standards Overview

Modern Python packaging has evolved from scattered `setup.py` scripts to a standardized, declarative approach centered on **pyproject.toml**. This file consolidates all project metadata, build system configuration, and tool settings in a single location.

### The Three Core PEPs

#### PEP 517: Build System Interface

Defines how build tools (pip, build) interact with build backends (setuptools, hatchling, etc.). This abstraction allows different backends to coexist without frontends needing backend-specific knowledge.

#### PEP 518: Build System Dependencies

Specifies the `[build-system]` table in pyproject.toml, where you declare which build backend to use and any build-time dependencies. This ensures build environments are reproducible.

#### PEP 621: Project Metadata

Standardizes the `[project]` table for metadata like name, version, description, authors, and dependencies. Replaces the need for setup.cfg or setup.py for metadata declaration.

### Why pyproject.toml?

Before pyproject.toml, Python projects used multiple configuration files:

- `setup.py` - Build script and metadata
- `setup.cfg` - Static metadata
- `MANIFEST.in` - Include/exclude files
- `requirements.txt` - Runtime dependencies
- `requirements-dev.txt` - Development dependencies
- Various tool configs (`.flake8`, `.coveragerc`, etc.)

**pyproject.toml consolidates these into one file**, providing:

- Declarative configuration over imperative scripts
- Standard format (TOML) for easy parsing
- Tool-agnostic metadata specification
- Single source of truth for project configuration

## Project Structure

Modern Python projects follow the **src layout** pattern, which forces proper installation before testing:

```text
my-project/
├── LICENSE                  # License text (e.g., MIT, Apache 2.0)
├── README.md               # Package description and documentation
├── pyproject.toml          # Build system and project metadata
├── src/
│   └── my_package/        # Package code (matches project name)
│       ├── __init__.py    # Package marker
│       ├── module.py      # Your modules
│       └── cli.py         # CLI entry points (optional)
└── tests/                 # Test directory (mirrors src/ structure)
    ├── __init__.py
    └── test_module.py
```

**Why src/ layout?**

- Forces installation before testing (catches import issues early)
- Prevents accidental imports from working directory
- Clear separation between source and tests
- Industry best practice for library development

**Directory naming:** The package directory under `src/` should match your package name (with underscores instead of hyphens). Example: project `my-project` → package `my_package`.

## Build Backends Comparison

Python's modern packaging ecosystem supports multiple build backends. Choose based on your project's needs:

### Hatchling (Recommended for Pure Python)

**When to use:** Pure Python packages, new projects, simple builds

**Pros:**

- Modern, fast, minimal configuration
- Part of PyPA (Python Packaging Authority)
- Excellent documentation and active development
- Smart defaults reduce boilerplate

**Cons:**

- Limited support for compiled extensions
- Newer (less ecosystem maturity than setuptools)

**Configuration:**

```toml
[build-system]
requires = ["hatchling >= 1.26"]
build-backend = "hatchling.build"
```

### Setuptools (Industry Standard)

**When to use:** Compiled extensions (C/C++), legacy projects, complex builds

**Pros:**

- Mature, battle-tested, widest compatibility
- Extensive features and plugin ecosystem
- Best support for compiled extensions
- De facto standard (most documentation assumes setuptools)

**Cons:**

- More complex configuration
- Slower builds than modern alternatives
- Historical baggage from pre-PEP 517 era

**Configuration:**

```toml
[build-system]
requires = ["setuptools >= 77.0.3"]
build-backend = "setuptools.build_meta"
```

### Flit (Minimalist)

**When to use:** Simple pure Python packages, minimal configuration needs

**Pros:**

- Extremely minimal configuration
- Fast builds
- Perfect for single-module packages

**Cons:**

- Limited features (no compiled extensions)
- Smaller ecosystem than setuptools/hatchling
- Less suitable for complex projects

**Configuration:**

```toml
[build-system]
requires = ["flit_core >= 3.12.0, <4"]
build-backend = "flit_core.buildapi"
```

### Poetry (All-in-One Tool)

**When to use:** Application development, teams wanting integrated tooling

**Pros:**

- Integrated dependency management with lock files
- Built-in virtual environment management
- Single tool for packaging, dependencies, and publishing

**Cons:**

- Not just a build backend (opinionated full workflow)
- Lock files less critical for libraries than applications
- Larger learning curve

**Configuration:**

```toml
[build-system]
requires = ["poetry-core"]
build-backend = "poetry.core.masonry.api"
```

### PDM (Modern Alternative)

**When to use:** Projects wanting PEP 582 support, modern dependency management

**Pros:**

- PEP 582 support (no virtual environments)
- Modern dependency resolution
- Lock file support

**Cons:**

- Less mature than alternatives
- Smaller community

**Configuration:**

```toml
[build-system]
requires = ["pdm-backend >= 2.4.0"]
build-backend = "pdm.backend"
```

## Complete pyproject.toml Structure

Here's a comprehensive example showing all common sections:

```toml
# ============================================================================
# Build System Configuration (PEP 517/518)
# ============================================================================
[build-system]
requires = ["hatchling >= 1.26"]
build-backend = "hatchling.build"

# ============================================================================
# Project Metadata (PEP 621)
# ============================================================================
[project]
# REQUIRED: Package name (must be unique on PyPI)
name = "example-package"

# REQUIRED: Version (can be dynamic with some backends)
version = "0.1.0"

# Short one-line description
description = "A short description of your package"

# Long description from README
readme = "README.md"

# Python version compatibility
requires-python = ">=3.8"

# SPDX license expression (PEP 639)
license = "MIT"

# License files to include (glob patterns)
license-files = ["LICEN[CS]E*"]

# Authors (can have multiple)
authors = [
    {name = "Your Name", email = "your.email@example.com"},
    {name = "Another Author", email = "another@example.com"},
]

# Maintainers (optional, same format as authors)
maintainers = [
    {name = "Maintainer Name", email = "maintainer@example.com"},
]

# Keywords for PyPI search
keywords = ["example", "packaging", "tutorial"]

# PyPI classifiers (see https://pypi.org/classifiers/)
classifiers = [
    "Development Status :: 4 - Beta",
    "Intended Audience :: Developers",
    "License :: OSI Approved :: MIT License",
    "Programming Language :: Python :: 3",
    "Programming Language :: Python :: 3.8",
    "Programming Language :: Python :: 3.9",
    "Programming Language :: Python :: 3.10",
    "Programming Language :: Python :: 3.11",
    "Programming Language :: Python :: 3.12",
    "Operating System :: OS Independent",
    "Topic :: Software Development :: Libraries :: Python Modules",
]

# ============================================================================
# Dependencies
# ============================================================================

# Runtime dependencies (PEP 508 format)
dependencies = [
    "requests>=2.28.0",      # Minimum version
    "click>=8.0,<9.0",       # Version range
    "pydantic>=2.0",         # Major version constraint
]

# Optional dependencies (extras)
[project.optional-dependencies]
dev = [
    "pytest>=7.0",
    "pytest-cov>=4.0",
    "black>=22.0",
    "ruff>=0.1.0",
    "mypy>=1.0",
]
docs = [
    "sphinx>=5.0",
    "sphinx-rtd-theme>=1.0",
    "myst-parser>=0.18",
]
test = [
    "pytest>=7.0",
    "pytest-cov>=4.0",
    "pytest-asyncio>=0.20",
]

# ============================================================================
# URLs (displayed on PyPI)
# ============================================================================
[project.urls]
Homepage = "https://github.com/username/example-package"
Documentation = "https://example-package.readthedocs.io"
Repository = "https://github.com/username/example-package.git"
Issues = "https://github.com/username/example-package/issues"
Changelog = "https://github.com/username/example-package/blob/main/CHANGELOG.md"

# ============================================================================
# Entry Points (Console Scripts)
# ============================================================================

# Console scripts (CLI commands)
[project.scripts]
example-cli = "example_package.cli:main"
example-tool = "example_package.tools:run"

# GUI scripts (Windows: no console window)
[project.gui-scripts]
example-gui = "example_package.gui:main"

# Custom entry points (for plugin systems)
[project.entry-points."example_package.plugins"]
plugin_a = "example_package.plugins:plugin_a"
plugin_b = "example_package.plugins:plugin_b"

# ============================================================================
# Tool-Specific Configuration
# ============================================================================

# Hatchling-specific settings (if using hatchling)
[tool.hatch.version]
path = "src/example_package/__init__.py"

[tool.hatch.build.targets.sdist]
include = [
    "/src",
    "/tests",
    "/README.md",
    "/LICENSE",
]

[tool.hatch.build.targets.wheel]
packages = ["src/example_package"]

# Pytest configuration
[tool.pytest.ini_options]
testpaths = ["tests"]
python_files = ["test_*.py"]
python_classes = ["Test*"]
python_functions = ["test_*"]
addopts = [
    "--strict-markers",
    "--strict-config",
    "--cov=example_package",
]

# Black configuration
[tool.black]
line-length = 88
target-version = ["py38", "py39", "py310", "py311", "py312"]
include = '\.pyi?$'

# Ruff configuration
[tool.ruff]
line-length = 88
target-version = "py38"
select = ["E", "F", "I"]

# MyPy configuration
[tool.mypy]
python_version = "3.8"
warn_return_any = true
warn_unused_configs = true
disallow_untyped_defs = true
```

## Project Metadata Fields

### Required Fields

#### name

- Distribution name on PyPI
- Must be unique, contain only letters, numbers, `.`, `_`, `-`
- Normalized for comparison (hyphens, underscores, dots treated as equivalent)
- Example: `my-package`, `my_package`, `my.package` are equivalent

#### version

- Must follow PEP 440 version scheme
- Format: `MAJOR.MINOR.PATCH` (semantic versioning recommended)
- Can include pre-release identifiers: `1.0.0a1`, `1.0.0b2`, `1.0.0rc1`
- Can be dynamic (loaded from `__version__` or git tags)

### Recommended Fields

#### description

- Short one-line summary (no newlines)
- Displayed on PyPI project page
- Maximum ~80 characters for best display

#### readme

- Path to README file (relative to pyproject.toml)
- Supports `.md` (Markdown), `.rst` (reStructuredText), `.txt` (plain text)
- Auto-detects content type from extension
- Becomes package description on PyPI

#### requires-python

- Python version compatibility
- Examples: `">=3.8"`, `">=3.8,<4.0"`, `">=3.9,!=3.9.0"`
- Installers (pip) use this to find compatible versions

#### license

- SPDX license expression (PEP 639)
- Examples: `"MIT"`, `"Apache-2.0"`, `"GPL-3.0-or-later"`
- See: <https://spdx.org/licenses/>

#### license-files

- Glob patterns for license files
- Examples: `["LICENSE"]`, `["LICEN[CS]E*"]`, `["COPYING"]`
- Files automatically included in distributions

#### authors / maintainers

- Array of tables with `name` and/or `email`
- At least one of `name` or `email` required per entry
- Format: `{name = "Name", email = "email@example.com"}`

#### keywords

- Array of strings for PyPI search
- Help users discover your package
- Example: `["cli", "tool", "automation"]`

#### classifiers

- Trove classifiers from <https://pypi.org/classifiers/>
- Describe development status, audience, license, Python versions, OS, topics
- Used for filtering/searching on PyPI

#### urls

- Table of labeled URLs
- Common keys: Homepage, Documentation, Repository, Issues, Changelog
- Displayed on PyPI sidebar

## Dependencies

### Runtime Dependencies

Specify packages required for your package to function:

```toml
[project]
dependencies = [
    "requests>=2.28.0",           # Minimum version
    "click>=8.0,<9.0",            # Version range
    "pydantic>=2.0,!=2.1.0",      # Exclude specific version
    "django>=3.2; python_version<'3.10'",  # Conditional
]
```

**Version specifiers (PEP 440):**

- `>=1.0` - Version 1.0 or higher
- `<2.0` - Less than version 2.0
- `>=1.0,<2.0` - Range (1.x versions)
- `==1.0` - Exact version (avoid unless necessary)
- `~=1.0` - Compatible release (>=1.0, <2.0)
- `!=1.5` - Exclude specific version

**Environment markers:**

```toml
dependencies = [
    "pywin32>=1.0; sys_platform=='win32'",
    "unix-specific>=1.0; sys_platform!='win32'",
    "backport>=1.0; python_version<'3.9'",
]
```

### Optional Dependencies (Extras)

Group related optional dependencies:

```toml
[project.optional-dependencies]
# Development tools
dev = [
    "pytest>=7.0",
    "black>=22.0",
    "ruff>=0.1.0",
]

# Documentation tools
docs = [
    "sphinx>=5.0",
    "sphinx-rtd-theme>=1.0",
]

# Testing tools
test = [
    "pytest>=7.0",
    "pytest-cov>=4.0",
    "pytest-asyncio>=0.20",
]

# All extras combined
all = [
    "example-package[dev,docs,test]",
]
```

**Installing with extras:**

```bash
# Install with dev extras
pip install example-package[dev]

# Install with multiple extras
pip install example-package[dev,test]

# Install all extras
pip install example-package[all]

# Install in editable mode with extras
pip install -e ".[dev,test]"
```

## Semantic Versioning (SemVer)

Semantic Versioning provides a standard way to communicate changes through version numbers.

### Version Format: MAJOR.MINOR.PATCH

```text
1.2.3
│ │ │
│ │ └─ PATCH: Bug fixes (backward compatible)
│ └─── MINOR: New features (backward compatible)
└───── MAJOR: Breaking changes (incompatible API)
```

### When to Increment Each Component

#### MAJOR version (X.0.0)

- Breaking changes to public API
- Removing features
- Changing behavior in incompatible ways
- Renaming functions/classes users depend on

#### MINOR version (0.X.0)

- Adding new features (backward compatible)
- Deprecating features (not removing)
- Internal refactoring that doesn't affect API
- Performance improvements

#### PATCH version (0.0.X)

- Bug fixes
- Security patches
- Documentation updates
- Internal changes with no API impact

### Pre-Release Versions

Semantic Versioning supports pre-release identifiers:

```text
1.0.0-alpha     # Alpha (early testing)
1.0.0-alpha.1   # Numbered alpha
1.0.0-beta      # Beta (feature complete, testing)
1.0.0-beta.2    # Numbered beta
1.0.0-rc.1      # Release candidate
1.0.0           # Stable release
```

**Version precedence:**

```text
1.0.0-alpha < 1.0.0-alpha.1 < 1.0.0-beta < 1.0.0-beta.2 < 1.0.0-rc.1 < 1.0.0
```

### Version 0.x.x (Initial Development)

Major version zero (0.y.z) is for initial development:

- **Anything may change at any time**
- Public API should not be considered stable
- `0.1.0` for initial development release
- Increment minor for each release
- `1.0.0` defines the first stable public API

### Python's PEP 440 Extensions

PEP 440 extends SemVer with Python-specific conventions:

**Development releases:**

```text
1.0.0.dev0
1.0.0.dev1
```

**Post releases (patches after release):**

```text
1.0.0.post1
1.0.0.post2
```

**Local version identifiers:**

```text
1.0.0+ubuntu.1
1.0.0+20250117
```

**Epoch (for version scheme changes):**

```text
1!1.0.0  # Epoch 1, version 1.0.0
```

### Best Practices

1. **Start at 0.1.0** for initial development
2. **Increment to 1.0.0** when API is stable
3. **Follow SemVer strictly** after 1.0.0
4. **Document breaking changes** clearly
5. **Use pre-release versions** for testing
6. **Automate version bumping** to avoid errors

## Entry Points and Console Scripts

Entry points allow packages to expose Python functions as command-line tools or plugin interfaces.

### Console Scripts (CLI Tools)

Create command-line tools that execute Python functions:

```toml
[project.scripts]
mytool = "mypackage.cli:main"
myapp = "mypackage.app:run"
```

**After installation:**

```bash
mytool --help         # Runs mypackage.cli.main()
myapp --version       # Runs mypackage.app.run()
```

**Example implementation:**

```python
# src/mypackage/cli.py
import sys

def main():
    """Entry point for CLI tool."""
    print("Hello from mytool!")
    return 0

if __name__ == "__main__":
    sys.exit(main())
```

**With arguments (using click):**

```python
# src/mypackage/cli.py
import click

@click.command()
@click.option('--name', default='World', help='Name to greet')
@click.option('--count', default=1, help='Number of greetings')
def main(name, count):
    """Simple CLI tool example."""
    for _ in range(count):
        click.echo(f"Hello {name}!")

if __name__ == "__main__":
    main()
```

### GUI Scripts (Windows)

GUI scripts don't open a console window on Windows:

```toml
[project.gui-scripts]
mygui = "mypackage.gui:main"
```

On Windows, this creates `mygui.exe` (no console) instead of console-based executable.

### Custom Entry Points (Plugin Systems)

Define custom entry point groups for plugin discovery:

```toml
[project.entry-points."myapp.plugins"]
plugin_a = "mypackage.plugins:plugin_a"
plugin_b = "mypackage.plugins:plugin_b"
```

**Discovering plugins at runtime:**

```python
from importlib.metadata import entry_points

# Python 3.10+
plugins = entry_points(group='myapp.plugins')

for plugin in plugins:
    plugin_func = plugin.load()
    plugin_func()
```

**Common use cases:**

- Pytest plugins (`pytest11`)
- Flask extensions (`flask.extensions`)
- Django apps (`django.apps`)
- Custom application plugins

## Building Distributions

### Install Build Tool

```bash
# Install or upgrade build
python -m pip install --upgrade build
```

### Build Distributions

From the directory containing `pyproject.toml`:

```bash
# Build both source distribution and wheel
python -m build
```

This creates two files in `dist/`:

```text
dist/
├── example_package-0.1.0.tar.gz          # Source distribution (sdist)
└── example_package-0.1.0-py3-none-any.whl  # Wheel (built distribution)
```

**Build specific format:**

```bash
# Only source distribution
python -m build --sdist

# Only wheel
python -m build --wheel
```

### Distribution Types

#### Source Distribution (sdist)

- `.tar.gz` archive
- Contains source code and metadata
- Requires build step during installation
- Cross-platform (if pure Python)
- Larger file size
- Use when: Distributing packages with compiled extensions, ensuring users can inspect source

#### Wheel (Built Distribution)

- `.whl` file (ZIP archive)
- Pre-built, ready to install
- Fast installation (no build step)
- Platform-specific if includes compiled code
- Smaller file size
- Use when: Pure Python packages, distributing pre-compiled binaries

**Wheel naming convention:**

```text
example_package-0.1.0-py3-none-any.whl
│              │      │   │    │
│              │      │   │    └─ Platform (any = all platforms)
│              │      │   └────── ABI (none = pure Python)
│              │      └────────── Python version (py3 = Python 3)
│              └───────────────── Version
└──────────────────────────────── Package name
```

**Platform-specific wheels:**

```text
mypackage-1.0.0-cp312-cp312-manylinux_2_17_x86_64.whl  # Linux x86_64
mypackage-1.0.0-cp312-cp312-macosx_11_0_arm64.whl      # macOS ARM64
mypackage-1.0.0-cp312-cp312-win_amd64.whl              # Windows 64-bit
```

### Best Practices for Distribution

1. **Always upload source distribution** (tarball)
2. **Upload wheels for all supported platforms** (if platform-specific)
3. **Pure Python:** Single universal wheel (`py3-none-any`)
4. **Test builds** before uploading to PyPI

## Publishing to PyPI

### Create PyPI Account

1. **TestPyPI** (for testing): <https://test.pypi.org/account/register/>
2. **PyPI** (production): <https://pypi.org/account/register/>
3. Verify email address

### Create API Token

**TestPyPI:**

1. Go to <https://test.pypi.org/manage/account/#api-tokens>
2. Click "Add API token"
3. Set scope: "Entire account" or specific project
4. Copy token (starts with `pypi-`) - **you won't see it again**

**PyPI:**

1. Go to <https://pypi.org/manage/account/#api-tokens>
2. Same process as TestPyPI

### Install Twine

```bash
python -m pip install --upgrade twine
```

### Upload to TestPyPI (Testing)

```bash
# Upload to TestPyPI
python -m twine upload --repository testpypi dist/*
```

**Enter credentials:**

- Username: `__token__`
- Password: Your API token (including `pypi-` prefix)

**Verify upload:**

Visit: `https://test.pypi.org/project/YOUR-PACKAGE-NAME/`

**Install from TestPyPI:**

```bash
# Install without dependencies (TestPyPI may not have them)
pip install --index-url https://test.pypi.org/simple/ --no-deps your-package-name

# Install with dependencies from PyPI
pip install --index-url https://test.pypi.org/simple/ --extra-index-url https://pypi.org/simple/ your-package-name
```

### Upload to PyPI (Production)

```bash
# Upload to PyPI (production)
python -m twine upload dist/*
```

**Enter credentials:**

- Username: `__token__`
- Password: Your PyPI API token

**Verify upload:**

Visit: `https://pypi.org/project/YOUR-PACKAGE-NAME/`

**Install from PyPI:**

```bash
pip install your-package-name
```

### Configure .pypirc (Optional)

Store repository configuration in `~/.pypirc`:

```ini
[distutils]
index-servers =
    pypi
    testpypi

[pypi]
username = __token__
password = pypi-YOUR-API-TOKEN-HERE

[testpypi]
repository = https://test.pypi.org/legacy/
username = __token__
password = pypi-YOUR-TESTPYPI-API-TOKEN-HERE
```

**Security note:** Keep `.pypirc` private (permissions 600 on Unix).

**Upload using .pypirc:**

```bash
# Upload to TestPyPI
twine upload --repository testpypi dist/*

# Upload to PyPI
twine upload --repository pypi dist/*
```

## Version Management

### Manual Version Bumping

**Update version in pyproject.toml:**

```toml
[project]
version = "0.2.0"  # Manually update
```

**Or in `__init__.py` (if using dynamic versioning):**

```python
# src/mypackage/__init__.py
__version__ = "0.2.0"
```

### Using bump2version / bumpversion

Automate version bumping across files:

**Install:**

```bash
pip install bump2version
```

**Create `.bumpversion.cfg`:**

```ini
[bumpversion]
current_version = 0.1.0
commit = True
tag = True

[bumpversion:file:pyproject.toml]
search = version = "{current_version}"
replace = version = "{new_version}"

[bumpversion:file:src/mypackage/__init__.py]
search = __version__ = "{current_version}"
replace = __version__ = "{new_version}"
```

**Bump version:**

```bash
# Patch version (0.1.0 -> 0.1.1)
bump2version patch

# Minor version (0.1.1 -> 0.2.0)
bump2version minor

# Major version (0.2.0 -> 1.0.0)
bump2version major
```

This automatically:

1. Updates version in all configured files
2. Commits changes
3. Creates git tag

### Git Tags for Releases

Tag releases with version numbers:

```bash
# Create annotated tag
git tag -a v1.0.0 -m "Release version 1.0.0"

# Push tag to remote
git push origin v1.0.0

# Push all tags
git push --tags
```

**Tag naming conventions:**

- `v1.0.0` (with 'v' prefix)
- `1.0.0` (without prefix)

Choose one convention and stick to it.

### CHANGELOG.md

Maintain a changelog following [Keep a Changelog](https://keepachangelog.com/):

```markdown
# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Feature X for new functionality

### Changed
- Improved performance of Y

### Fixed
- Bug in Z module

## [1.0.0] - 2025-01-17

### Added
- Initial stable release
- Core functionality A, B, C

### Changed
- Migrated from setup.py to pyproject.toml

### Deprecated
- Function `old_function` (use `new_function` instead)

### Removed
- Deprecated `legacy_module`

### Fixed
- Critical bug in authentication

### Security
- Fixed vulnerability CVE-2024-XXXX

## [0.1.0] - 2024-12-01

### Added
- Initial release
```

## README, LICENSE, and Documentation

### README.md Best Practices

Your README is the first thing users see on PyPI and GitHub. Make it count.

**Essential sections:**

Your README should include:

- Project title and one-line description
- Badges (PyPI version, Python versions, license)
- Features list
- Installation instructions
- Quick start example
- Link to full documentation
- Contributing guidelines
- License information
- Changelog reference

**Example structure:**

```markdown
# Project Name

Brief one-line description.

## Features

- Feature 1
- Feature 2
- Feature 3

## Installation

pip install your-package

## Quick Start

See documentation for usage examples.

## Documentation

Full documentation: https://your-package.readthedocs.io

## Contributing

Contributions welcome! Please read CONTRIBUTING.md

## License

MIT License - see LICENSE file
```

**Tips:**

- Keep it concise (users skim)
- Show code examples early
- Use badges for quick info (version, build status, coverage)
- Link to full documentation
- Include installation instructions prominently

### Choosing a License

**Popular open-source licenses:**

**MIT License** (Permissive)

- Simple, permissive
- Minimal restrictions
- Commercial use allowed
- Best for: Most open-source projects

**Apache 2.0** (Permissive with patent protection)

- Permissive like MIT
- Includes patent grant
- Requires attribution
- Best for: Projects concerned about patents

**GPL 3.0** (Copyleft)

- Requires derivative works to be open-source
- Strong copyleft
- Best for: Projects wanting to ensure derivatives stay open

**BSD 3-Clause** (Permissive)

- Similar to MIT
- Slightly more explicit
- Best for: Academic projects

**Resources:**

- <https://choosealicense.com/> (interactive license chooser)
- <https://opensource.org/licenses> (OSI-approved licenses)
- <https://spdx.org/licenses/> (SPDX identifiers for pyproject.toml)

### Documentation Hosting

**Read the Docs** (recommended)

- Free for open-source
- Automatic builds from git
- Version switching
- Search functionality
- Sphinx or MkDocs support

**Setup:**

1. Write documentation with Sphinx or MkDocs
2. Create `.readthedocs.yaml`
3. Import project at <https://readthedocs.org>
4. Automatic builds on git push

**Example .readthedocs.yaml:**

```yaml
version: 2

build:
  os: ubuntu-22.04
  tools:
    python: "3.11"

sphinx:
  configuration: docs/conf.py

python:
  install:
    - method: pip
      path: .
      extra_requirements:
        - docs
```

## CI/CD for Packaging

### GitHub Actions for Automated Publishing

Automate building and publishing when you create a git tag:

```yaml
# .github/workflows/publish.yml
name: Publish to PyPI

on:
  push:
    tags:
      - 'v*.*.*'  # Trigger on version tags (v1.0.0, v2.1.3, etc.)

jobs:
  build-and-publish:
    runs-on: ubuntu-latest

    steps:
    - name: Check out code
      uses: actions/checkout@v4

    - name: Set up Python
      uses: actions/setup-python@v5
      with:
        python-version: '3.11'

    - name: Install build dependencies
      run: |
        python -m pip install --upgrade pip
        pip install build twine

    - name: Build distributions
      run: python -m build

    - name: Check distributions
      run: twine check dist/*

    - name: Publish to PyPI
      env:
        TWINE_USERNAME: __token__
        TWINE_PASSWORD: ${{ secrets.PYPI_API_TOKEN }}
      run: twine upload dist/*
```

**Setup:**

1. Add API token to GitHub Secrets:
   - Go to repository Settings → Secrets → Actions
   - Add secret named `PYPI_API_TOKEN`
   - Paste your PyPI API token

2. Create workflow file (above)

3. Create and push a tag:

   ```bash
   git tag -a v1.0.0 -m "Release 1.0.0"
   git push origin v1.0.0
   ```

4. GitHub Actions automatically builds and publishes

### Testing Before Publishing

Add a test job before publishing:

```yaml
# .github/workflows/test-and-publish.yml
name: Test and Publish

on:
  push:
    tags:
      - 'v*.*.*'

jobs:
  test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        python-version: ['3.8', '3.9', '3.10', '3.11', '3.12']

    steps:
    - uses: actions/checkout@v4

    - name: Set up Python ${{ matrix.python-version }}
      uses: actions/setup-python@v5
      with:
        python-version: ${{ matrix.python-version }}

    - name: Install dependencies
      run: |
        pip install -e ".[test]"

    - name: Run tests
      run: pytest

  publish:
    needs: test  # Only publish if tests pass
    runs-on: ubuntu-latest

    steps:
    - uses: actions/checkout@v4

    - name: Set up Python
      uses: actions/setup-python@v5
      with:
        python-version: '3.11'

    - name: Build and publish
      env:
        TWINE_USERNAME: __token__
        TWINE_PASSWORD: ${{ secrets.PYPI_API_TOKEN }}
      run: |
        pip install build twine
        python -m build
        twine upload dist/*
```

### Publishing to TestPyPI First

Test publishing pipeline with TestPyPI:

```yaml
# .github/workflows/test-publish.yml
name: Publish to TestPyPI

on:
  push:
    tags:
      - 'v*.*.*-rc*'  # Release candidates (v1.0.0-rc1)

jobs:
  publish:
    runs-on: ubuntu-latest

    steps:
    - uses: actions/checkout@v4

    - name: Set up Python
      uses: actions/setup-python@v5
      with:
        python-version: '3.11'

    - name: Build and publish to TestPyPI
      env:
        TWINE_USERNAME: __token__
        TWINE_PASSWORD: ${{ secrets.TESTPYPI_API_TOKEN }}
      run: |
        pip install build twine
        python -m build
        twine upload --repository testpypi dist/*
```

## Common Pitfalls and Solutions

### 1. Missing Dependencies in Built Packages

**Problem:** Package installs but imports fail due to missing dependencies.

**Solution:** Ensure all runtime dependencies are in `[project.dependencies]`:

```toml
[project]
dependencies = [
    "requests>=2.28.0",  # Don't forget this!
]
```

**Verify:** Install package in clean virtual environment and test imports.

### 2. Incorrect Version Specifiers

**Problem:** Too restrictive (`==1.0.0`) or too loose (`>=1.0`) version pins.

**Solution:** Use compatible release specifiers:

```toml
dependencies = [
    "requests~=2.28.0",  # Compatible: >=2.28.0, <2.29.0
    "click>=8.0,<9.0",   # Major version range
]
```

### 3. Platform-Specific Dependencies Not Handled

**Problem:** Dependencies needed only on certain platforms installed everywhere.

**Solution:** Use environment markers:

```toml
dependencies = [
    "pywin32>=1.0; sys_platform=='win32'",
    "python-daemon>=2.0; sys_platform!='win32'",
]
```

### 4. Missing Files in Distribution

**Problem:** Files present in git but missing from built package.

**Solution:** Check build backend configuration:

**Hatchling:**

```toml
[tool.hatch.build.targets.sdist]
include = [
    "/src",
    "/tests",
    "/README.md",
    "/LICENSE",
]
```

**Setuptools:**

```toml
[tool.setuptools.packages.find]
where = ["src"]
include = ["mypackage*"]
```

**Verify:** Extract built wheel and check contents:

```bash
unzip -l dist/mypackage-1.0.0-py3-none-any.whl
```

### 5. Import Errors After Installation

**Problem:** Package installs but `import mypackage` fails.

**Common causes:**

1. **Wrong directory structure** (missing `__init__.py`)
2. **Package not in src/** (use src layout)
3. **Circular imports** in `__init__.py`

**Solution:** Use src layout and minimal `__init__.py`:

```python
# src/mypackage/__init__.py
__version__ = "1.0.0"

# Import public API
from .module import main_function

__all__ = ["main_function"]
```

### 6. Version String Mismatch

**Problem:** Version in different files doesn't match.

**Solution:** Single source of truth with dynamic versioning:

```toml
[tool.hatch.version]
path = "src/mypackage/__init__.py"

[project]
dynamic = ["version"]
```

```python
# src/mypackage/__init__.py
__version__ = "1.0.0"
```

### 7. Large Package Sizes

**Problem:** Wheel includes unnecessary files (tests, docs, cache files).

**Solution:** Exclude unwanted files:

```toml
[tool.hatch.build.targets.wheel]
packages = ["src/mypackage"]
exclude = [
    "**/__pycache__",
    "**/*.pyc",
    "tests/",
    "docs/",
]
```

### 8. Console Script Not Found After Install

**Problem:** Installed package but `mytool` command not found.

**Causes:**

1. Scripts directory not in PATH
2. Wrong entry point format

**Solution:** Verify entry point syntax:

```toml
[project.scripts]
mytool = "mypackage.cli:main"  # Correct: module.submodule:function
# NOT: mytool = "mypackage/cli.py:main"  # Wrong
```

**Check PATH:**

```bash
# Unix/macOS
echo $PATH
python -m site --user-base

# Windows
echo %PATH%
py -m site --user-base
```

### 9. Upload Conflicts

**Problem:** `File already exists` error when uploading.

**Cause:** Same version uploaded twice (PyPI doesn't allow overwrites).

**Solution:** Bump version before re-uploading:

```bash
# Increment version in pyproject.toml
# Then rebuild and upload
python -m build
twine upload dist/*
```

**Prevention:** Use CI/CD to automate versioning.

### 10. README Not Rendering on PyPI

**Problem:** README appears as plain text instead of formatted Markdown.

**Solution:** Ensure `readme` field points to Markdown file:

```toml
[project]
readme = "README.md"  # Extension must be .md
```

**Verify locally:**

```bash
twine check dist/*
```

## Complete Workflow Example

### Step-by-Step: First Package Release

**1. Initialize project structure:**

```bash
mkdir my-project && cd my-project
mkdir -p src/mypackage tests
touch src/mypackage/__init__.py
touch src/mypackage/module.py
touch tests/__init__.py
touch README.md LICENSE pyproject.toml
```

**2. Write code:**

```python
# src/mypackage/__init__.py
__version__ = "0.1.0"

from .module import hello

__all__ = ["hello"]
```

```python
# src/mypackage/module.py
def hello(name="World"):
    """Return a greeting."""
    return f"Hello, {name}!"
```

**3. Create pyproject.toml:**

```toml
[build-system]
requires = ["hatchling >= 1.26"]
build-backend = "hatchling.build"

[project]
name = "mypackage-username"  # Use your username
version = "0.1.0"
description = "A simple example package"
readme = "README.md"
requires-python = ">=3.8"
license = "MIT"
authors = [
    {name = "Your Name", email = "you@example.com"},
]
```

**4. Write README.md:**

```markdown
# My Package

A simple example package.

## Installation

pip install mypackage-username

## Usage

from mypackage import hello
print(hello("Python"))
```

**5. Add LICENSE (MIT example):**

```text
MIT License

Copyright (c) 2025 Your Name

Permission is hereby granted, free of charge...
[Full MIT license text from https://choosealicense.com/licenses/mit/]
```

**6. Build distributions:**

```bash
# Install build tool
pip install build

# Build
python -m build
```

**7. Upload to TestPyPI:**

```bash
# Install twine
pip install twine

# Upload
python -m twine upload --repository testpypi dist/*
```

**8. Test installation:**

```bash
# Create test environment
python -m venv test-env
source test-env/bin/activate  # Windows: test-env\Scripts\activate

# Install from TestPyPI
pip install --index-url https://test.pypi.org/simple/ --no-deps mypackage-username

# Test
python -c "from mypackage import hello; print(hello())"
```

**9. Upload to PyPI (production):**

```bash
# Same version can't be uploaded to both TestPyPI and PyPI
# If already uploaded to TestPyPI, bump version first

# Upload to PyPI
twine upload dist/*
```

**10. Install and verify:**

```bash
# Clean environment
deactivate
rm -rf test-env
python -m venv prod-env
source prod-env/bin/activate

# Install from PyPI
pip install mypackage-username

# Verify
python -c "from mypackage import hello; print(hello())"
```

## Summary

Modern Python packaging centers on **pyproject.toml** and PEP 517/518/621 standards:

1. **Project structure:** Use src/ layout for packages
2. **Build backend:** Choose based on needs (Hatchling for pure Python, Setuptools for extensions)
3. **Metadata:** Declare in `[project]` table
4. **Dependencies:** Runtime in `dependencies`, optional in `optional-dependencies`
5. **Versioning:** Follow Semantic Versioning (MAJOR.MINOR.PATCH)
6. **Building:** Use `python -m build` to create distributions
7. **Publishing:** Use Twine to upload to PyPI
8. **Automation:** Use GitHub Actions for CI/CD

**Resources:**

- [Python Packaging User Guide](https://packaging.python.org/)
- [PyPI](https://pypi.org/) and [TestPyPI](https://test.pypi.org/)
- [Semantic Versioning](https://semver.org/)
- [Choose a License](https://choosealicense.com/)
- [Keep a Changelog](https://keepachangelog.com/)

**Last Verified:** 2025-01-17

**Sources:** Python Packaging User Guide (packaging.python.org), PEP 517, PEP 518, PEP 621, PEP 440, PEP 639, Semantic Versioning 2.0.0 (semver.org), Python official documentation
