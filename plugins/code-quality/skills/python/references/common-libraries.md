# Common Libraries

Comprehensive guide to essential Python libraries for modern development, backed by official documentation.

**Last Verified:** 2025-01-17

---

## Table of Contents

1. [Standard Library Essentials](#standard-library-essentials)
2. [Web Frameworks](#web-frameworks)
3. [HTTP Clients](#http-clients)
4. [Data Science and Scientific Computing](#data-science-and-scientific-computing)
5. [Data Validation and Serialization](#data-validation-and-serialization)
6. [Database Libraries](#database-libraries)
7. [CLI Tools](#cli-tools)
8. [Testing and Quality](#testing-and-quality)
9. [Async Libraries](#async-libraries)
10. [Utility Libraries](#utility-libraries)
11. [Date and Time](#date-and-time)
12. [Documentation Tools](#documentation-tools)

---

## Standard Library Essentials

The Python standard library provides powerful, built-in tools. Always prefer these over third-party alternatives when available.

### pathlib: Object-Oriented Path Operations

**Prefer over:** `os.path`

**Official Documentation:** <https://docs.python.org/3/library/pathlib.html>

**Why use it:** Cross-platform, object-oriented, composable path operations.

**Examples:**

```python
from pathlib import Path

# Basic usage
p = Path('.')
python_files = list(p.glob('**/*.py'))  # Recursive glob

# Path composition with / operator
config_path = Path.home() / '.config' / 'app' / 'settings.json'

# Reading/writing files
data = config_path.read_text()
config_path.write_text('new content')

# Path properties
print(p.name)       # Filename
print(p.stem)       # Filename without extension
print(p.suffix)     # File extension
print(p.parent)     # Parent directory
```

**Key Methods:**

- `Path.iterdir()` - List directory contents
- `Path.glob(pattern)` - Pattern matching
- `Path.exists()`, `is_file()`, `is_dir()` - Check file type
- `Path.read_text()`, `write_text()` - Quick file I/O
- `Path.resolve()` - Get absolute path, resolve symlinks

### itertools: Iterator Tools

**Official Documentation:** <https://docs.python.org/3/library/itertools.html>

**Why use it:** Memory-efficient iteration patterns.

**Common Functions:**

```python
from itertools import (
    count, cycle, repeat,           # Infinite iterators
    chain, compress, islice,        # Finite iterators
    combinations, permutations,     # Combinatorics
    groupby, accumulate            # Aggregation
)

# Infinite iterators
for i in count(10, 2):  # 10, 12, 14, 16...
    if i > 20: break

# Chain iterables
list(chain('ABC', 'DEF'))  # ['A', 'B', 'C', 'D', 'E', 'F']

# Batching (3.12+)
from itertools import batched
list(batched('ABCDEFG', 2))  # [('A', 'B'), ('C', 'D'), ('E', 'F'), ('G',)]

# Pairwise sliding window (3.10+)
from itertools import pairwise
list(pairwise('ABCD'))  # [('A', 'B'), ('B', 'C'), ('C', 'D')]

# Groupby for aggregation
from itertools import groupby
data = [('a', 1), ('a', 2), ('b', 3), ('b', 4)]
for key, group in groupby(data, key=lambda x: x[0]):
    print(key, list(group))
```

### collections: Specialized Containers

**Official Documentation:** <https://docs.python.org/3/library/collections.html>

**Key Types:**

```python
from collections import Counter, defaultdict, deque, namedtuple

# Counter: Counting and tallying
word_counts = Counter(['apple', 'banana', 'apple', 'orange', 'apple'])
print(word_counts.most_common(2))  # [('apple', 3), ('banana', 1)]

# defaultdict: Avoid KeyError with default values
word_index = defaultdict(list)
for i, word in enumerate(['a', 'b', 'a', 'c']):
    word_index[word].append(i)  # No KeyError

# deque: Fast append/pop from both ends (O(1))
queue = deque(['a', 'b', 'c'])
queue.append('d')        # Add to right
queue.appendleft('z')    # Add to left
queue.pop()              # Remove from right
queue.popleft()          # Remove from left

# namedtuple: Lightweight immutable objects
Point = namedtuple('Point', ['x', 'y'])
p = Point(11, 22)
print(p.x, p.y)
```

### dataclasses: Simple Class Definitions

**Official Documentation:** <https://docs.python.org/3/library/dataclasses.html>

**Why use it:** Automatic generation of `__init__`, `__repr__`, `__eq__` and other methods.

**Examples:**

```python
from dataclasses import dataclass, field

@dataclass
class InventoryItem:
    """Class for tracking inventory."""
    name: str
    unit_price: float
    quantity_on_hand: int = 0

    def total_cost(self) -> float:
        return self.unit_price * self.quantity_on_hand

# With mutable defaults using field()
@dataclass
class ShoppingCart:
    items: list[str] = field(default_factory=list)

# Frozen (immutable) dataclasses
@dataclass(frozen=True)
class ImmutablePoint:
    x: int
    y: int
```

### typing: Type Hints Support

**Official Documentation:** <https://docs.python.org/3/library/typing.html>

**Common Type Hints:**

```python
from typing import List, Dict, Optional, Union, Callable, TypeVar, Generic

def process_items(items: list[str]) -> dict[str, int]:
    return {item: len(item) for item in items}

# Optional (None allowed)
def find_user(user_id: int) -> Optional[User]:
    ...

# Union (multiple types)
def parse_value(value: Union[int, str]) -> int:
    return int(value)

# Callable type hints
def apply_func(func: Callable[[int, int], int], a: int, b: int) -> int:
    return func(a, b)

# Generic types
T = TypeVar('T')

class Stack(Generic[T]):
    def push(self, item: T) -> None: ...
    def pop(self) -> T: ...
```

### Other Essential Standard Library Modules

**json, csv:** Data serialization

```python
import json
import csv

# JSON
data = {'key': 'value'}
json_str = json.dumps(data)
loaded = json.loads(json_str)

# CSV
with open('data.csv', 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=['name', 'age'])
    writer.writeheader()
    writer.writerow({'name': 'Alice', 'age': 30})
```

**datetime:** Date and time handling

```python
from datetime import datetime, timedelta

now = datetime.now()
tomorrow = now + timedelta(days=1)
formatted = now.strftime('%Y-%m-%d %H:%M:%S')
```

**re:** Regular expressions

```python
import re

pattern = r'\d{3}-\d{2}-\d{4}'  # SSN pattern
if re.match(pattern, '123-45-6789'):
    print('Valid SSN format')
```

**logging:** Logging framework

```python
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

logger.info('Application started')
logger.warning('Low disk space')
logger.error('Connection failed', exc_info=True)
```

**argparse:** CLI argument parsing

```python
import argparse

parser = argparse.ArgumentParser(description='Process files')
parser.add_argument('files', nargs='+', help='Files to process')
parser.add_argument('--verbose', action='store_true')
args = parser.parse_args()
```

**subprocess:** Running external commands

```python
import subprocess

result = subprocess.run(
    ['git', 'status'],
    capture_output=True,
    text=True,
    check=True
)
print(result.stdout)
```

**functools:** Higher-order functions

```python
from functools import lru_cache, partial, reduce

@lru_cache(maxsize=128)
def fibonacci(n):
    if n < 2: return n
    return fibonacci(n-1) + fibonacci(n-2)

# Partial application
from operator import mul
double = partial(mul, 2)
print(double(5))  # 10

# Reduce
from operator import add
total = reduce(add, [1, 2, 3, 4])  # 10
```

**contextlib:** Context manager tools

```python
from contextlib import contextmanager, suppress

@contextmanager
def managed_resource():
    resource = acquire_resource()
    try:
        yield resource
    finally:
        release_resource(resource)

# Suppress exceptions
with suppress(FileNotFoundError):
    os.remove('file.txt')
```

---

## Web Frameworks

### Web Frameworks Comparison

| Framework | Type | Async | Best For | Installation |
| --------- | ---- | ----- | -------- | ------------ |
| **FastAPI** | API | Yes | Modern APIs, OpenAPI docs, type safety | `pip install fastapi uvicorn` |
| **Django** | Full-stack | Partial | Large apps, admin, ORM, auth | `pip install django` |
| **Flask** | Micro | No | Prototyping, microservices, flexibility | `pip install flask` |

### FastAPI: Modern, Async, Type-Safe

**Official Documentation:** <https://fastapi.tiangolo.com/>

**When to use:**

- Modern API services
- Async/await patterns
- Automatic OpenAPI documentation
- Type safety is critical
- High performance requirements

**Example:**

```python
from fastapi import FastAPI
from pydantic import BaseModel

app = FastAPI()

class Item(BaseModel):
    name: str
    price: float
    is_offer: bool = False

@app.get("/")
async def root():
    return {"message": "Hello World"}

@app.post("/items/")
async def create_item(item: Item):
    return item
```

**Key Features:**

- Automatic request validation
- OpenAPI/Swagger UI generation
- Dependency injection
- WebSocket support
- Background tasks

### Django: Batteries-Included Full-Stack

**Official Documentation:** <https://docs.djangoproject.com/>

**When to use:**

- Full-featured web applications
- Need admin interface
- ORM required
- User authentication/authorization
- Large, robust applications

**Key Features:**

- Django ORM
- Admin interface
- Authentication system
- Form handling
- Template engine

### Flask: Minimal and Flexible

**Official Documentation:** <https://flask.palletsprojects.com/>

**When to use:**

- Quick prototyping
- Microservices
- Need full control over components
- Learning web development

**Example:**

```python
from flask import Flask, jsonify, request

app = Flask(__name__)

@app.route('/')
def home():
    return jsonify(message="Hello World")

@app.route('/items', methods=['POST'])
def create_item():
    data = request.get_json()
    return jsonify(data), 201
```

---

## HTTP Clients

### HTTP Clients Comparison

| Library | Sync/Async | HTTP/2 | Best For | Installation |
| ------- | ---------- | ------ | -------- | ------------ |
| **requests** | Sync | No | Classic scripts, simple use | `pip install requests` |
| **httpx** | Both | Yes | Modern apps, async, HTTP/2 | `pip install httpx` |
| **aiohttp** | Async | No | High concurrency, websockets | `pip install aiohttp` |

### requests: Simple and Stable

**Official Documentation:** <https://requests.readthedocs.io/>

**When to use:** Synchronous scripts, most classic use cases

**Example:**

```python
import requests

response = requests.get('https://api.example.com/data')
response.raise_for_status()  # Raise exception for 4xx/5xx
data = response.json()

# POST with data
response = requests.post(
    'https://api.example.com/items',
    json={'name': 'item', 'price': 10}
)
```

### httpx: Modern HTTP Client

**Official Documentation:** <https://www.python-httpx.org/>

**When to use:** Async APIs, HTTP/2, modern applications, testability

**Example:**

```python
import httpx

# Sync usage (drop-in replacement for requests)
response = httpx.get('https://api.example.com/data')
data = response.json()

# Async usage
async with httpx.AsyncClient() as client:
    response = await client.get('https://api.example.com/data')
    data = response.json()
```

### aiohttp: Async Client and Server

**Official Documentation:** <https://docs.aiohttp.org/>

**When to use:** High-concurrency async apps, websockets, need both client and server

**Example:**

```python
import aiohttp
import asyncio

async def fetch_data():
    async with aiohttp.ClientSession() as session:
        async with session.get('https://api.example.com/data') as resp:
            return await resp.json()

asyncio.run(fetch_data())
```

---

## Data Science and Scientific Computing

### NumPy: Numerical Computing

**Installation:** `pip install numpy`
**Official Documentation:** <https://numpy.org/doc/>

**Use for:** Array computations, mathematical functions, linear algebra

**Example:**

```python
import numpy as np

# Array creation
arr = np.array([1, 2, 3, 4, 5])
matrix = np.array([[1, 2], [3, 4]])

# Mathematical operations (vectorized)
arr * 2          # Element-wise multiplication
np.sqrt(arr)     # Element-wise square root
arr.mean()       # Aggregate functions

# Linear algebra
np.dot(matrix, matrix.T)  # Matrix multiplication
```

### pandas: Data Analysis

**Installation:** `pip install pandas`
**Official Documentation:** <https://pandas.pydata.org/docs/>

**Use for:** Dataframes, tabular data analysis, data manipulation

**Example:**

```python
import pandas as pd

# Create DataFrame
df = pd.DataFrame({
    'name': ['Alice', 'Bob', 'Charlie'],
    'age': [25, 30, 35],
    'city': ['NYC', 'LA', 'Chicago']
})

# Data manipulation
df[df['age'] > 25]           # Filtering
df.groupby('city').mean()    # Grouping
df.sort_values('age')        # Sorting

# I/O
df.to_csv('data.csv')
df = pd.read_csv('data.csv')
```

### Matplotlib: Data Visualization

**Installation:** `pip install matplotlib`
**Official Documentation:** <https://matplotlib.org/stable/>

**Use for:** Line plots, scatter plots, bar charts, custom visualizations

**Example:**

```python
import matplotlib.pyplot as plt

# Simple plot
plt.plot([1, 2, 3, 4], [1, 4, 9, 16])
plt.xlabel('x')
plt.ylabel('y')
plt.title('Sample Plot')
plt.show()
```

### scikit-learn: Machine Learning

**Installation:** `pip install scikit-learn`
**Official Documentation:** <https://scikit-learn.org/stable/>

**Use for:** Classification, regression, clustering, preprocessing, model selection

**Example:**

```python
from sklearn.model_selection import train_test_split
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import accuracy_score

# Train/test split
X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2)

# Train model
clf = RandomForestClassifier()
clf.fit(X_train, y_train)

# Predict and evaluate
y_pred = clf.predict(X_test)
accuracy = accuracy_score(y_test, y_pred)
```

---

## Data Validation and Serialization

### Data Validation Libraries Comparison

| Library | Type Hints | Performance | Async | Best For | Installation |
| ------- | ---------- | ----------- | ----- | -------- | ------------ |
| **Pydantic** | Yes | Fast | Yes | FastAPI, modern APIs, type safety | `pip install pydantic` |
| **marshmallow** | No | Moderate | No | Django/Flask, legacy, custom schemas | `pip install marshmallow` |

### Pydantic: Type-Safe Data Validation

**Official Documentation:** <https://docs.pydantic.dev/>

**When to use:** FastAPI, new projects, type annotations, JSON serialization

**Example:**

```python
from pydantic import BaseModel, Field, EmailStr, validator

class User(BaseModel):
    name: str = Field(..., min_length=1, max_length=50)
    email: EmailStr
    age: int = Field(gt=0, lt=120)
    is_active: bool = True

    @validator('name')
    def name_must_be_alphanumeric(cls, v):
        assert v.isalnum(), 'must be alphanumeric'
        return v

# Validation
user = User(name='Alice', email='alice@example.com', age=28)

# Serialization
user.model_dump()  # To dict
user.model_dump_json()  # To JSON string
user.model_dump(by_alias=True)  # Use field aliases
```

**Advanced Features:**

```python
from pydantic import Field

class Item(BaseModel):
    name: str = Field(..., alias='item_name')  # Field aliasing
    price: float = Field(..., gt=0, description="Price in USD")

    class Config:
        populate_by_name = True  # Accept both name and alias
```

### marshmallow: Object Serialization

**Official Documentation:** <https://marshmallow.readthedocs.io/>

**When to use:** Django/Flask projects, need custom serialization logic

---

## Database Libraries

### PostgreSQL

**psycopg3 (Modern):**

- Installation: `pip install psycopg[binary]`
- Official Documentation: <https://www.psycopg.org/psycopg3/docs/>
- Supports both sync and async
- Recommended for new projects

**asyncpg (Fast Async):**

- Installation: `pip install asyncpg`
- Official Documentation: <https://magicstack.github.io/asyncpg/current/>
- Best async performance for PostgreSQL

**Example (asyncpg):**

```python
import asyncpg

async def fetch_users():
    conn = await asyncpg.connect('postgresql://user:pass@localhost/db')
    users = await conn.fetch('SELECT * FROM users WHERE age > $1', 18)
    await conn.close()
    return users
```

### SQLAlchemy: ORM and SQL Toolkit

**Installation:** `pip install sqlalchemy`
**Official Documentation:** <https://docs.sqlalchemy.org/>

**Use for:** ORM, multi-database support, complex queries

**Example:**

```python
from sqlalchemy import create_engine, Column, Integer, String
from sqlalchemy.orm import declarative_base, Session

Base = declarative_base()

class User(Base):
    __tablename__ = 'users'
    id = Column(Integer, primary_key=True)
    name = Column(String)
    email = Column(String)

engine = create_engine('sqlite:///example.db')
Base.metadata.create_all(engine)

# CRUD operations
with Session(engine) as session:
    user = User(name='Alice', email='alice@example.com')
    session.add(user)
    session.commit()
```

---

## CLI Tools

### CLI Tools Comparison

| Library | Type Hints | Modern | Best For | Installation |
| ------- | ---------- | ------ | -------- | ------------ |
| **Typer** | Yes | Yes | Modern CLIs, type safety | `pip install typer` |
| **Click** | No | Yes | Mature ecosystem, flexibility | `pip install click` |
| **argparse** | No | No | Simple needs, no dependencies | Built-in |

### Typer: Modern Type-Safe CLI

**Official Documentation:** <https://typer.tiangolo.com/>

**When to use:** New CLI apps, type hints, auto-generated help

**Example:**

```python
import typer

app = typer.Typer()

@app.command()
def hello(name: str, count: int = 1):
    """Say hello COUNT times."""
    for _ in range(count):
        typer.echo(f"Hello {name}")

if __name__ == "__main__":
    app()
```

### Click: Flexible CLI Framework

**Official Documentation:** <https://click.palletsprojects.com/>

**When to use:** Existing projects, mature ecosystem

### rich: Terminal Formatting

**Installation:** `pip install rich`
**Official Documentation:** <https://rich.readthedocs.io/>

**Use for:** Beautiful terminal output, progress bars, tables

**Example:**

```python
from rich.console import Console
from rich.table import Table

console = Console()
console.print("[bold green]Success![/bold green]")

table = Table(title="Users")
table.add_column("Name")
table.add_column("Age")
table.add_row("Alice", "25")
console.print(table)
```

---

## Testing and Quality

### pytest: Testing Framework

**Installation:** `pip install pytest`
**Official Documentation:** <https://docs.pytest.org/>

**Core Plugins:**

- `pytest-cov`: Coverage reports (`pip install pytest-cov`)
- `pytest-asyncio`: Async tests (`pip install pytest-asyncio`)
- `pytest-mock`: Mocking (`pip install pytest-mock`)
- `pytest-xdist`: Parallel execution (`pip install pytest-xdist`)

**Example:**

```python
import pytest

# Basic test
def test_addition():
    assert 1 + 1 == 2

# Fixtures
@pytest.fixture
def sample_data():
    return {'key': 'value'}

def test_with_fixture(sample_data):
    assert sample_data['key'] == 'value'

# Parametrize
@pytest.mark.parametrize("input,expected", [
    (1, 2),
    (2, 4),
    (3, 6),
])
def test_double(input, expected):
    assert input * 2 == expected

# Async tests
@pytest.mark.asyncio
async def test_async_function():
    result = await async_function()
    assert result is True

# Mocking
def test_with_mock(mocker):
    mock = mocker.patch('module.function', return_value=42)
    result = module.function()
    assert result == 42
    mock.assert_called_once()
```

**Running Tests:**

```bash
pytest                           # Run all tests
pytest --cov=mypackage          # With coverage
pytest -v                       # Verbose
pytest -k test_addition         # Run specific test
pytest -x                       # Stop on first failure
pytest --pdb                    # Drop into debugger on failure
```

### Ruff: Linting and Formatting

**Installation:** `pip install ruff`
**Official Documentation:** <https://docs.astral.sh/ruff/>

**Use for:** Fast linting, formatting (replacement for flake8, black, isort)

```bash
ruff check .                # Lint
ruff format .               # Format
```

### mypy: Static Type Checking

**Installation:** `pip install mypy`
**Official Documentation:** <https://mypy.readthedocs.io/>

```bash
mypy mypackage/
```

### Bandit: Security Linting

**Installation:** `pip install bandit`
**Official Documentation:** <https://bandit.readthedocs.io/>

```bash
bandit -r mypackage/
```

---

## Async Libraries

### asyncio: Core Async Framework

**Official Documentation:** <https://docs.python.org/3/library/asyncio.html>

**Example:**

```python
import asyncio

async def fetch_data():
    await asyncio.sleep(1)
    return "data"

async def main():
    result = await fetch_data()
    print(result)

asyncio.run(main())
```

### aiohttp: Async HTTP (see HTTP Clients section)

### aiofiles: Async File I/O

**Installation:** `pip install aiofiles`

```python
import aiofiles

async def read_file():
    async with aiofiles.open('file.txt', 'r') as f:
        contents = await f.read()
    return contents
```

---

## Utility Libraries

### python-dotenv: Environment Variables

**Installation:** `pip install python-dotenv`
**Official Documentation:** <https://saurabh-kumar.com/python-dotenv/>

```python
from dotenv import load_dotenv
import os

load_dotenv()  # Load .env file
api_key = os.getenv('API_KEY')
```

### pyyaml: YAML Parsing

**Installation:** `pip install pyyaml`
**Official Documentation:** <https://pyyaml.org/>

```python
import yaml

with open('config.yaml', 'r') as f:
    config = yaml.safe_load(f)
```

### Beautiful Soup: Web Scraping

**Installation:** `pip install beautifulsoup4`
**Official Documentation:** <https://www.crummy.com/software/BeautifulSoup/>

```python
from bs4 import BeautifulSoup
import requests

html = requests.get('https://example.com').text
soup = BeautifulSoup(html, 'html.parser')
titles = soup.find_all('h1')
```

---

## Date and Time

### Date and Time Libraries Comparison

| Library | Timezones | NLP-Style | Best For | Installation |
| ------- | ---------- | --------- | -------- | ------------ |
| **datetime** | No | No | Built-in, basic needs | Built-in |
| **dateutil** | Yes | No | Parsing, timezones, relativedelta | `pip install python-dateutil` |
| **arrow** | Yes | Yes | User-friendly, human dates | `pip install arrow` |
| **pendulum** | Yes | No | Timezone-aware, datetime replacement | `pip install pendulum` |

**Official Documentation:**

- datetime: <https://docs.python.org/3/library/datetime.html>
- dateutil: <https://dateutil.readthedocs.io/>
- arrow: <https://arrow.readthedocs.io/>
- pendulum: <https://pendulum.eustace.io/docs/>

---

## Documentation Tools

### Documentation Tools Comparison

| Tool | Format | Best For | Installation |
| ---- | ------ | -------- | ------------ |
| **Sphinx** | reStructuredText/Markdown | API docs, Python projects | `pip install sphinx` |
| **MkDocs** | Markdown | Simple docs, GitHub Pages | `pip install mkdocs` |
| **pdoc** | Markdown/HTML | Auto-generate from docstrings | `pip install pdoc` |

**Official Documentation:**

- Sphinx: <https://www.sphinx-doc.org/>
- MkDocs: <https://www.mkdocs.org/>
- pdoc: <https://pdoc.dev/>

---

## Quick Reference Table

### Standard Library vs Third-Party

| Task | Standard Library | Third-Party Alternative |
| ---- | ---------------- | ----------------------- |
| Path operations | `pathlib` | - |
| HTTP requests | `urllib` | `requests`, `httpx` |
| Async I/O | `asyncio` | - |
| Date/time | `datetime` | `arrow`, `pendulum` |
| JSON | `json` | `orjson` (faster) |
| Type hints | `typing` | - |
| CLI parsing | `argparse` | `click`, `typer` |
| Testing | `unittest` | `pytest` |

### Installation Quick Commands

```bash
# Web Development
pip install fastapi uvicorn pydantic
pip install django
pip install flask

# Data Science
pip install numpy pandas matplotlib scikit-learn

# HTTP Clients
pip install requests httpx aiohttp

# Testing
pip install pytest pytest-cov pytest-mock pytest-asyncio

# CLI Tools
pip install typer click rich

# Utilities
pip install python-dotenv pyyaml
```

---

## Best Practices Summary

1. **Prefer standard library** when available (pathlib over os.path, dataclasses over custom classes)
2. **Use type hints** with `typing` and validate with `mypy`
3. **Choose async libraries** for I/O-bound concurrent operations
4. **FastAPI + Pydantic** for modern APIs
5. **pytest** for all testing needs
6. **Ruff** for fast linting and formatting
7. **pathlib** for all path operations
8. **dataclasses** for simple data containers
9. **Type hints everywhere** for better IDE support and fewer bugs

---

## Version Compatibility Notes

- Python 3.10+: Use new union syntax (`int | str` instead of `Union[int, str]`)
- Python 3.11+: Significant performance improvements, use for new projects
- Python 3.12+: More performance improvements, `batched()` in itertools
- Always specify minimum Python version in your project

---

**Sources:**

- Python Standard Library Documentation: <https://docs.python.org/3/library/>
- Perplexity Research: Python essential libraries 2024
- Official library documentation (linked throughout)
