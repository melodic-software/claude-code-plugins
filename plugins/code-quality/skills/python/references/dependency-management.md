# Python Dependency Management Guide

Python dependency management has evolved significantly, with modern tools offering substantial improvements over traditional approaches. This guide covers the current landscape of dependency management tools, best practices, and workflows for Python projects in 2024-2025.

**Official Sources:**

- uv: <https://docs.astral.sh/uv/>
- Poetry: <https://python-poetry.org/docs/>
- pip: <https://pip.pypa.io/en/stable/>
- venv: <https://docs.python.org/3/library/venv.html>
- PEP 621 (pyproject.toml): <https://peps.python.org/pep-0621/>
- PEP 508 (Dependency Specification): <https://peps.python.org/pep-0508/>

## Table of Contents

- [Tool Comparison](#tool-comparison)
- [uv (Recommended for New Projects)](#uv-recommended-for-new-projects)
- [Poetry (Feature-Rich Alternative)](#poetry-feature-rich-alternative)
- [pip + venv (Traditional Approach)](#pip--venv-traditional-approach)
- [Virtual Environments Deep Dive](#virtual-environments-deep-dive)
- [pyproject.toml Standard](#pyprojecttoml-standard)
- [Lock Files](#lock-files)
- [Dependency Specification](#dependency-specification)
- [Development vs Production Dependencies](#development-vs-production-dependencies)
- [Troubleshooting](#troubleshooting)
- [Official Documentation](#official-documentation)
- [Last Verified](#last-verified)

## Tool Comparison

The Python ecosystem offers several dependency management solutions, each with distinct trade-offs:

| Feature | pip + venv | Poetry | uv |
| --- | --- | --- | --- |
| --- | --- | --- | --- |
| --- | --- | --- | --- |
| **Project init** | Manual | `poetry new/init` | `uv init` |
| --- | --- | --- | --- |
| --- | --- | --- | --- |
| **Dependency groups** | None | Full support | Limited (via optional deps) |
| --- | --- | --- | --- |
| **pyproject.toml** | Manual setup | Full support | Full support |
| **Maturity** | Very mature | Mature (v2.0+) | New (2024+) |
| **Ecosystem adoption** | Universal | Widespread | Rapidly growing |

**Performance characteristics:**

- **uv**: Written in Rust, parallelized operations, 10-100x faster than pip for installs and resolution
- **Poetry**: Python-based, faster than pip but slower than uv
- **pip**: Standard tool, slowest but most universally compatible

**When to use each:**

- **uv**: New projects prioritizing speed, modern workflows, minimal configuration
- **Poetry**: Projects needing rich dependency groups, mature ecosystem, extensive features
- **pip + venv**: Legacy projects, minimal dependencies, maximum compatibility

## uv (Recommended for New Projects)

uv is an extremely fast Python package and project manager written in Rust by Astral (creators of Ruff). It's designed as a modern replacement for pip, pip-tools, pipx, poetry, pyenv, and more.

**Key advantages:**

- 10-100x faster than pip
- Single tool replacing multiple utilities
- Automatic Python version management
- Universal lockfile for reproducibility
- Minimal configuration required

### Installation (uv)

**macOS and Linux:**

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
```

**Windows:**

```powershell
powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"
```

**Alternative (using pip):**

```bash
pip install uv
```

**Verify installation:**

```bash
uv --version
```

### Creating Projects (uv)

**Initialize a new project:**

```bash
uv init my-project
cd my-project
```

This creates:

- `pyproject.toml` with project metadata
- `.python-version` for Python version pinning
- Basic directory structure

**Initialize in existing directory:**

```bash
uv init
```

### Managing Dependencies (uv)

**Add a dependency:**

```bash
uv add requests
```

This automatically:

- Updates `pyproject.toml`
- Creates/updates `uv.lock`
- Installs the package in the virtual environment

**Add development dependencies:**

```bash
uv add --dev pytest ruff black
```

**Add with version constraints:**

```bash
uv add "requests>=2.31.0,<3.0.0"
uv add "pydantic~=2.5.0"
```

**Remove a dependency:**

```bash
uv remove requests
```

### Virtual Environments

**uv automatically manages virtual environments.** When you run `uv add` or `uv run`, uv creates a `.venv` directory if it doesn't exist.

**Create virtual environment manually:**

```bash
uv venv
```

**Use specific Python version:**

```bash
uv venv --python 3.12
```

**Activate virtual environment:**

```bash
# macOS/Linux
source .venv/bin/activate

# Windows
.venv\Scripts\activate
```

**However, activation is usually unnecessary** — use `uv run` instead:

```bash
uv run python script.py
uv run pytest
```

### Lock Files (uv)

uv uses `uv.lock` to ensure reproducible installations across environments.

**Generate/update lock file:**

```bash
uv lock
```

**Install from lock file:**

```bash
uv sync
```

**Update dependencies to latest compatible versions:**

```bash
uv lock --upgrade
```

**Lock files should be committed to version control** to ensure all team members use identical dependency versions.

### Python Version Management

**Install Python versions:**

```bash
uv python install 3.12
uv python install 3.11 3.10
```

**Pin project to specific Python version:**

```bash
uv python pin 3.12
```

This creates `.python-version` file.

**List available Python versions:**

```bash
uv python list
```

### Complete Workflow Example (uv)

```bash
# Initialize new project
uv init my-api
cd my-api

# Pin Python version
uv python pin 3.12

# Add dependencies
uv add fastapi uvicorn pydantic

# Add development dependencies
uv add --dev pytest ruff black mypy

# Lock dependencies
uv lock

# Run application
uv run python -m uvicorn main:app --reload

# Run tests
uv run pytest

# Format code
uv run black .
uv run ruff check .
```

### pyproject.toml Example (uv)

```toml
[project]
name = "my-api"
version = "0.1.0"
description = "Example API project"
readme = "README.md"
requires-python = ">=3.12"
dependencies = [
    "fastapi>=0.109.0",
    "pydantic>=2.5.0",
    "uvicorn[standard]>=0.27.0",
]

[project.optional-dependencies]
dev = [
    "pytest>=7.4.0",
    "ruff>=0.1.6",
    "black>=23.12.0",
    "mypy>=1.7.0",
]

[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"
```

## Poetry (Feature-Rich Alternative)

Poetry is a mature, feature-rich dependency manager with excellent support for dependency groups and publishing workflows. Poetry 2.0+ (released January 2025) supports PEP 621 `[project]` sections in `pyproject.toml`.

### Installation

**Official installer (recommended):**

```bash
# macOS/Linux
curl -sSL https://install.python-poetry.org | python3 -

# Windows (PowerShell)
(Invoke-WebRequest -Uri https://install.python-poetry.org -UseBasicParsing).Content | py -
```

**Using pip (alternative):**

```bash
pip install poetry
```

**Verify installation:**

```bash
poetry --version
```

### Creating Projects (Poetry)

**Create new project with structure:**

```bash
poetry new my-project
cd my-project
```

Creates:

- `pyproject.toml` with Poetry configuration
- `my_project/` package directory
- `tests/` directory
- `README.md`

**Initialize in existing directory:**

```bash
poetry init
```

Interactive setup wizard guides you through configuration.

### Managing Dependencies (Poetry)

**Add a dependency:**

```bash
poetry add requests
```

**Add to development group:**

```bash
poetry add --group dev pytest black ruff
```

**Add with version constraints:**

```bash
poetry add "requests>=2.31.0,<3.0.0"
poetry add "pydantic^2.5.0"  # Poetry-specific: >=2.5.0,<3.0.0
```

**Remove a dependency:**

```bash
poetry remove requests
```

**Show installed packages:**

```bash
poetry show
poetry show --tree  # Show dependency tree
```

### Installing Dependencies

**Install all dependencies:**

```bash
poetry install
```

**Install only production dependencies (exclude dev groups):**

```bash
poetry install --without dev
```

**Install specific groups:**

```bash
poetry install --with docs,test
```

### Running Commands

**Run in virtual environment:**

```bash
poetry run python script.py
poetry run pytest
poetry run black .
```

**Activate shell in virtual environment:**

```bash
poetry shell
```

### Lock Files (pip-tools)

Poetry uses `poetry.lock` for reproducible installations.

**Generate/update lock file:**

```bash
poetry lock
```

**Update dependencies to latest compatible versions:**

```bash
poetry update
```

**Update specific package:**

```bash
poetry update requests
```

### Publishing to PyPI

**Build package:**

```bash
poetry build
```

**Publish to PyPI:**

```bash
poetry publish
```

**Build and publish:**

```bash
poetry publish --build
```

### Complete Workflow Example (Poetry)

```bash
# Create new project
poetry new my-library
cd my-library

# Add dependencies
poetry add requests httpx pydantic

# Add development dependencies
poetry add --group dev pytest black ruff mypy
poetry add --group docs sphinx sphinx-rtd-theme

# Install all dependencies
poetry install

# Run tests
poetry run pytest

# Format and lint
poetry run black .
poetry run ruff check .

# Build package
poetry build

# Publish to PyPI (requires credentials)
poetry publish
```

### pyproject.toml Example (Poetry)

**Traditional Poetry format:**

```toml
[tool.poetry]
name = "my-library"
version = "0.1.0"
description = "Example library"
authors = ["Your Name <you@example.com>"]
readme = "README.md"

[tool.poetry.dependencies]
python = "^3.11"
requests = "^2.31.0"
pydantic = "^2.5.0"

[tool.poetry.group.dev.dependencies]
pytest = "^7.4.0"
black = "^23.12.0"
ruff = "^0.1.6"
mypy = "^1.7.0"

[tool.poetry.group.docs.dependencies]
sphinx = "^7.2.0"
sphinx-rtd-theme = "^2.0.0"

[build-system]
requires = ["poetry-core"]
build-backend = "poetry.core.masonry.api"
```

**Poetry 2.0+ with PEP 621:**

```toml
[project]
name = "my-library"
version = "0.1.0"
description = "Example library"
authors = [{name = "Your Name", email = "you@example.com"}]
readme = "README.md"
requires-python = ">=3.11"
dependencies = [
    "requests>=2.31.0,<3.0.0",
    "pydantic>=2.5.0,<3.0.0",
]

[dependency-groups]
dev = [
    "pytest>=7.4.0",
    "black>=23.12.0",
    "ruff>=0.1.6",
]

[build-system]
requires = ["poetry-core"]
build-backend = "poetry.core.masonry.api"
```

## pip + venv (Traditional Approach)

The traditional approach using Python's built-in `venv` module and `pip` remains valid, especially for simple projects or when maximum compatibility is required.

### Creating Virtual Environments

**Create virtual environment:**

```bash
# Python 3.3+
python -m venv .venv

# Windows (if python3 not available)
py -m venv .venv
```

**Activate virtual environment:**

```bash
# macOS/Linux
source .venv/bin/activate

# Windows (Command Prompt)
.venv\Scripts\activate.bat

# Windows (PowerShell)
.venv\Scripts\Activate.ps1
```

**Deactivate:**

```bash
deactivate
```

### Managing Dependencies (pip + venv)

**Upgrade pip (recommended first step):**

```bash
python -m pip install --upgrade pip
```

**Install packages:**

```bash
pip install requests
pip install "requests>=2.31.0,<3.0.0"
```

**Install from requirements file:**

```bash
pip install -r requirements.txt
```

**Install development dependencies:**

```bash
pip install -r requirements-dev.txt
```

### Requirements Files

**Create requirements.txt:**

```bash
pip freeze > requirements.txt
```

**Manual requirements.txt (recommended):**

```txt
# requirements.txt
requests>=2.31.0,<3.0.0
pydantic~=2.5.0
httpx>=0.25.2
```

**Development requirements:**

```txt
# requirements-dev.txt
-r requirements.txt
pytest>=7.4.0
black>=23.12.0
ruff>=0.1.6
mypy>=1.7.0
```

The `-r requirements.txt` line includes production dependencies.

### Editable Installs

For local development of packages:

```bash
pip install -e .
```

Requires `pyproject.toml` or `setup.py` in current directory. Changes to source code are immediately reflected without reinstallation.

### Lock Dependencies with pip-tools

For reproducible builds, use `pip-tools`:

```bash
pip install pip-tools
```

**Create requirements.in:**

```txt
# requirements.in
requests>=2.31.0
pydantic>=2.5.0
```

**Compile to requirements.txt:**

```bash
pip-compile requirements.in
```

**Install from compiled requirements:**

```bash
pip-sync requirements.txt
```

### Complete Workflow Example (pip + venv)

```bash
# Create virtual environment
python -m venv .venv

# Activate
source .venv/bin/activate  # macOS/Linux
# or
.venv\Scripts\activate  # Windows

# Upgrade pip
python -m pip install --upgrade pip

# Install dependencies
pip install -r requirements.txt

# Install development dependencies
pip install -r requirements-dev.txt

# Install project in editable mode
pip install -e .

# Run application
python main.py

# Run tests
pytest

# When done
deactivate
```

### pyproject.toml with pip

Modern projects can use `pyproject.toml` with pip:

```toml
[project]
name = "my-package"
version = "0.1.0"
description = "Example package"
readme = "README.md"
requires-python = ">=3.11"
dependencies = [
    "requests>=2.31.0,<3.0.0",
    "pydantic>=2.5.0,<3.0.0",
]

[project.optional-dependencies]
dev = [
    "pytest>=7.4.0",
    "black>=23.12.0",
    "ruff>=0.1.6",
]

[build-system]
requires = ["setuptools>=68.0", "wheel"]
build-backend = "setuptools.build_meta"
```

**Install with optional dependencies:**

```bash
pip install -e ".[dev]"
```

## Virtual Environments Deep Dive

### Why Virtual Environments Matter

Virtual environments provide **isolation** for Python projects:

- **Dependency isolation**: Each project has independent package versions
- **Reproducibility**: Consistent environments across machines
- **Avoid conflicts**: Prevent version conflicts between projects
- **System protection**: Don't pollute system Python installation

### Virtual Environment Tools

| Tool | Description | Use Case |
| --- | --- | --- |
| --- | --- | --- |
| --- | --- | --- |
| --- | --- | --- |
| --- | --- | --- |
| **poetry env** | Managed by Poetry | Projects using Poetry |

### Best Practices (Virtual Environments)

**One environment per project:**

```text

├── .venv/          # Virtual environment (gitignored)
├── pyproject.toml  # Project configuration
└── src/            # Source code
```

**Convention: `.venv` or `venv` directory name** — most tools recognize these automatically.

**Never commit virtual environments to version control:**

```gitignore
# .gitignore
.venv/
venv/
env/
*.pyc
__pycache__/
```

**Recreate environments, don't move them:**

Virtual environments contain absolute paths. To move a project:

1. Delete old `.venv`
2. Recreate in new location: `python -m venv .venv`
3. Reinstall dependencies: `pip install -r requirements.txt`

### Virtual Environment Activation

**Activation modifies shell environment:**

- Prepends virtual environment's `bin/` (or `Scripts/`) to `PATH`
- Sets `VIRTUAL_ENV` environment variable
- Changes shell prompt to show environment name

**Activation is optional** when using absolute paths:

```bash
# Without activation
/path/to/project/.venv/bin/python script.py

# With activation
source /path/to/project/.venv/bin/activate
python script.py
```

**Modern tools (uv, poetry) handle activation automatically:**

```bash
# No activation needed
uv run python script.py
poetry run python script.py
```

## pyproject.toml Standard

`pyproject.toml` is the modern standard for Python project configuration, defined by PEP 518 and extended by PEP 621.

### Core Project Metadata (PEP 621)

```toml
[project]
name = "my-package"
version = "0.1.0"
description = "A short description"
readme = "README.md"
requires-python = ">=3.11"
license = {text = "MIT"}
authors = [
    {name = "Your Name", email = "you@example.com"}
]
keywords = ["example", "package"]
classifiers = [
    "Development Status :: 3 - Alpha",
    "Programming Language :: Python :: 3.11",
    "Programming Language :: Python :: 3.12",
]
dependencies = [
    "requests>=2.31.0,<3.0.0",
    "pydantic>=2.5.0,<3.0.0",
]
```

### Optional Dependencies (Extras)

```toml
[project.optional-dependencies]
dev = [
    "pytest>=7.4.0",
    "black>=23.12.0",
    "ruff>=0.1.6",
]
docs = [
    "sphinx>=7.2.0",
    "sphinx-rtd-theme>=2.0.0",
]
all = [
    "my-package[dev,docs]",  # Include all extras
]
```

**Install with extras:**

```bash
pip install "my-package[dev]"
pip install "my-package[dev,docs]"
uv add "my-package[dev]"
poetry add "my-package[extras]" --extras dev
```

### Dependency Groups (Modern Alternative)

PEP 735 defines dependency groups as an alternative to optional dependencies:

```toml
[dependency-groups]
dev = [
    "pytest>=7.4.0",
    "ruff>=0.1.6",
]
test = [
    {include-group = "dev"},  # Include dev group
    "pytest-cov>=4.1.0",
]
```

**Supported by:** uv, some other modern tools (Poetry uses groups in `[tool.poetry.group.*]`)

### Build System Configuration

```toml
[build-system]
requires = ["setuptools>=68.0", "wheel"]
build-backend = "setuptools.build_meta"
```

**Common build backends:**

- `setuptools.build_meta` — Traditional setuptools
- `hatchling.build` — Modern, fast (used by uv)
- `poetry.core.masonry.api` — Poetry's build backend
- `flit_core.buildapi` — Lightweight alternative

### Tool-Specific Configuration

Tools can add their own sections:

```toml
[tool.uv]
dev-dependencies = [
    "pytest>=7.4.0",
]

[tool.poetry]
name = "my-package"
version = "0.1.0"

[tool.black]
line-length = 88
target-version = ['py311', 'py312']

[tool.ruff]
line-length = 88
select = ["E", "F", "I"]

[tool.pytest.ini_options]
testpaths = ["tests"]
python_files = ["test_*.py"]
```

## Lock Files

Lock files ensure **reproducible builds** by recording exact dependency versions.

### Purpose

**Problem:** Dependency specifiers like `requests>=2.31.0` are flexible — different installations might get different versions.

**Solution:** Lock files record exact versions installed, ensuring:

- Same versions across development, CI, and production
- Reproducible builds months or years later
- Protection against upstream breaking changes

### Lock File Comparison

| Tool | Lock File | Format | Contents |
| --- | --- | --- | --- |
| --- | --- | --- | --- |
| Poetry | `poetry.lock` | TOML | All dependencies with hashes |
| pip-tools | `requirements.txt` | Plain text | All dependencies with hashes (via `pip-compile`) |

### Using Lock Files

**uv:**

```bash
uv lock          # Generate/update lock file
uv sync          # Install from lock file
uv lock --upgrade  # Update all dependencies
```

**Poetry:**

```bash
poetry lock      # Generate/update lock file
poetry install   # Install from lock file
poetry update    # Update all dependencies
```

**pip-tools:**

```bash
pip-compile requirements.in    # Generate requirements.txt
pip-sync requirements.txt      # Install from lock file
pip-compile --upgrade requirements.in  # Update all
```

### Best Practices (Lock Files)

**Always commit lock files to version control:**

```bash
git add uv.lock poetry.lock requirements.txt
git commit -m "Update dependencies"
```

**Update lock files regularly:**

```bash
# Weekly or monthly
uv lock --upgrade
poetry update
pip-compile --upgrade requirements.in
```

**Use lock files in CI/CD:**

```yaml
# .github/workflows/test.yml
- name: Install dependencies
  run: uv sync  # or poetry install, or pip-sync
```

**Don't edit lock files manually** — always use tool commands.

## Dependency Specification

### PEP 508 Version Specifiers

Python uses PEP 440 version specifiers in PEP 508 dependency strings:

| Specifier | Meaning | Example | Matches |
| --- | --- | --- | --- |
| `==` | Exact version | `==1.2.3` | 1.2.3 only |
| `!=` | Not this version | `!=1.2.3` | Any except 1.2.3 |
| `>=` | Greater or equal | `>=1.2.3` | 1.2.3, 1.2.4, 2.0.0, etc. |
| `<=` | Less or equal | `<=1.2.3` | 1.2.3, 1.2.2, 1.0.0, etc. |
| `>` | Greater than | `>1.2.3` | 1.2.4, 2.0.0, etc. |
| `<` | Less than | `<1.2.3` | 1.2.2, 1.0.0, etc. |
| `~=` | Compatible release | `~=1.2.3` | >=1.2.3, ==1.2.* |
| Combined | Multiple constraints | `>=1.2.3,<2.0.0` | 1.2.3 to 1.9.9 |

### Compatible Release Operator (~=)

The `~=` operator allows the **last specified version component** to increment:

```toml
dependencies = [
    "requests~=2.31.0",  # >=2.31.0, ==2.31.*
    "numpy~=1.25",       # >=1.25, ==1.*
]
```

**Equivalent to:**

```toml
dependencies = [
    "requests>=2.31.0,==2.31.*",
    "numpy>=1.25,==1.*",
]
```

### Poetry-Specific Version Operators

Poetry supports additional operators (not in PEP 508):

| Operator | Poetry Meaning | Equivalent |
| --- | --- | --- |
| `^` | Caret (major compatible) | `^1.2.3` = `>=1.2.3,<2.0.0` |
| `~` | Tilde (minor compatible) | `~1.2.3` = `>=1.2.3,<1.3.0` |

**These only work in Poetry's `[tool.poetry.dependencies]` sections**, not in PEP 621 `[project]` sections.

### Semantic Versioning (SemVer)

Python packaging follows semantic versioning:

```text

  1  .  2  .  3
```

- **MAJOR**: Breaking changes (incompatible API changes)
- **MINOR**: New features (backward-compatible)
- **PATCH**: Bug fixes (backward-compatible)

### Version Constraint Recommendations

**For libraries (published to PyPI):**

```toml
# Be permissive — allow wide version ranges
dependencies = [
    "requests>=2.28.0",      # Minimum version only
    "pydantic>=2.0,<3.0",    # Exclude next major
]
```

**For applications (deployed services):**

```toml
# Be specific — use lock files for reproducibility
dependencies = [
    "requests>=2.31.0,<3.0.0",
    "pydantic>=2.5.0,<3.0.0",
]
```

**Always use lock files for applications** — version ranges become exact versions in lock files.

### Examples

```toml
[project]
dependencies = [
    # Exact version (rare — usually only for known issues)
    "broken-package==1.2.3",

    # Compatible release (common)
    "requests~=2.31.0",

    # Version range (common)
    "pydantic>=2.5.0,<3.0.0",

    # Minimum version (permissive for libraries)
    "httpx>=0.25.0",

    # Exclude broken version
    "numpy>=1.24.0,!=1.24.1,<2.0.0",

    # Complex constraints
    "django>=4.2,<5.0,!=4.2.3",
]
```

## Development vs Production Dependencies

### Separating Concerns

**Production dependencies:** Required for application to run

**Development dependencies:** Only needed during development (testing, linting, docs)

### Tool-Specific Approaches

**uv (via optional dependencies):**

```toml
[project]
dependencies = [
    "fastapi>=0.109.0",
    "uvicorn>=0.27.0",
]

[project.optional-dependencies]
dev = [
    "pytest>=7.4.0",
    "ruff>=0.1.6",
    "black>=23.12.0",
]
```

**Install:**

```bash
uv add fastapi uvicorn           # Production
uv add --dev pytest ruff black   # Development (adds to optional-dependencies.dev)
```

**Poetry (via groups):**

```toml
[tool.poetry.dependencies]
python = "^3.11"
fastapi = "^0.109.0"
uvicorn = "^0.27.0"

[tool.poetry.group.dev.dependencies]
pytest = "^7.4.0"
ruff = "^0.1.6"
black = "^23.12.0"
```

**Install:**

```bash
poetry install               # All groups
poetry install --without dev # Production only
poetry install --only dev    # Development only
```

**pip (via separate files):**

```txt
# requirements.txt (production)
fastapi>=0.109.0
uvicorn>=0.27.0

# requirements-dev.txt (development)
-r requirements.txt
pytest>=7.4.0
ruff>=0.1.6
black>=23.12.0
```

**Install:**

```bash
pip install -r requirements.txt      # Production
pip install -r requirements-dev.txt  # Development
```

### Container Best Practices

**Dockerfile for production** (exclude dev dependencies):

**Using uv:**

```dockerfile
FROM python:3.12-slim
WORKDIR /app

COPY pyproject.toml uv.lock ./
RUN pip install uv && uv sync --frozen --no-dev

COPY . .
CMD ["uv", "run", "python", "-m", "uvicorn", "main:app"]
```

**Using Poetry:**

```dockerfile
FROM python:3.12-slim
WORKDIR /app

COPY pyproject.toml poetry.lock ./
RUN pip install poetry && poetry install --without dev --no-root

COPY . .
CMD ["poetry", "run", "uvicorn", "main:app"]
```

**Using pip:**

```dockerfile
FROM python:3.12-slim
WORKDIR /app

COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

COPY . .
CMD ["python", "-m", "uvicorn", "main:app"]
```

## Troubleshooting

### Dependency Conflicts

**Problem:** Two packages require incompatible versions of the same dependency.

**Solutions:**

**uv/Poetry:** Use resolver to find compatible versions:

```bash
uv lock --upgrade     # Re-resolve with latest compatible versions
poetry lock --no-update  # Re-resolve without upgrading
```

**pip:** Manually adjust version constraints or use `pip-compile`:

```bash
pip-compile --upgrade     # Re-resolve
pip-compile --resolver=backtracking  # Use backtracking resolver
```

**If unresolvable:** One dependency may need updating or replacement.

### Version Resolution Issues

**Problem:** Cannot find versions that satisfy requirements.

**Diagnosis:**

```bash
# uv
uv lock --verbose

# Poetry
poetry lock --verbose

# pip
pip install --dry-run -r requirements.txt
```

**Common causes:**

- Python version constraint too restrictive
- Dependency requires newer version than specified
- Package not available for your platform

**Solutions:**

- Relax version constraints
- Update Python version
- Check package platform compatibility

### Cache Clearing

**Problem:** Corrupted cache or stale package metadata.

**Solutions:**

**uv:**

```bash
uv cache clean
```

**Poetry:**

```bash
poetry cache clear pypi --all
```

**pip:**

```bash
pip cache purge
```

### Virtual Environment Activation Issues

**Problem:** Virtual environment not activating or wrong Python version.

**Windows PowerShell execution policy:**

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

**Wrong Python version:**

```bash
# Delete and recreate with correct Python
rm -rf .venv
python3.12 -m venv .venv
```

**uv/Poetry:** Let tools manage environments automatically:

```bash
uv run python --version    # Uses project Python
poetry run python --version
```

### Package Not Found

**Problem:** `ERROR: Could not find a version that satisfies the requirement`

**Causes:**

- Typo in package name
- Package not on PyPI (private package?)
- Package removed from PyPI
- Network/firewall issues

**Solutions:**

```bash
# Search PyPI
pip search package-name  # (deprecated, use pypi.org search)

# Check package exists
pip index versions package-name

# Use private index
pip install --index-url https://your-private-pypi.com package-name
```

### Import Errors After Installation

**Problem:** Package installed but import fails.

**Diagnosis:**

```bash
# Verify package installed
pip list | grep package-name
uv pip list | grep package-name
poetry show package-name

# Check Python path
python -c "import sys; print(sys.path)"

# Verify virtual environment active
which python
```

**Common causes:**

- Wrong virtual environment activated
- Package name differs from import name (`pip install Pillow` → `import PIL`)
- Installation incomplete

### Slow Dependency Resolution

**Problem:** Dependency resolution takes very long.

**Solutions:**

**Use uv** (10-100x faster than pip/poetry)

**Poetry:** Disable modern installer if issues:

```bash
poetry config installer.modern-installation false
```

**pip:** Use faster resolver (default in pip 20.3+):

```bash
pip install --use-feature=fast-deps
```

## Official Documentation

- **uv Documentation**: <https://docs.astral.sh/uv/>
- **Poetry Documentation**: <https://python-poetry.org/docs/>
- **pip Documentation**: <https://pip.pypa.io/en/stable/>
- **venv Documentation**: <https://docs.python.org/3/library/venv.html>
- **Python Packaging User Guide**: <https://packaging.python.org/>
- **PEP 518 (Build System Requirements)**: <https://peps.python.org/pep-0518/>
- **PEP 621 (Project Metadata)**: <https://peps.python.org/pep-0621/>
- **PEP 508 (Dependency Specification)**: <https://peps.python.org/pep-0508/>
- **PEP 735 (Dependency Groups)**: <https://peps.python.org/pep-0735/>

## Last Verified

**Date**: 2025-01-17

**Tool Versions Referenced**:

- uv: Latest stable (2024-2025)
- Poetry: 2.0+ (with PEP 621 support)
- pip: 25.3+
- Python: 3.11-3.14
