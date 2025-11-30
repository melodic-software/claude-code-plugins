# Python Performance Optimization

Comprehensive guide to profiling and optimizing Python code for better performance, backed by official documentation and current best practices.

**Official Documentation:**

- [Python Profilers](https://docs.python.org/3/library/profile.html)
- [functools - Higher-order functions](https://docs.python.org/3/library/functools.html)
- [collections - Container datatypes](https://docs.python.org/3/library/collections.html)
- [NumPy Performance Guide](https://numpy.org/doc/stable/user/whatisnumpy.html)

**Last Verified:** 2025-11-17

---

## Table of Contents

1. [Profiling Tools](#profiling-tools)
2. [Common Performance Pitfalls](#common-performance-pitfalls)
3. [Data Structures](#data-structures)
4. [List Comprehensions vs Loops](#list-comprehensions-vs-loops)
5. [**slots** for Memory Optimization](#slots-for-memory-optimization)
6. [Caching and Memoization](#caching-and-memoization)
7. [NumPy/Pandas Optimization](#numpypandas-optimization)
8. [Database Query Optimization](#database-query-optimization)
9. [Cython for Performance-Critical Code](#cython-for-performance-critical-code)
10. [Multiprocessing vs Threading](#multiprocessing-vs-threading)
11. [Performance Best Practices](#performance-best-practices)
12. [Tools and Libraries](#tools-and-libraries)

---

## Profiling Tools

### cProfile (Standard Library)

**Official Documentation:** [Python Profilers](https://docs.python.org/3/library/profile.html)

`cProfile` is the recommended profiler for most users - it's a C extension with reasonable overhead suitable for profiling long-running programs.

**Basic Usage:**

```python
import cProfile
import re

# Profile a simple function call
cProfile.run('re.compile("foo|bar")')
```

**Output Format:**

```text
214 function calls (207 primitive calls) in 0.002 seconds

Ordered by: cumulative time

ncalls  tottime  percall  cumtime  percall filename:lineno(function)
     1    0.000    0.000    0.002    0.002 {built-in method builtins.exec}
     1    0.000    0.000    0.001    0.001 <string>:1(<module>)
     1    0.000    0.000    0.001    0.001 __init__.py:250(compile)
```

**Column Definitions:**

- `ncalls`: Number of calls
- `tottime`: Total time spent in function (excluding sub-functions)
- `percall`: `tottime` divided by `ncalls`
- `cumtime`: Cumulative time spent in this and all subfunctions
- `percall`: `cumtime` divided by primitive calls
- `filename:lineno(function)`: Location of each function

**Command-Line Usage:**

```bash
python -m cProfile [-o output_file] [-s sort_order] script.py
```

**Programmatic Usage:**

```python
import cProfile
import pstats
import io
from pstats import SortKey

pr = cProfile.Profile()
pr.enable()
# ... code to profile ...
pr.disable()

s = io.StringIO()
sortby = SortKey.CUMULATIVE
ps = pstats.Stats(pr, stream=s).sort_stats(sortby)
ps.print_stats()
print(s.getvalue())
```

**Context Manager (cProfile only):**

```python
import cProfile

with cProfile.Profile() as pr:
    # ... code to profile ...
    pr.print_stats()
```

**Save Results to File:**

```python
cProfile.run('my_function()', 'profile_stats')

# Later, analyze results:
import pstats
p = pstats.Stats('profile_stats')
p.strip_dirs().sort_stats(SortKey.CUMULATIVE).print_stats(10)
```

### line_profiler (Third-Party)

For line-by-line profiling to identify expensive operations within specific functions.

**Installation:**

```bash
pip install line_profiler
```

**Usage:**

```python
from line_profiler import LineProfiler

def my_function():
    # ... code ...
    pass

lp = LineProfiler()
lp.add_function(my_function)
lp_wrapper = lp(my_function)
lp_wrapper()
lp.print_stats()
```

**When to Use:** When cProfile identifies a slow function and you need to know which specific lines are causing the slowdown.

### memory_profiler (Third-Party)

For tracking memory usage line-by-line.

**Installation:**

```bash
pip install memory_profiler
```

**Usage:**

```python
from memory_profiler import profile

@profile
def my_function():
    large_list = [1] * (10 ** 6)
    return sum(large_list)
```

**When to Use:** Identifying memory leaks or understanding memory consumption patterns.

### py-spy (Production Profiling)

Low-overhead sampling profiler suitable for production environments. Works without code changes.

**Installation:**

```bash
pip install py-spy
```

**Usage:**

```bash
# Sample a running Python process
py-spy top --pid 12345

# Generate flamegraph
py-spy record -o profile.svg -- python my_script.py
```

**When to Use:** Profiling production systems or when you can't modify source code.

### Snakeviz (Visualization)

Visualize cProfile output in an interactive browser-based interface.

**Installation:**

```bash
pip install snakeviz
```

**Usage:**

```bash
# Generate profile data
python -m cProfile -o program.prof my_script.py

# Visualize
snakeviz program.prof
```

---

## Common Performance Pitfalls

### String Concatenation in Loops

**❌ Slow (Quadratic Time Complexity):**

```python
result = ""
for item in large_list:
    result += str(item)  # Creates new string each iteration
```

**✅ Fast (Linear Time):**

```python
result = "".join(str(item) for item in large_list)
```

**Benchmark:** For 10,000 items, `join()` is ~100x faster than `+=`.

### Global vs Local Variable Access

**❌ Slower:**

```python
import math

def compute_distances(points):
    distances = []
    for p1, p2 in points:
        # Global lookup for 'math' every iteration
        d = math.sqrt((p2[0] - p1[0])**2 + (p2[1] - p1[1])**2)
        distances.append(d)
    return distances
```

**✅ Faster:**

```python
import math

def compute_distances(points):
    sqrt = math.sqrt  # Local reference
    distances = []
    for p1, p2 in points:
        d = sqrt((p2[0] - p1[0])**2 + (p2[1] - p1[1])**2)
        distances.append(d)
    return distances
```

**Why:** Local variable access is faster than global lookups (~15-30% speedup in tight loops).

### Unnecessary Function Calls in Loops

**❌ Slow:**

```python
data = [1, 2, 3, 4, 5]
for i in range(len(data)):  # len() called every iteration (no - cached)
    # But range() creates unnecessary overhead
    process(data[i])
```

**✅ Fast:**

```python
for item in data:  # Direct iteration
    process(item)
```

### dict.get() vs Exception Handling

**For Expected Keys:**

```python
# ❌ Slower (exception overhead)
try:
    value = my_dict[key]
except KeyError:
    value = default

# ✅ Faster (direct lookup)
value = my_dict.get(key, default)
```

**For Rare Missing Keys:**

```python
# ✅ Faster (EAFP - Easier to Ask Forgiveness than Permission)
try:
    value = my_dict[key]
except KeyError:
    value = expensive_default_computation()
```

---

## Data Structures

**Official Documentation:** [collections module](https://docs.python.org/3/library/collections.html)

### Choosing the Right Data Structure

| Operation | list | tuple | set | dict | deque | defaultdict |
| --- | --- | --- | --- | --- | --- | --- |
| Access by index | O(1) | O(1) | N/A | N/A | O(n) | N/A |
| Access by key | N/A | N/A | N/A | O(1) | N/A | O(1) |
| Search (contains) | O(n) | O(n) | O(1) | O(1) | O(n) | O(1) |
| Insert/Delete (end) | O(1) | N/A | O(1) | O(1) | O(1) | O(1) |
| Insert/Delete (start) | O(n) | N/A | O(1) | O(1) | O(1) | O(1) |
| Insert/Delete (middle) | O(n) | N/A | O(1) | O(1) | O(n) | O(1) |
| Memory overhead | Low | Lowest | Medium | Medium | Medium | Medium |

### collections.defaultdict

**Official Documentation:** [defaultdict objects](https://docs.python.org/3/library/collections.html#defaultdict-objects)

Avoid `KeyError` and simplify grouping operations.

**❌ Without defaultdict:**

```python
data = [('a', 1), ('b', 2), ('a', 3), ('b', 4)]
grouped = {}
for key, value in data:
    if key not in grouped:
        grouped[key] = []
    grouped[key].append(value)
```

**✅ With defaultdict:**

```python
from collections import defaultdict

data = [('a', 1), ('b', 2), ('a', 3), ('b', 4)]
grouped = defaultdict(list)
for key, value in data:
    grouped[key].append(value)
```

### collections.Counter

**Official Documentation:** [Counter objects](https://docs.python.org/3/library/collections.html#counter-objects)

Efficient counting and tallying.

```python
from collections import Counter

# Count word occurrences
words = ['apple', 'banana', 'apple', 'cherry', 'banana', 'apple']
counts = Counter(words)
# Counter({'apple': 3, 'banana': 2, 'cherry': 1})

# Most common elements
counts.most_common(2)  # [('apple', 3), ('banana', 2)]

# Combine counters
c1 = Counter(a=3, b=1)
c2 = Counter(a=1, b=2)
c1 + c2  # Counter({'a': 4, 'b': 3})
```

### collections.deque

**Official Documentation:** [deque objects](https://docs.python.org/3/library/collections.html#deque-objects)

Optimized for fast appends and pops from both ends (O(1) vs O(n) for lists).

```python
from collections import deque

# Queue operations
queue = deque(['a', 'b', 'c'])
queue.append('d')      # Add to right: O(1)
queue.appendleft('z')  # Add to left: O(1)
queue.pop()            # Remove from right: O(1)
queue.popleft()        # Remove from left: O(1)

# Bounded deque (circular buffer)
recent = deque(maxlen=3)
for i in range(5):
    recent.append(i)  # Automatically discards oldest when full
# deque([2, 3, 4], maxlen=3)
```

**Use Case:** Implementing queues, circular buffers, or maintaining sliding windows.

---

## List Comprehensions vs Loops

List comprehensions are typically faster than equivalent loops due to optimized bytecode.

**❌ Slower (Explicit Loop):**

```python
squares = []
for x in range(1000):
    squares.append(x ** 2)
```

**✅ Faster (List Comprehension):**

```python
squares = [x ** 2 for x in range(1000)]
```

**Benchmark:** List comprehensions are ~20-30% faster for simple operations.

### Generator Expressions for Large Datasets

When you don't need the entire list in memory:

```python
# ❌ Memory-intensive
squares = [x ** 2 for x in range(10_000_000)]  # Allocates entire list

# ✅ Memory-efficient
squares = (x ** 2 for x in range(10_000_000))  # Yields one at a time
total = sum(squares)  # Process without storing all values
```

**Use Case:** Processing large datasets where you only need to iterate once.

### When to Use Each

- **List comprehension:** Need full list, small to medium size, or multiple iterations
- **Generator expression:** Large datasets, single iteration, memory constraints
- **Explicit loop:** Complex logic, multiple statements per iteration, or need break/continue

---

## **slots** for Memory Optimization

**Official Documentation:** [**slots**](https://docs.python.org/3/reference/datamodel.html#slots)

By default, Python instances use a `__dict__` to store attributes. Using `__slots__` can reduce memory usage by 20-30% for large numbers of instances.

**Without **slots**:**

```python
class Point:
    def __init__(self, x, y):
        self.x = x
        self.y = y

# Each instance has __dict__ overhead
p = Point(1, 2)
```

**With **slots**:**

```python
class Point:
    __slots__ = ('x', 'y')

    def __init__(self, x, y):
        self.x = x
        self.y = y

# No __dict__, fixed attributes only
```

**Benchmarks:**

- Memory savings: ~20-30% per instance
- Attribute access: ~10-15% faster
- Creation time: Slightly faster

**Trade-offs:**

- Cannot add attributes dynamically
- No `__dict__` (some libraries expect it)
- Slightly more restrictive

**When to Use:**

- Creating many instances (thousands+)
- Fixed set of attributes
- Memory is a constraint
- Performance-critical data structures

---

## Caching and Memoization

**Official Documentation:** [functools.lru_cache](https://docs.python.org/3/library/functools.html#functools.lru_cache)

### functools.lru_cache (Least Recently Used Cache)

Cache function results to avoid recomputation.

#### Example: Fibonacci Sequence

```python
from functools import lru_cache

# ❌ Without cache: O(2^n) - extremely slow
def fib(n):
    if n < 2:
        return n
    return fib(n-1) + fib(n-2)

# ✅ With cache: O(n) - very fast
@lru_cache(maxsize=None)
def fib_cached(n):
    if n < 2:
        return n
    return fib_cached(n-1) + fib_cached(n-2)

# fib(35) takes seconds, fib_cached(35) is instant
```

**Cache Parameters:**

```python
@lru_cache(maxsize=128)  # Cache up to 128 results (default)
def expensive_function(x):
    # ... complex computation ...
    return result

# Unbounded cache (Python 3.9+)
@lru_cache(maxsize=None)
# Or equivalently:
from functools import cache
@cache
def function(x):
    return result
```

**Cache Statistics:**

```python
@lru_cache(maxsize=32)
def get_data(key):
    return expensive_fetch(key)

# Check cache effectiveness
print(get_data.cache_info())
# CacheInfo(hits=3, misses=8, maxsize=32, currsize=8)

# Clear cache
get_data.cache_clear()
```

**When to Use:**

- ✅ Pure functions (same input → same output)
- ✅ Expensive computations
- ✅ Frequently called with same arguments
- ❌ Functions with side effects
- ❌ Functions returning mutable objects

### functools.cache (Python 3.9+)

Simpler, faster unbounded cache.

```python
from functools import cache

@cache
def factorial(n):
    return n * factorial(n-1) if n else 1

factorial(10)  # Computed
factorial(5)   # Retrieved from cache
factorial.cache_info()
```

**Difference from lru_cache:**

- No size limit (unbounded)
- Slightly faster (no eviction logic)
- Simpler implementation

---

## NumPy/Pandas Optimization

**Official Documentation:** [NumPy Performance](https://numpy.org/doc/stable/user/whatisnumpy.html)

### Vectorization in NumPy

NumPy operations are implemented in C and orders of magnitude faster than Python loops.

**❌ Slow (Python loops):**

```python
import numpy as np

a = [1, 2, 3, 4, 5]
b = [6, 7, 8, 9, 10]
c = []
for i in range(len(a)):
    c.append(a[i] * b[i])
```

**✅ Fast (NumPy vectorization):**

```python
import numpy as np

a = np.array([1, 2, 3, 4, 5])
b = np.array([6, 7, 8, 9, 10])
c = a * b  # Element-wise multiplication in C
```

**Benchmark:** NumPy vectorization is 10-100x faster for numerical operations.

### Why NumPy is Fast

From official documentation:

1. **Vectorization:** Operations executed in optimized C code
2. **Fixed types:** Homogeneous data types (no type checking per element)
3. **Contiguous memory:** Cache-friendly memory layout
4. **Broadcasting:** Efficient element-wise operations on arrays of different shapes

**Example - Broadcasting:**

```python
import numpy as np

# Add scalar to array (broadcasting)
arr = np.array([1, 2, 3, 4])
result = arr + 10  # [11, 12, 13, 14]

# Add 1D array to 2D array (broadcasting)
matrix = np.array([[1, 2, 3], [4, 5, 6]])
row = np.array([10, 20, 30])
result = matrix + row
# [[11, 22, 33],
#  [14, 25, 36]]
```

### Pandas Optimization

**Avoid iterrows():**

```python
import pandas as pd

df = pd.DataFrame({'A': range(1000), 'B': range(1000, 2000)})

# ❌ Very slow: ~100-1000x slower
result = []
for idx, row in df.iterrows():
    result.append(row['A'] + row['B'])

# ✅ Fast: Vectorized operation
result = df['A'] + df['B']

# ✅ Also fast: apply() for complex operations
result = df.apply(lambda row: row['A'] + row['B'], axis=1)

# ✅ Fastest for simple operations: direct vectorized
result = df['A'].values + df['B'].values  # NumPy arrays
```

**Prefer Vectorized Operations:**

```python
# ❌ Slow
df['C'] = df.apply(lambda row: row['A'] * 2 if row['B'] > 1500 else row['A'], axis=1)

# ✅ Fast
df['C'] = np.where(df['B'] > 1500, df['A'] * 2, df['A'])
```

**Use .loc/.iloc for Filtering:**

```python
# ✅ Efficient boolean indexing
filtered = df[df['B'] > 1500]

# ✅ Efficient column selection
subset = df[['A', 'B']]
```

---

## Database Query Optimization

### N+1 Query Problem

**❌ N+1 Queries (Very Slow):**

```python
# Fetch users
users = User.query.all()  # 1 query

# Fetch posts for each user
for user in users:
    posts = user.posts  # N queries (one per user)
```

**✅ Eager Loading (Fast):**

```python
# SQLAlchemy
from sqlalchemy.orm import joinedload

users = User.query.options(joinedload(User.posts)).all()  # 1 query with JOIN

# Django ORM
users = User.objects.prefetch_related('posts')  # 2 queries (users + all posts)
```

### Batch Operations

**❌ Individual Inserts:**

```python
for item in large_dataset:
    db.session.add(Item(data=item))
    db.session.commit()  # Commit per item - very slow
```

**✅ Bulk Insert:**

```python
# SQLAlchemy
db.session.bulk_insert_mappings(Item, large_dataset)
db.session.commit()  # Single commit

# Django ORM
Item.objects.bulk_create([Item(data=d) for d in large_dataset])
```

### Connection Pooling

Reuse database connections instead of creating new ones.

```python
from sqlalchemy import create_engine

# ✅ With connection pooling
engine = create_engine(
    'postgresql://user:pass@localhost/db',
    pool_size=10,        # Maintain 10 connections
    max_overflow=20,     # Allow 20 additional connections
    pool_recycle=3600    # Recycle connections after 1 hour
)
```

---

## Cython for Performance-Critical Code

Cython compiles Python code to C for significant speedups (10-100x for numerical code).

### When to Use Cython

- ✅ CPU-bound numerical computations
- ✅ Tight loops with known types
- ✅ Performance-critical hot paths (identified by profiling)
- ❌ I/O-bound operations
- ❌ Code that's already fast enough

### Basic Cython Example

**Pure Python (slow):**

```python
# slow.py
def compute_sum(n):
    total = 0
    for i in range(n):
        total += i
    return total
```

**Cython with Type Annotations (fast):**

```cython
# fast.pyx
def compute_sum(int n):
    cdef int i
    cdef long total = 0
    for i in range(n):
        total += i
    return total
```

**Compilation:**

Create `setup.py`:

```python
from setuptools import setup
from Cython.Build import cythonize

setup(
    ext_modules=cythonize("fast.pyx")
)
```

Build:

```bash
python setup.py build_ext --inplace
```

**Speedup:** 10-50x faster for numerical loops with type annotations.

### Type Annotations in Cython

```cython
# Declare C types for variables
cdef int x = 10
cdef double y = 3.14
cdef list my_list = [1, 2, 3]

# Type function arguments and return values
def process(int n, double factor) -> double:
    cdef double result = n * factor
    return result

# Use C arrays for maximum performance
cdef int arr[100]  # Fixed-size C array
```

---

## Multiprocessing vs Threading

### The GIL (Global Interpreter Lock)

Python's GIL prevents true parallel execution of threads for CPU-bound tasks.

**When to Use Each:**

| Task Type | Use | Reason |
| --- | --- | --- |
| CPU-bound | `multiprocessing` | Bypasses GIL, true parallelism |
| I/O-bound | `asyncio` (preferred) or `threading` | GIL released during I/O |
| Mixed | Depends on bottleneck | Profile first |

### Multiprocessing (CPU-bound)

#### Example: Parallel Computation

```python
from multiprocessing import Pool
import time

def cpu_intensive(n):
    # Simulate heavy computation
    return sum(i*i for i in range(n))

if __name__ == '__main__':
    data = [10_000_000] * 8

    # ❌ Sequential: ~8 seconds (on 8-core machine)
    start = time.time()
    results = [cpu_intensive(n) for n in data]
    print(f"Sequential: {time.time() - start:.2f}s")

    # ✅ Parallel: ~1 second (8x speedup)
    start = time.time()
    with Pool(processes=8) as pool:
        results = pool.map(cpu_intensive, data)
    print(f"Parallel: {time.time() - start:.2f}s")
```

### Threading (I/O-bound)

**Note:** For I/O-bound tasks, prefer `asyncio` over threading in modern Python.

```python
from concurrent.futures import ThreadPoolExecutor
import requests

def fetch_url(url):
    response = requests.get(url)
    return len(response.content)

urls = ['https://example.com'] * 10

# ❌ Sequential: ~10 seconds
results = [fetch_url(url) for url in urls]

# ✅ Threaded: ~1 second (I/O happens in parallel)
with ThreadPoolExecutor(max_workers=10) as executor:
    results = list(executor.map(fetch_url, urls))
```

### concurrent.futures (Unified Interface)

```python
from concurrent.futures import ProcessPoolExecutor, ThreadPoolExecutor

# CPU-bound: Use processes
with ProcessPoolExecutor(max_workers=4) as executor:
    results = executor.map(cpu_function, data)

# I/O-bound: Use threads
with ThreadPoolExecutor(max_workers=10) as executor:
    results = executor.map(io_function, data)
```

---

## Performance Best Practices

### 1. Profile Before Optimizing

**Quote from Donald Knuth:**
> "Premature optimization is the root of all evil."

Always profile to find actual bottlenecks:

```python
import cProfile

cProfile.run('my_slow_function()')
```

Focus optimization efforts on the top 10-20% of time-consuming operations.

### 2. Optimize Hot Paths Only

Use profiling to identify:

- Functions called most frequently
- Functions consuming most cumulative time
- Inner loops in performance-critical sections

**Example Workflow:**

1. Profile with cProfile
2. Identify top 5 slowest functions
3. Use line_profiler on those functions
4. Optimize specific slow lines
5. Re-profile to verify improvement

### 3. Use Built-in Functions

Built-in functions are implemented in C and highly optimized:

```python
# ✅ Use built-ins when possible
result = sum(numbers)           # Fast (C implementation)
result = max(numbers)           # Fast
result = sorted(numbers)        # Fast

# ❌ Avoid reimplementing
result = 0
for n in numbers:
    result += n  # Slower than sum()
```

### 4. Readability vs Performance Trade-offs

**Balance:** Readable code that's "fast enough" is better than unreadable optimized code.

```python
# ✅ Clear and fast enough for most cases
total = sum(x for x in data if x > 0)

# ❌ Micro-optimized but harder to read (only if proven bottleneck)
total = sum(filter(lambda x: x > 0, data))
```

### 5. Measure Everything

```python
import time

start = time.perf_counter()
# ... code to measure ...
elapsed = time.perf_counter() - start
print(f"Elapsed: {elapsed:.4f}s")
```

Use `timeit` for accurate micro-benchmarks:

```python
import timeit

# Compare two approaches
time1 = timeit.timeit('sum(range(100))', number=10000)
time2 = timeit.timeit('[x for x in range(100)]', number=10000)
print(f"sum: {time1:.4f}s, comprehension: {time2:.4f}s")
```

### 6. Algorithm Complexity Matters Most

**Big O Notation:**

| Complexity | Example | Performance |
| --- | --- | --- |
| O(1) | Dict lookup | Constant |
| O(log n) | Binary search | Excellent |
| O(n) | Linear scan | Good |
| O(n log n) | Efficient sort | Acceptable |
| O(n²) | Nested loops | Poor |
| O(2^n) | Recursive without cache | Terrible |

**Example:** Choosing the right algorithm matters more than micro-optimizations:

```python
# ❌ O(n²) - check membership in list
if item in large_list:  # Linear search
    pass

# ✅ O(1) - check membership in set
if item in large_set:  # Hash lookup
    pass
```

For 10,000 items, the set lookup is ~10,000x faster.

---

## Tools and Libraries

### numba (JIT Compilation)

Just-in-time compilation for NumPy-heavy code.

**Installation:**

```bash
pip install numba
```

**Usage:**

```python
from numba import jit
import numpy as np

@jit(nopython=True)  # Force pure compiled mode
def fast_function(x):
    total = 0
    for i in range(len(x)):
        total += x[i] ** 2
    return total

arr = np.arange(1_000_000)
result = fast_function(arr)  # Near C speed
```

**Speedup:** 10-100x for numerical loops, comparable to Cython.

**When to Use:**

- NumPy-heavy numerical code
- Want speedup without learning Cython syntax
- Can tolerate JIT compilation overhead

### PyPy (Alternative Interpreter)

JIT-compiling Python interpreter, can be 2-10x faster for pure Python code.

**Installation:**

```bash
# Download from https://www.pypy.org/
```

**Caveats:**

- Not compatible with all C extensions (NumPy support exists but limited)
- Best for pure Python code
- Startup overhead (JIT warmup)

**When to Use:**

- Pure Python applications
- Long-running processes
- No heavy C extension dependencies

### pybind11 (C++ Integration)

Seamlessly integrate C++ code with Python.

**When to Use:**

- Need maximum performance (C++ speed)
- Existing C++ codebase to integrate
- Complex algorithms best expressed in C++

**Example:**

```cpp
// example.cpp
#include <pybind11/pybind11.h>

int add(int i, int j) {
    return i + j;
}

PYBIND11_MODULE(example, m) {
    m.def("add", &add);
}
```

Compile and use in Python:

```python
import example
result = example.add(1, 2)  # C++ speed
```

---

## Summary Checklist

**Before Optimization:**

- ✅ Profile to find bottlenecks (cProfile)
- ✅ Identify hot paths (top 20% of time)
- ✅ Set performance goals (how much faster is enough?)

**Common Optimizations:**

- ✅ Use appropriate data structures (dict/set for lookups)
- ✅ Cache expensive function calls (lru_cache)
- ✅ Vectorize with NumPy for numerical operations
- ✅ Use list comprehensions over loops
- ✅ Avoid string concatenation in loops
- ✅ Consider **slots** for many instances
- ✅ Use built-in functions when possible

**Advanced Optimizations:**

- ✅ Multiprocessing for CPU-bound parallelism
- ✅ asyncio/threading for I/O-bound concurrency
- ✅ Cython/Numba for performance-critical hot paths
- ✅ Database query optimization (eager loading, batching)

**Always:**

- ✅ Measure before and after
- ✅ Balance readability with performance
- ✅ Optimize algorithms before micro-optimizations
- ✅ Document why optimizations were needed

---

## Additional Resources

**Official Python Documentation:**

- [Python Performance Tips](https://wiki.python.org/moin/PythonSpeed/PerformanceTips)
- [timeit - Measure execution time](https://docs.python.org/3/library/timeit.html)
- [Profiling and Debugging](https://docs.python.org/3/library/debug.html)

**NumPy Documentation:**

- [NumPy Performance](https://numpy.org/doc/stable/user/performance.html)
- [NumPy Best Practices](https://numpy.org/doc/stable/user/basics.html)

**Third-Party Resources:**

- [Cython Documentation](https://cython.readthedocs.io/)
- [Numba Documentation](https://numba.pydata.org/)
- [PyPy Website](https://www.pypy.org/)

---

**Last Updated:** 2025-11-17
**Python Versions:** 3.9+
**Verified Against:** Python 3.13, 3.14 official documentation
