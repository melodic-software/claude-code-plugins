# Type Hints

Comprehensive guide to Python type hints based on official documentation and PEPs.

## Table of Contents

- [Official Sources](#official-sources)
- [Modern Type Hint Syntax (Python 3.10+)](#modern-type-hint-syntax-python-310)
- [Basic Types](#basic-types)
- [Collections](#collections)
- [Union and Optional](#union-and-optional)
- [Callable Types](#callable-types)
- [Generic Types and TypeVar](#generic-types-and-typevar)
- [Protocols (Structural Typing)](#protocols-structural-typing)
- [TypedDict](#typeddict)
- [dataclasses with Type Hints](#dataclasses-with-type-hints)
- [mypy Configuration](#mypy-configuration)
- [Type Stubs and .pyi Files](#type-stubs-and-pyi-files)
- [Best Practices](#best-practices)
- [Summary](#summary)
- [Additional Resources](#additional-resources)

## Official Sources

This guide is backed by the following official sources:

- **Python typing module documentation**: <https://docs.python.org/3/library/typing.html>
- **PEP 484** (Type Hints): <https://peps.python.org/pep-0484/>
- **PEP 604** (Union Types with |): <https://peps.python.org/pep-0604/>
- **PEP 544** (Protocols/Structural Subtyping): <https://peps.python.org/pep-0544/>
- **PEP 589** (TypedDict): <https://peps.python.org/pep-0589/>
- **PEP 655** (Required/NotRequired for TypedDict): <https://peps.python.org/pep-0655/>
- **Mypy documentation**: <https://mypy.readthedocs.io/>
- **Python dataclasses documentation**: <https://docs.python.org/3/library/dataclasses.html>
- **typing.python.org**: <https://typing.python.org/>

## Modern Type Hint Syntax (Python 3.10+)

Python 3.10+ introduces cleaner, more readable type hint syntax through PEP 604 and built-in generic support.

### Built-in Generics (Python 3.9+)

Starting with Python 3.9, you can use built-in collection types directly for type hints without importing from `typing`:

```python
# Modern syntax (Python 3.9+)
def process_items(items: list[str]) -> dict[str, int]:
    return {item: len(item) for item in items}

def get_coordinates() -> tuple[float, float]:
    return (1.0, 2.0)

def unique_values(items: list[int]) -> set[int]:
    return set(items)
```

No need for `typing.List`, `typing.Dict`, etc. anymore.

### Union Types with | (Python 3.10+)

PEP 604 introduces the `|` operator for union types:

```python
# Modern syntax (Python 3.10+)
def process_value(value: int | str) -> int | None:
    if isinstance(value, int):
        return value
    elif isinstance(value, str):
        return int(value)
    return None

# Old syntax (still valid, but verbose)
from typing import Union, Optional

def process_value_old(value: Union[int, str]) -> Optional[int]:
    # Same implementation
    pass
```

**Best Practice**: Use `|` syntax in Python 3.10+ for cleaner, more readable code.

### Type Aliases

Type aliases create shorthand names for complex types:

```python
# Simple type alias
Vector = list[float]

def scale(scalar: float, vector: Vector) -> Vector:
    return [scalar * num for num in vector]

# Explicit type alias (Python 3.10+)
from typing import TypeAlias

UserId: TypeAlias = int
UserMap: TypeAlias = dict[UserId, str]

# Complex type alias
JSONValue: TypeAlias = dict[str, "JSONValue"] | list["JSONValue"] | str | int | float | bool | None
```

Type aliases are treated as completely interchangeable with the original type.

### NewType for Distinct Types

`NewType` creates a distinct type that's checked by static type checkers but remains the underlying type at runtime:

```python
from typing import NewType

UserId = NewType('UserId', int)
AdminId = NewType('AdminId', int)

def get_user_name(user_id: UserId) -> str:
    return f"User {user_id}"

# Type checker enforces distinction
user_id = UserId(42)
admin_id = AdminId(99)

get_user_name(user_id)    # OK
get_user_name(admin_id)   # Error: AdminId is not UserId
get_user_name(42)         # Error: int is not UserId
```

**Use Case**: When you need type safety for semantically different values that share the same underlying type.

## Basic Types

### Primitive Types

```python
def calculate(x: int, y: float, name: str, active: bool) -> float:
    return x * y if active else 0.0

# bytes type
def process_binary(data: bytes) -> int:
    return len(data)
```

### None and Optional

```python
# Modern syntax (Python 3.10+)
def find_user(user_id: int) -> str | None:
    # Returns string or None
    pass

# Equivalent to Optional[str] in older syntax
from typing import Optional

def find_user_old(user_id: int) -> Optional[str]:
    pass
```

**Note**: `str | None` and `Optional[str]` are equivalent. The modern `|` syntax is preferred.

### Any Type

`Any` is a special type that disables type checking for that value:

```python
from typing import Any

def process_dynamic(value: Any) -> Any:
    # No type checking performed
    return value.anything()  # No error

# Use sparingly - defeats the purpose of type hints
```

**Best Practice**: Use `Any` only when:

- Interfacing with dynamic libraries
- Gradually adopting type hints in legacy code
- Type is genuinely unknown and varies widely

Consider `object` for values where you just need "any type":

```python
def log_value(value: object) -> None:
    print(f"Value: {value}")  # OK - object supports str()
```

### Literal Types

`Literal` restricts values to specific constants:

```python
from typing import Literal

def draw_line(style: Literal['solid', 'dashed', 'dotted']) -> None:
    print(f"Drawing {style} line")

draw_line('solid')   # OK
draw_line('wavy')    # Error: not a permitted literal

# Multiple literals
Mode = Literal['r', 'w', 'a', 'rb', 'wb', 'ab']

def open_file(filename: str, mode: Mode) -> None:
    pass

# Literal with multiple types
def process(value: Literal[1, 2, 3, 'auto']) -> None:
    pass
```

## Collections

### Basic Collections

```python
from collections.abc import Sequence, Mapping, Iterable

# list, dict, set, tuple - use built-in types directly (Python 3.9+)
def process_names(names: list[str]) -> set[str]:
    return set(names)

def count_items(items: dict[str, int]) -> int:
    return sum(items.values())

# tuple with specific types
def get_point() -> tuple[int, int]:
    return (10, 20)

# tuple with variable length (homogeneous)
def get_values() -> tuple[int, ...]:
    return (1, 2, 3, 4, 5)

# frozenset
def immutable_set() -> frozenset[str]:
    return frozenset(['a', 'b', 'c'])
```

### Abstract Collections (from collections.abc)

Use abstract types when you don't need specific collection implementations:

```python
from collections.abc import Sequence, Mapping, Iterable, Iterator

def process_sequence(items: Sequence[int]) -> int:
    # Accepts list, tuple, range, etc.
    return sum(items)

def process_mapping(data: Mapping[str, int]) -> list[str]:
    # Accepts dict, OrderedDict, etc.
    return list(data.keys())

def process_items(items: Iterable[str]) -> None:
    # Accepts list, set, dict, generator, etc.
    for item in items:
        print(item)

def count_generator(n: int) -> Iterator[int]:
    i = 0
    while i < n:
        yield i
        i += 1
```

**Best Practice**: Use abstract types in function parameters for maximum flexibility, concrete types for return values for clarity.

## Union and Optional

### Union Types

```python
# Modern syntax (Python 3.10+)
def process(value: int | str | float) -> str:
    return str(value)

# Multiple unions
def handle_input(data: list[int] | dict[str, int] | None) -> int:
    if data is None:
        return 0
    elif isinstance(data, list):
        return sum(data)
    else:  # dict
        return sum(data.values())
```

### Type Narrowing

Type checkers understand `isinstance()` checks:

```python
def process_value(value: int | str) -> int:
    if isinstance(value, str):
        # Type checker knows value is str here
        return len(value)
    else:
        # Type checker knows value is int here
        return value
```

## Callable Types

### Function Signatures

```python
from collections.abc import Callable

# Callable[[arg1_type, arg2_type, ...], return_type]
def apply_twice(value: int, func: Callable[[int], int]) -> int:
    return func(func(value))

def add_one(x: int) -> int:
    return x + 1

result = apply_twice(5, add_one)  # Returns 7

# No arguments
def run_callback(callback: Callable[[], None]) -> None:
    callback()

# Multiple arguments
def transform(
    value: int,
    operation: Callable[[int, int], int]
) -> int:
    return operation(value, 10)
```

### Variable Arguments

```python
from collections.abc import Callable

# For unknown/variable arguments, use ...
def register_handler(handler: Callable[..., None]) -> None:
    # Accepts any callable that returns None
    pass
```

### Callback Protocols

For more precise callable specifications, use Protocol:

```python
from typing import Protocol

class Combiner(Protocol):
    def __call__(self, *vals: bytes, maxlen: int | None = None) -> list[bytes]:
        ...

def batch_process(data: list[bytes], combiner: Combiner) -> bytes:
    result = combiner(*data)
    return b''.join(result)
```

## Generic Types and TypeVar

### TypeVar Basics

`TypeVar` creates type variables for generic functions and classes:

```python
from typing import TypeVar

T = TypeVar('T')

def first_item(items: list[T]) -> T:
    return items[0]

# Type checker infers return type from input
x: int = first_item([1, 2, 3])        # T = int
y: str = first_item(['a', 'b', 'c'])  # T = str
```

### Bounded TypeVars

Restrict type variables to specific types:

```python
from typing import TypeVar

# T must be int or str
T = TypeVar('T', int, str)

def double(value: T) -> T:
    if isinstance(value, int):
        return value * 2  # type: ignore
    return value + value  # type: ignore

# T must be a subtype of these bounds
from numbers import Number

NumT = TypeVar('NumT', bound=Number)

def add_ten(value: NumT) -> NumT:
    return value + 10  # type: ignore
```

### Generic Classes

```python
from typing import TypeVar, Generic

T = TypeVar('T')

class Box(Generic[T]):
    def __init__(self, content: T) -> None:
        self.content = content

    def get(self) -> T:
        return self.content

# Type checker infers type parameter
int_box: Box[int] = Box(123)
str_box: Box[str] = Box("hello")

x: int = int_box.get()    # OK
y: int = str_box.get()    # Error: str is not int
```

### Multiple Type Parameters

```python
from typing import TypeVar, Generic

K = TypeVar('K')
V = TypeVar('V')

class Pair(Generic[K, V]):
    def __init__(self, key: K, value: V) -> None:
        self.key = key
        self.value = value

    def get_key(self) -> K:
        return self.key

    def get_value(self) -> V:
        return self.value

pair: Pair[str, int] = Pair("age", 30)
```

### Variance

TypeVars can be covariant, contravariant, or invariant (default):

```python
from typing import TypeVar, Generic

# Covariant: ReadOnlyBox[Derived] can be used where ReadOnlyBox[Base] is expected
T_co = TypeVar('T_co', covariant=True)

class ReadOnlyBox(Generic[T_co]):
    def __init__(self, content: T_co) -> None:
        self._content = content

    def get(self) -> T_co:
        return self._content

# Contravariant: Processor[Base] can be used where Processor[Derived] is expected
T_contra = TypeVar('T_contra', contravariant=True)

class Processor(Generic[T_contra]):
    def process(self, item: T_contra) -> None:
        pass

# Invariant (default): exact type match required
T = TypeVar('T')

class MutableBox(Generic[T]):
    def __init__(self, content: T) -> None:
        self.content = content

    def get(self) -> T:
        return self.content

    def set(self, content: T) -> None:
        self.content = content
```

## Protocols (Structural Typing)

Protocols define interfaces based on structure, not inheritance (PEP 544):

```python
from typing import Protocol

class SupportsClose(Protocol):
    def close(self) -> None:
        ...

class Resource:
    # No inheritance from SupportsClose needed!
    def close(self) -> None:
        print("Closing resource")

def close_all(items: list[SupportsClose]) -> None:
    for item in items:
        item.close()

# Works because Resource has a close() method
close_all([Resource(), open('file.txt')])  # OK
```

### Runtime Checkable Protocols

Use `@runtime_checkable` to enable `isinstance()` checks:

```python
from typing import Protocol, runtime_checkable

@runtime_checkable
class Portable(Protocol):
    handles: int

class Mug:
    def __init__(self) -> None:
        self.handles = 1

mug = Mug()
if isinstance(mug, Portable):  # Works at runtime!
    print(f"Has {mug.handles} handles")
```

### Generic Protocols

```python
from typing import Protocol, TypeVar

T = TypeVar('T')

class SupportsAbs(Protocol[T]):
    def __abs__(self) -> T:
        ...

def absolute_value(x: SupportsAbs[float]) -> float:
    return abs(x)
```

### Built-in Protocols

Python provides several useful protocols:

```python
from typing import SupportsInt, SupportsFloat, SupportsAbs

def to_integer(value: SupportsInt) -> int:
    return int(value)

def to_float(value: SupportsFloat) -> float:
    return float(value)

def get_magnitude(value: SupportsAbs[float]) -> float:
    return abs(value)
```

## TypedDict

`TypedDict` provides typed dictionaries with fixed keys (PEP 589):

### Basic TypedDict

```python
from typing import TypedDict

class Movie(TypedDict):
    name: str
    year: int

# Type checker validates structure
movie: Movie = {'name': 'The Matrix', 'year': 1999}  # OK
bad: Movie = {'name': 'Inception'}  # Error: missing 'year'
```

### Optional Keys (total=False)

```python
from typing import TypedDict

class MovieOptional(TypedDict, total=False):
    # All keys are optional
    name: str
    year: int
    rating: float

movie: MovieOptional = {}  # OK
movie2: MovieOptional = {'name': 'Inception'}  # OK
```

### Mixed Required/Optional Keys (Python 3.11+)

PEP 655 introduces `Required` and `NotRequired`:

```python
from typing import TypedDict, Required, NotRequired

class User(TypedDict, total=False):
    id: Required[int]         # Always required
    name: str                 # Optional (total=False)
    email: NotRequired[str]   # Explicitly optional

# id is required, name and email are optional
user: User = {'id': 1}                           # OK
user2: User = {'id': 2, 'name': 'Alice'}         # OK
user3: User = {'name': 'Bob'}                    # Error: missing required 'id'
```

### Inheritance

```python
from typing import TypedDict

class MovieBase(TypedDict):
    name: str
    year: int

class MovieWithRating(MovieBase):
    rating: float

movie: MovieWithRating = {
    'name': 'Inception',
    'year': 2010,
    'rating': 8.8
}
```

### Introspection

```python
from typing import TypedDict, Required, NotRequired

class User(TypedDict, total=False):
    id: Required[int]
    name: str
    email: NotRequired[str]

# Check required and optional keys
print(User.__required_keys__)   # frozenset({'id'})
print(User.__optional_keys__)   # frozenset({'name', 'email'})
```

## dataclasses with Type Hints

### Basic dataclass

```python
from dataclasses import dataclass

@dataclass
class InventoryItem:
    name: str
    unit_price: float
    quantity_on_hand: int = 0

item = InventoryItem("Widget", 3.99, 10)
print(item.name)  # Widget
```

### Field Options

```python
from dataclasses import dataclass, field

@dataclass
class Position:
    name: str
    lon: float = field(default=0.0, metadata={'unit': 'degrees'})
    lat: float = field(default=0.0, metadata={'unit': 'degrees'})
```

### default_factory

Use `default_factory` for mutable defaults:

```python
from dataclasses import dataclass, field

@dataclass
class Inventory:
    # WRONG: items: list = []  # Dangerous! Shared between instances
    items: list[str] = field(default_factory=list)  # Correct

inventory1 = Inventory()
inventory2 = Inventory()
inventory1.items.append("A")
print(inventory2.items)  # [] - separate lists
```

### frozen (Immutable)

```python
from dataclasses import dataclass

@dataclass(frozen=True)
class Point:
    x: float
    y: float

p = Point(1.0, 2.0)
# p.x = 3.0  # Error: FrozenInstanceError
```

### slots (Memory Optimization)

Python 3.10+ supports `slots=True` for memory efficiency:

```python
from dataclasses import dataclass

@dataclass(slots=True)
class Position:
    x: int
    y: int

# Uses __slots__ internally, reducing memory usage
```

### Combined Example

```python
from dataclasses import dataclass, field

@dataclass(frozen=True, slots=True)
class Node:
    label: str
    value: int
    edges: list['Node'] = field(default_factory=list)

# Immutable, memory-efficient, type-safe
```

## mypy Configuration

### pyproject.toml Configuration

```toml
[tool.mypy]
# Python version for compatibility checking
python_version = "3.11"

# Enable strict mode (recommended for new projects)
strict = true

# Additional warnings
warn_unreachable = true
warn_redundant_casts = true
warn_unused_ignores = true
warn_unused_configs = true
warn_return_any = true

# Output formatting
pretty = true
show_column_numbers = true
show_error_codes = true
show_error_context = true

# Import discovery
namespace_packages = true
explicit_package_bases = true

# Caching
cache_dir = ".mypy_cache"
sqlite_cache = true

# Per-module overrides
[[tool.mypy.overrides]]
module = "tests.*"
disallow_untyped_defs = false

[[tool.mypy.overrides]]
module = [
    "pandas.*",
    "numpy.*",
    "scipy.*"
]
ignore_missing_imports = true
```

### Strict Mode Components

Enabling `strict = true` is equivalent to:

```toml
[tool.mypy]
warn_unused_configs = true
warn_redundant_casts = true
warn_unused_ignores = true
strict_equality = true
check_untyped_defs = true
disallow_subclassing_any = true
disallow_untyped_decorators = true
disallow_any_generics = true
disallow_untyped_calls = true
disallow_incomplete_defs = true
disallow_untyped_defs = true
no_implicit_reexport = true
warn_return_any = true
extra_checks = true
```

### Selective Strictness

Start strict, then disable specific checks as needed:

```toml
[tool.mypy]
strict = true
# Disable specific checks that are too strict for your use case
warn_return_any = false
disallow_untyped_decorators = false
```

### Command-Line Options

```bash
# Enable strict mode
mypy --strict myapp.py

# Disallow untyped function definitions
mypy --disallow-untyped-defs src/

# Ignore missing imports (for gradual adoption)
mypy --ignore-missing-imports external_lib_usage.py

# Specify Python version
mypy --python-version 3.10 legacy_code.py

# Show detailed error information
mypy --show-column-numbers --show-error-codes app.py

# Generate reports
mypy --html-report ./mypy-report src/
```

## Type Stubs and .pyi Files

### When to Use Stub Files

- Adding types to libraries without modifying source
- Third-party libraries without type hints
- Separating type information from implementation

### Creating Stub Files

```python
# mymodule.pyi (stub file)
from typing import overload

def process(value: int) -> str: ...
def process(value: str) -> int: ...

@overload
def compute(x: int, y: int) -> int: ...
@overload
def compute(x: float, y: float) -> float: ...
```

### Third-Party Type Stubs

Install type stubs from typeshed:

```bash
# Install stubs for requests library
pip install types-requests

# Install stubs for redis
pip install types-redis
```

Common stub packages:

- `types-requests`
- `types-redis`
- `types-PyYAML`
- `types-setuptools`

### Inline vs Stub Files

```python
# inline.py
def add(x: int, y: int) -> int:
    return x + y

# OR separate stub:
# inline.py (no type hints)
def add(x, y):
    return x + y

# inline.pyi (type hints)
def add(x: int, y: int) -> int: ...
```

## Best Practices

### 1. Start with Public APIs

Begin type hinting from public interfaces:

```python
# Good: Type public API first
class DataProcessor:
    def process(self, data: list[dict[str, int]]) -> list[int]:
        return self._internal_process(data)

    def _internal_process(self, data):
        # Can add types later
        return [sum(d.values()) for d in data]
```

### 2. Gradual Typing

Adopt type hints incrementally:

```python
# Phase 1: Type function signatures
def process_data(data):  # type: ignore
    # Implementation without internal types
    result = transform(data)
    return result

# Phase 2: Add internal types
def process_data(data: list[int]) -> dict[str, int]:
    result = transform(data)
    return result
```

### 3. When to Use Any

Use `Any` sparingly and document why:

```python
from typing import Any

# Acceptable: interfacing with dynamic library
def call_dynamic_api(endpoint: str, payload: Any) -> Any:
    # External API accepts/returns dynamic structures
    return api_client.call(endpoint, payload)

# Avoid: lazy typing
def process(value: Any) -> Any:  # Too permissive!
    return value + 1
```

### 4. Type Narrowing

Use type guards and narrowing:

```python
def process_value(value: int | str | None) -> int:
    if value is None:
        return 0
    elif isinstance(value, int):
        return value
    else:  # Type checker knows value is str
        return len(value)
```

### 5. Prefer Specific Types Over Any

```python
# Avoid
def process(data: Any) -> Any:
    return data.upper()

# Better: Use object if truly any type
def process(data: object) -> str:
    return str(data).upper()

# Best: Use specific types
def process(data: str) -> str:
    return data.upper()
```

### 6. Use Protocols for Duck Typing

```python
from typing import Protocol

class Drawable(Protocol):
    def draw(self) -> None: ...

def render(item: Drawable) -> None:
    item.draw()

# Any class with draw() method works
class Circle:
    def draw(self) -> None:
        print("Drawing circle")

render(Circle())  # OK - structural match
```

### 7. Avoid Overusing Generics

```python
# Overkill for simple cases
T = TypeVar('T')
def identity(x: T) -> T:
    return x

# Simpler (unless you need generic behavior)
def identity(x: object) -> object:
    return x
```

### 8. Document Complex Types

```python
from typing import TypeAlias

# Document with type aliases
UserId: TypeAlias = int
Timestamp: TypeAlias = float
EventData: TypeAlias = dict[str, str | int | float]

def process_event(
    user_id: UserId,
    timestamp: Timestamp,
    data: EventData
) -> None:
    pass
```

### 9. Use Literal for Constants

```python
from typing import Literal

LogLevel = Literal['DEBUG', 'INFO', 'WARNING', 'ERROR']

def log(message: str, level: LogLevel = 'INFO') -> None:
    print(f"[{level}] {message}")

log("Starting", "INFO")   # OK
log("Error", "CRITICAL")  # Error: not a valid literal
```

### 10. Runtime vs Static Checking

Type hints are for static analysis - they don't enforce types at runtime:

```python
def add(x: int, y: int) -> int:
    return x + y

# This runs without error (no runtime type checking)
result = add("hello", "world")  # Returns "helloworld"

# mypy will catch this error during static analysis
```

Use runtime validation when needed:

```python
def add(x: int, y: int) -> int:
    if not isinstance(x, int) or not isinstance(y, int):
        raise TypeError("Arguments must be integers")
    return x + y
```

## Summary

**Modern Python Type Hints (3.10+)**:

- Use built-in types: `list[T]`, `dict[K,V]`, `set[T]`, `tuple[T, ...]`
- Use `|` for unions: `int | str | None`
- Use `TypeAlias` for explicit aliases
- Use `Literal` for constant values
- Use `Protocol` for structural typing
- Use `TypedDict` for typed dictionaries
- Use `dataclass` for typed data structures

**Configuration**:

- Enable `strict = true` in mypy for comprehensive checking
- Use per-module overrides for gradual adoption
- Install type stubs (`types-*` packages) for third-party libraries

**Best Practices**:

- Start with public APIs, add internal types gradually
- Use specific types over `Any` when possible
- Leverage type narrowing with `isinstance()` checks
- Document complex types with `TypeAlias`
- Remember: type hints are for static analysis, not runtime enforcement

## Additional Resources

- **Official typing documentation**: <https://docs.python.org/3/library/typing.html>
- **Mypy documentation**: <https://mypy.readthedocs.io/>
- **typing.python.org**: <https://typing.python.org/>
- **PEP Index**: <https://peps.python.org/> (search for typing-related PEPs)
- **Mypy cheat sheet**: <https://mypy.readthedocs.io/en/stable/cheat_sheet_py3.html>

**Last Verified**: 2025-01-17
