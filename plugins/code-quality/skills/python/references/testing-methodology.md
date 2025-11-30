# Python Testing Methodology Guide

This guide covers modern Python testing practices using pytest, the de facto standard testing framework for Python projects. pytest offers powerful features like fixtures, parametrization, and extensive plugin ecosystem while maintaining simplicity and readability.

**Official Sources:**

- pytest Documentation: <https://docs.pytest.org/en/stable/>
- pytest-cov (Coverage Plugin): <https://pytest-cov.readthedocs.io/>
- pytest-mock (Mocking Plugin): <https://pytest-mock.readthedocs.io/>

## Table of Contents

- [Why pytest (Modern Standard)](#why-pytest-modern-standard)
- [Test Discovery](#test-discovery)
- [Test Structure (AAA Pattern)](#test-structure-aaa-pattern)
- [Writing Tests](#writing-tests)
- [Fixtures](#fixtures)
- [Parametrization](#parametrization)
- [Exception Testing](#exception-testing)
- [Mocking and Patching](#mocking-and-patching)
- [Coverage](#coverage)
- [Test Organization](#test-organization)
- [Best Practices](#best-practices)
- [Common Patterns](#common-patterns)
- [Running Tests](#running-tests)
- [Configuration](#configuration)
- [Official Documentation](#official-documentation)

## Why pytest (Modern Standard)

pytest has become the modern standard for Python testing, replacing unittest for most new projects:

**Advantages over unittest:**

- **Simple assert statements**: Use native Python `assert` instead of `self.assertEqual()` methods
- **Better error reporting**: Detailed introspection shows actual values in failed assertions
- **Fixtures over setUp/tearDown**: More flexible, composable, and explicit dependency management
- **Parametrization built-in**: Test multiple inputs without code duplication
- **Rich plugin ecosystem**: pytest-cov, pytest-mock, pytest-asyncio, and hundreds more
- **Runs unittest tests**: Can execute existing unittest-based tests without modification

**Installation:**

```bash
# Using uv (recommended for modern Python projects)
uv add --dev pytest

# Or using pip
pip install pytest
```

**Verification:**

```bash
pytest --version
# Expected output: pytest 9.x.y
```

## Test Discovery

pytest automatically discovers tests using these conventions:

**File naming:**

- `test_*.py` or `*_test.py` files

**Function naming:**

- `test_*` prefixed functions (outside classes)
- `test_*` prefixed methods inside `Test*` prefixed classes (without `__init__`)

**Directory structure:**

```text
project/
├── src/
│   └── mypackage/
│       ├── __init__.py
│       └── module.py
└── tests/
    ├── __init__.py
    ├── test_module.py
    └── conftest.py
```

pytest will discover all `test_*.py` files and collect all `test_*` functions/methods.

## Test Structure (AAA Pattern)

Follow the **Arrange-Act-Assert (AAA)** pattern for clear, maintainable tests:

**Arrange**: Set up test data and conditions
**Act**: Execute the code being tested
**Assert**: Verify the results

```python
def test_user_registration():
    # Arrange: Set up test data
    username = "alice"
    email = "alice@example.com"

    # Act: Execute the functionality
    user = register_user(username, email)

    # Assert: Verify the outcome
    assert user.username == username
    assert user.email == email
    assert user.is_active is True
```

**Benefits:**

- **Clarity**: Each test phase is explicit
- **Readability**: Easy to understand what's being tested
- **Maintainability**: Changes to one phase don't affect others
- **Debugging**: Failures clearly indicate which phase broke

## Writing Tests

### Basic Test Example

```python
# content of test_math.py
def add(a, b):
    return a + b

def test_addition():
    # Arrange
    a, b = 2, 3

    # Act
    result = add(a, b)

    # Assert
    assert result == 5
```

### Assertions

pytest uses Python's native `assert` statement with powerful introspection:

```python
def test_string_operations():
    text = "hello world"

    # Simple assertions
    assert text == "hello world"
    assert "world" in text
    assert text.startswith("hello")
    assert len(text) == 11

    # Assertions with custom messages
    assert text.islower(), "Text should be lowercase"
```

**When assertions fail, pytest shows detailed information:**

```text
    def test_addition():
>       assert add(2, 3) == 6
E       assert 5 == 6
E        +  where 5 = add(2, 3)
```

### Approximate Equality (Floating Point)

Use `pytest.approx()` for floating-point comparisons:

```python
import pytest

def test_floating_point():
    result = 0.1 + 0.2
    assert result == pytest.approx(0.3)

def test_arrays():
    import numpy as np
    a = np.array([1.0, 2.0, 3.0])
    b = np.array([0.9999, 2.0001, 3.0])
    assert a == pytest.approx(b)
```

## Fixtures

Fixtures provide reusable test data, setup, and teardown logic. They are one of pytest's most powerful features.

### Basic Fixtures

```python
import pytest

@pytest.fixture
def sample_user():
    """Provides a sample user for testing."""
    return {
        "username": "alice",
        "email": "alice@example.com",
        "age": 30
    }

def test_user_data(sample_user):
    """Fixture is injected by name."""
    assert sample_user["username"] == "alice"
    assert sample_user["age"] == 30
```

### Fixture Scopes

Fixtures can have different scopes controlling their lifecycle:

**Function scope (default)**: Runs before each test function

```python
@pytest.fixture  # scope="function" is default
def database_connection():
    """New connection for each test."""
    conn = create_connection()
    yield conn
    conn.close()
```

**Module scope**: Runs once per test module (file)

```python
@pytest.fixture(scope="module")
def database_session():
    """Shared connection for all tests in module."""
    session = create_session()
    yield session
    session.close()
```

**Class scope**: Runs once per test class

```python
@pytest.fixture(scope="class")
def browser():
    """Browser instance shared across test class."""
    driver = webdriver.Chrome()
    yield driver
    driver.quit()
```

**Session scope**: Runs once per entire test session

```python
@pytest.fixture(scope="session")
def database():
    """Database setup for entire test suite."""
    db = setup_test_database()
    yield db
    teardown_test_database(db)
```

**Scope Usage Guidelines:**

- **Function**: Default choice; tests are independent
- **Module**: Expensive resources shared within a file
- **Class**: Shared state for related tests in a class
- **Session**: One-time setup for entire test run (use sparingly)

### Fixtures with Setup and Teardown

Use `yield` to separate setup and teardown:

```python
import pytest

@pytest.fixture
def temp_file():
    """Create temporary file, cleanup after test."""
    # Setup
    import tempfile
    f = tempfile.NamedTemporaryFile(delete=False)

    # Provide to test
    yield f.name

    # Teardown (runs after test completes)
    import os
    os.unlink(f.name)

def test_file_operations(temp_file):
    with open(temp_file, 'w') as f:
        f.write("test data")

    with open(temp_file, 'r') as f:
        assert f.read() == "test data"
```

### Autouse Fixtures

Fixtures that run automatically without being requested:

```python
@pytest.fixture(autouse=True)
def reset_database():
    """Runs before every test automatically."""
    clear_test_database()
    seed_test_data()

def test_user_count():
    # reset_database runs automatically before this test
    assert count_users() == 10
```

**Use autouse sparingly**: Only for setup that EVERY test needs.

### Sharing Fixtures with conftest.py

Place shared fixtures in `conftest.py` to make them available to all tests:

```python
# tests/conftest.py
import pytest

@pytest.fixture
def api_client():
    """Available to all tests in this directory and subdirectories."""
    from myapp import create_client
    client = create_client(base_url="http://test.example.com")
    yield client
    client.close()

@pytest.fixture
def authenticated_user():
    """Another shared fixture."""
    return {
        "user_id": 1,
        "username": "testuser",
        "token": "test-token-123"
    }
```

**conftest.py discovery:**

- pytest automatically discovers `conftest.py` files
- Fixtures are available to tests in same directory and subdirectories
- No imports needed; fixtures are injected by name

### Fixtures Depending on Other Fixtures

```python
import pytest

@pytest.fixture
def database():
    """Database connection."""
    db = create_db()
    yield db
    db.close()

@pytest.fixture
def user_repository(database):
    """User repository depends on database fixture."""
    return UserRepository(database)

def test_create_user(user_repository):
    """Uses user_repository which uses database."""
    user = user_repository.create("alice", "alice@example.com")
    assert user.username == "alice"
```

## Parametrization

Parametrization allows testing multiple inputs with a single test function, avoiding code duplication.

### Basic Parametrization

```python
import pytest

@pytest.mark.parametrize("input,expected", [
    (1, 2),
    (2, 4),
    (3, 6),
    (10, 20),
])
def test_double(input, expected):
    """Runs 4 times with different inputs."""
    assert double(input) == expected
```

**Test output shows each case:**

```text
test_math.py::test_double[1-2] PASSED
test_math.py::test_double[2-4] PASSED
test_math.py::test_double[3-6] PASSED
test_math.py::test_double[10-20] PASSED
```

### Multiple Parameters

```python
@pytest.mark.parametrize("a,b,expected", [
    (1, 1, 2),
    (2, 3, 5),
    (10, -5, 5),
    (0, 0, 0),
])
def test_addition(a, b, expected):
    assert add(a, b) == expected
```

### Descriptive Test IDs

Use `ids` parameter for readable test names:

```python
@pytest.mark.parametrize(
    "test_input,expected",
    [
        ("hello", True),
        ("hello123", False),
        ("", False),
    ],
    ids=["valid_string", "alphanumeric", "empty_string"]
)
def test_is_alpha(test_input, expected):
    assert test_input.isalpha() == expected
```

### Stacking Parametrize Decorators

Get all combinations by stacking decorators:

```python
@pytest.mark.parametrize("x", [0, 1])
@pytest.mark.parametrize("y", [2, 3])
def test_combinations(x, y):
    """Runs 4 times: (0,2), (1,2), (0,3), (1,3)"""
    assert isinstance(x + y, int)
```

### Parametrizing Fixtures

```python
import pytest

@pytest.fixture(params=["mysql", "postgresql", "sqlite"])
def database_type(request):
    """Test runs once for each database type."""
    return request.param

def test_query(database_type):
    """Runs 3 times with different databases."""
    db = create_connection(database_type)
    result = db.execute("SELECT 1")
    assert result is not None
```

### Marking Individual Parameters

```python
import pytest

@pytest.mark.parametrize(
    "input,expected",
    [
        (2, 4),
        (3, 9),
        pytest.param(4, 16, marks=pytest.mark.slow),
        pytest.param(5, 25, marks=pytest.mark.xfail),
    ]
)
def test_square(input, expected):
    assert square(input) == expected
```

## Exception Testing

Test that code raises expected exceptions using `pytest.raises`:

### Basic Exception Testing

```python
import pytest

def test_division_by_zero():
    """Test that dividing by zero raises ZeroDivisionError."""
    with pytest.raises(ZeroDivisionError):
        result = 1 / 0

def test_invalid_input():
    """Test exception with any input validation."""
    with pytest.raises(ValueError):
        create_user(age=-5)
```

### Inspecting Exception Details

```python
def test_exception_message():
    """Verify exception message content."""
    with pytest.raises(RuntimeError) as excinfo:
        raise RuntimeError("Something went wrong")

    assert "went wrong" in str(excinfo.value)

def test_exception_attributes():
    """Access exception attributes."""
    with pytest.raises(ValueError) as excinfo:
        raise ValueError("Invalid value: 42")

    # Check exception type, value, traceback
    assert excinfo.type is ValueError
    assert "Invalid value" in str(excinfo.value)
```

### Matching Exception Messages

```python
import pytest

def test_exception_with_regex():
    """Match exception message with regex."""
    with pytest.raises(ValueError, match=r"Invalid.*123"):
        raise ValueError("Invalid input: 123")

def test_exact_message():
    """Match exact substring."""
    with pytest.raises(ValueError, match="User not found"):
        delete_user(user_id=999)
```

### Testing Exception Groups (Python 3.11+)

```python
import pytest

def test_exception_group():
    """Test ExceptionGroup handling."""
    with pytest.raises(ExceptionGroup) as excinfo:
        raise ExceptionGroup(
            "Multiple errors",
            [ValueError("Error 1"), TypeError("Error 2")]
        )

    assert excinfo.group_contains(ValueError)
    assert excinfo.group_contains(TypeError)
```

## Mocking and Patching

Mocking isolates tests from external dependencies (APIs, databases, filesystem).

### pytest-mock Plugin (Recommended)

**Installation:**

```bash
uv add --dev pytest-mock
# or: pip install pytest-mock
```

pytest-mock provides the `mocker` fixture, a pytest-friendly wrapper around `unittest.mock`.

### Basic Mocking

```python
def test_api_call(mocker):
    """Mock external API call."""
    # Mock the requests.get function
    mock_get = mocker.patch('requests.get')
    mock_get.return_value.status_code = 200
    mock_get.return_value.json.return_value = {"user": "alice"}

    # Call function that uses requests.get
    response = fetch_user_data(user_id=1)

    # Verify mock was called correctly
    mock_get.assert_called_once_with('https://api.example.com/users/1')
    assert response["user"] == "alice"
```

### Mocking Return Values

```python
def test_database_query(mocker):
    """Mock database query."""
    mock_db = mocker.patch('myapp.database.get_connection')
    mock_db.return_value.execute.return_value = [
        {"id": 1, "name": "Alice"},
        {"id": 2, "name": "Bob"}
    ]

    users = get_all_users()
    assert len(users) == 2
    assert users[0]["name"] == "Alice"
```

### Mocking with Side Effects

```python
def test_retry_logic(mocker):
    """Test function retries on failure."""
    mock_api = mocker.patch('myapp.external_api.call')

    # First two calls raise exception, third succeeds
    mock_api.side_effect = [
        ConnectionError("Network error"),
        ConnectionError("Network error"),
        {"status": "success"}
    ]

    result = call_with_retry()
    assert result["status"] == "success"
    assert mock_api.call_count == 3
```

### Mocking Filesystem Operations

```python
def test_file_reading(mocker):
    """Mock file operations."""
    mock_open = mocker.patch('builtins.open', mocker.mock_open(read_data='test content'))

    data = read_config_file('/path/to/config.txt')

    mock_open.assert_called_once_with('/path/to/config.txt', 'r')
    assert data == 'test content'
```

### Mocking Environment Variables

```python
def test_environment_config(mocker):
    """Mock environment variables."""
    mocker.patch.dict('os.environ', {'API_KEY': 'test-key-123'})

    api_key = get_api_key()
    assert api_key == 'test-key-123'
```

### Spy (Partial Mocking)

```python
def test_spy_on_method(mocker):
    """Spy on method to verify calls while keeping real implementation."""
    calculator = Calculator()
    spy = mocker.spy(calculator, 'add')

    result = calculator.add(2, 3)

    # Real implementation runs
    assert result == 5
    # But we can verify it was called
    spy.assert_called_once_with(2, 3)
```

### Monkeypatch (Built-in Alternative)

pytest includes `monkeypatch` fixture for simpler cases:

```python
def test_with_monkeypatch(monkeypatch):
    """Use monkeypatch for simple mocking."""
    # Set environment variable
    monkeypatch.setenv('DEBUG', 'true')

    # Modify dict
    monkeypatch.setitem(app.config, 'TESTING', True)

    # Replace function
    monkeypatch.setattr('myapp.utils.get_time', lambda: 1234567890)

    # Automatically restored after test
```

## Coverage

Code coverage measures which lines of code are executed during tests.

### pytest-cov Plugin

**Installation:**

```bash
uv add --dev pytest-cov
# or: pip install pytest-cov
```

### Running Tests with Coverage

```bash
# Basic coverage report
pytest --cov=src

# Coverage with missing lines shown
pytest --cov=src --cov-report=term-missing

# HTML coverage report
pytest --cov=src --cov-report=html

# Multiple output formats
pytest --cov=src --cov-report=term-missing --cov-report=html
```

### Coverage Configuration

Add to `pyproject.toml`:

```toml
[tool.pytest.ini_options]
testpaths = ["tests"]
addopts = "--cov=src --cov-report=term-missing --cov-report=html"

[tool.coverage.run]
source = ["src"]
omit = ["*/tests/*", "*/test_*.py"]

[tool.coverage.report]
exclude_lines = [
    "pragma: no cover",
    "def __repr__",
    "raise AssertionError",
    "raise NotImplementedError",
    "if __name__ == .__main__.:",
    "if TYPE_CHECKING:",
]
```

### Coverage Targets

**Guidelines:**

- **80%+ for business logic**: Critical code should be well-tested
- **Lower for simple code**: Getters, setters, simple properties
- **100% not always necessary**: Diminishing returns on defensive code
- **Focus on meaningful coverage**: Testing behavior, not just lines

**Fail build if coverage too low:**

```bash
pytest --cov=src --cov-fail-under=80
```

### Interpreting Coverage Reports

```text
Name                    Stmts   Miss  Cover   Missing
-----------------------------------------------------
src/auth.py                45      3    93%   23-25
src/database.py            67      0   100%
src/utils.py               23      8    65%   15-18, 34-37
-----------------------------------------------------
TOTAL                     135     11    92%
```

- **Stmts**: Total statements
- **Miss**: Statements not executed
- **Cover**: Percentage covered
- **Missing**: Line numbers not covered

**HTML Report**: Open `htmlcov/index.html` to see line-by-line coverage with color coding.

## Test Organization

### Directory Structure

**Mirror source structure in tests:**

```text
project/
├── src/
│   └── mypackage/
│       ├── __init__.py
│       ├── auth.py
│       ├── database.py
│       └── utils.py
└── tests/
    ├── __init__.py
    ├── conftest.py          # Shared fixtures
    ├── test_auth.py         # Tests for auth.py
    ├── test_database.py     # Tests for database.py
    └── test_utils.py        # Tests for utils.py
```

### Test File Naming

- **Files**: `test_*.py` or `*_test.py`
- **Functions**: `test_<what>_<condition>_<expected>`
- **Classes**: `Test<Feature>` (no `__init__` method)

```python
# test_auth.py
def test_login_valid_credentials_returns_token():
    """Clear, descriptive test name."""
    pass

def test_login_invalid_password_raises_error():
    pass

class TestUserRegistration:
    def test_valid_email_creates_user(self):
        pass

    def test_duplicate_email_raises_error(self):
        pass
```

### conftest.py Usage

```python
# tests/conftest.py - root level
import pytest

@pytest.fixture(scope="session")
def database():
    """Available to all tests."""
    pass

# tests/integration/conftest.py - subdirectory
@pytest.fixture
def api_client():
    """Available to tests in integration/ and subdirectories."""
    pass
```

### Organizing with Test Classes (Optional)

```python
class TestUserAuthentication:
    """Group related tests in a class."""

    def test_login_success(self):
        pass

    def test_login_failure(self):
        pass

    def test_logout(self):
        pass
```

**Benefits**: Logical grouping, shared fixtures via class-scoped fixtures.

## Best Practices

### Tests Should Be Independent

**Bad - Tests depend on order:**

```python
user = None

def test_create_user():
    global user
    user = create_user("alice")
    assert user is not None

def test_update_user():
    # Breaks if run alone!
    global user
    user.email = "new@example.com"
    assert user.email == "new@example.com"
```

**Good - Each test is independent:**

```python
@pytest.fixture
def user():
    return create_user("alice")

def test_create_user(user):
    assert user is not None

def test_update_user(user):
    user.email = "new@example.com"
    assert user.email == "new@example.com"
```

### Tests Should Be Fast

- **Mock external dependencies**: Don't hit real APIs or databases in unit tests
- **Use in-memory databases**: SQLite `:memory:` for integration tests
- **Parallelize tests**: Use `pytest-xdist` for parallel execution
- **Appropriate scoping**: Use module/session fixtures for expensive setup

```bash
# Run tests in parallel (install pytest-xdist)
pytest -n auto
```

### Tests Should Be Deterministic

**Avoid:**

- Random values (use seeded random or fixed values)
- Current time (mock time or use fixed timestamps)
- Network dependencies (mock or use local test servers)
- Race conditions (avoid threading in tests unless testing concurrency)

**Good practices:**

```python
def test_timestamp_formatting(mocker):
    """Mock time for deterministic tests."""
    mocker.patch('time.time', return_value=1234567890)
    formatted = format_timestamp()
    assert formatted == "2009-02-13 23:31:30"
```

### One Logical Assertion Per Test (Generally)

**Prefer:**

```python
def test_user_creation_sets_username(user):
    assert user.username == "alice"

def test_user_creation_sets_email(user):
    assert user.email == "alice@example.com"

def test_user_creation_activates_user(user):
    assert user.is_active is True
```

**Over:**

```python
def test_user_creation(user):
    assert user.username == "alice"
    assert user.email == "alice@example.com"
    assert user.is_active is True
    # If first assertion fails, others don't run
```

**Exception**: Related assertions for single behavior are fine.

### Clear Test Names

Follow pattern: `test_<what>_<when>_<expected>`

```python
def test_divide_by_zero_raises_error():
    pass

def test_login_invalid_credentials_returns_401():
    pass

def test_calculate_discount_no_coupon_returns_full_price():
    pass
```

### Don't Test Implementation Details

**Bad - Tests implementation:**

```python
def test_user_storage_uses_dictionary():
    """Too coupled to implementation."""
    user_manager = UserManager()
    assert isinstance(user_manager._storage, dict)
```

**Good - Tests behavior:**

```python
def test_user_can_be_stored_and_retrieved():
    """Tests what matters."""
    user_manager = UserManager()
    user_manager.add_user("alice")
    assert user_manager.get_user("alice") is not None
```

## Common Patterns

### Testing Async Code

**Install pytest-asyncio:**

```bash
uv add --dev pytest-asyncio
```

**Write async tests:**

```python
import pytest

@pytest.mark.asyncio
async def test_async_fetch():
    """Test async function."""
    result = await fetch_data_async()
    assert result is not None

@pytest.fixture
async def async_client():
    """Async fixture."""
    client = AsyncHTTPClient()
    yield client
    await client.close()

@pytest.mark.asyncio
async def test_with_async_fixture(async_client):
    response = await async_client.get('/api/users')
    assert response.status == 200
```

### Testing Database Interactions

```python
import pytest

@pytest.fixture(scope="function")
def db_session():
    """Fresh database session for each test."""
    engine = create_engine("sqlite:///:memory:")
    Base.metadata.create_all(engine)
    Session = sessionmaker(bind=engine)
    session = Session()

    yield session

    session.close()

def test_create_user(db_session):
    user = User(username="alice", email="alice@example.com")
    db_session.add(user)
    db_session.commit()

    retrieved = db_session.query(User).filter_by(username="alice").first()
    assert retrieved.email == "alice@example.com"
```

### Testing Web APIs (requests/httpx)

```python
def test_api_endpoint(mocker):
    """Mock HTTP request."""
    mock_get = mocker.patch('requests.get')
    mock_get.return_value.status_code = 200
    mock_get.return_value.json.return_value = {"users": []}

    response = get_users()
    assert response == {"users": []}

# Alternative: Use responses library
import responses

@responses.activate
def test_api_with_responses():
    responses.add(
        responses.GET,
        'https://api.example.com/users',
        json={"users": []},
        status=200
    )

    response = get_users()
    assert response == {"users": []}
```

### Testing CLI Applications

```python
import pytest
from click.testing import CliRunner

def test_cli_command():
    """Test CLI using click's test runner."""
    runner = CliRunner()
    result = runner.invoke(cli, ['--help'])

    assert result.exit_code == 0
    assert 'Usage:' in result.output

def test_cli_with_arguments():
    runner = CliRunner()
    result = runner.invoke(cli, ['process', '--input', 'data.txt'])

    assert result.exit_code == 0
    assert 'Processing complete' in result.output
```

### Testing Exceptions and Errors

```python
def test_error_handling():
    """Test error scenarios."""
    with pytest.raises(ValueError, match="Invalid input"):
        process_data(invalid_input)

def test_retries_on_failure(mocker):
    """Test retry logic."""
    mock_func = mocker.Mock(side_effect=[
        Exception("Retry 1"),
        Exception("Retry 2"),
        "Success"
    ])

    result = retry_wrapper(mock_func, max_retries=3)
    assert result == "Success"
    assert mock_func.call_count == 3
```

## Running Tests

### Basic Commands

```bash
# Run all tests
pytest

# Verbose output
pytest -v

# Very verbose (show all output)
pytest -vv

# Quiet mode (minimal output)
pytest -q

# Show print statements
pytest -s
```

### Running Specific Tests

```bash
# Specific file
pytest tests/test_auth.py

# Specific function
pytest tests/test_auth.py::test_login

# Specific class
pytest tests/test_auth.py::TestAuthentication

# Specific method in class
pytest tests/test_auth.py::TestAuthentication::test_login

# Pattern matching
pytest -k "login"  # Runs all tests with "login" in name
```

### Test Selection by Markers

```python
# Mark tests
@pytest.mark.slow
def test_expensive_operation():
    pass

@pytest.mark.integration
def test_database_integration():
    pass
```

```bash
# Run only slow tests
pytest -m slow

# Run everything except slow tests
pytest -m "not slow"

# Run integration tests
pytest -m integration
```

### Useful Flags

```bash
# Stop after first failure
pytest -x

# Stop after N failures
pytest --maxfail=3

# Run last failed tests
pytest --lf

# Run failed tests first, then others
pytest --ff

# Show local variables in tracebacks
pytest -l

# Disable output capturing (see prints immediately)
pytest -s

# Generate JUnit XML report
pytest --junit-xml=report.xml
```

### Coverage Commands

```bash
# Run with coverage
pytest --cov=src

# Coverage with missing lines
pytest --cov=src --cov-report=term-missing

# HTML report
pytest --cov=src --cov-report=html

# Fail if coverage below threshold
pytest --cov=src --cov-fail-under=80
```

### Parallel Execution

```bash
# Install pytest-xdist
uv add --dev pytest-xdist

# Run tests in parallel (auto-detect CPU count)
pytest -n auto

# Run with specific number of workers
pytest -n 4
```

## Configuration

### pyproject.toml Configuration

Modern Python projects use `pyproject.toml` for configuration:

```toml
[tool.pytest.ini_options]
# Test discovery
testpaths = ["tests"]
python_files = ["test_*.py", "*_test.py"]
python_functions = ["test_*"]
python_classes = ["Test*"]

# Output and reporting
addopts = """
    -v
    --strict-markers
    --cov=src
    --cov-report=term-missing
    --cov-report=html
    --cov-fail-under=80
"""

# Markers
markers = [
    "slow: marks tests as slow (deselect with '-m \"not slow\"')",
    "integration: marks tests as integration tests",
    "unit: marks tests as unit tests",
]

# Ignore paths
norecursedirs = [
    ".git",
    ".tox",
    "dist",
    "build",
    "*.egg",
]

[tool.coverage.run]
source = ["src"]
omit = [
    "*/tests/*",
    "*/test_*.py",
    "*/__pycache__/*",
]

[tool.coverage.report]
precision = 2
show_missing = true
skip_covered = false

exclude_lines = [
    "pragma: no cover",
    "def __repr__",
    "raise AssertionError",
    "raise NotImplementedError",
    "if __name__ == .__main__.:",
    "if TYPE_CHECKING:",
    "@abstractmethod",
]
```

### pytest.ini (Alternative)

If not using `pyproject.toml`, use `pytest.ini`:

```ini
[pytest]
testpaths = tests
python_files = test_*.py
python_functions = test_*
addopts = -v --cov=src --cov-report=term-missing

markers =
    slow: marks tests as slow
    integration: marks tests as integration tests
```

### Common Configuration Options

```toml
[tool.pytest.ini_options]
# Minimum version
minversion = "8.0"

# Test discovery paths
testpaths = ["tests"]

# Add options to all pytest runs
addopts = "-ra -v --strict-markers"

# Timeout for tests (requires pytest-timeout)
timeout = 300

# Show warnings
filterwarnings = [
    "error",
    "ignore::DeprecationWarning",
]

# Custom markers
markers = [
    "slow",
    "integration",
    "unit",
]
```

## Official Documentation

- **pytest Documentation**: <https://docs.pytest.org/en/stable/>
  - How-to guides: <https://docs.pytest.org/en/stable/how-to/>
  - Fixtures guide: <https://docs.pytest.org/en/stable/how-to/fixtures.html>
  - Parametrization: <https://docs.pytest.org/en/stable/how-to/parametrize.html>
  - Assertions: <https://docs.pytest.org/en/stable/how-to/assert.html>
- **pytest-cov**: <https://pytest-cov.readthedocs.io/>
- **pytest-mock**: <https://pytest-mock.readthedocs.io/>
- **pytest Plugins**: <https://docs.pytest.org/en/stable/reference/plugin_list.html>

---

**Last Updated**: 2025-01-17
**Sources**: Official pytest documentation, pytest-cov documentation, pytest-mock documentation, Perplexity research on pytest best practices 2024-2025
