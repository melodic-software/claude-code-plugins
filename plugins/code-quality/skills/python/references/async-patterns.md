# Async Patterns

Comprehensive guide to asynchronous programming in Python using `asyncio`, covering fundamentals, patterns, libraries, and best practices.

## Overview

Python's `asyncio` library enables writing concurrent code using the `async`/`await` syntax. It's ideal for I/O-bound operations where you spend time waiting rather than computing, such as network requests, file operations, and database queries.

**Official Documentation:** [Python asyncio Documentation](https://docs.python.org/3/library/asyncio.html)

## Table of Contents

- [Fundamentals](#fundamentals)
- [Creating and Running Tasks](#creating-and-running-tasks)
- [Structured Concurrency (Python 3.11+)](#structured-concurrency-python-311)
- [Common Async Patterns](#common-async-patterns)
- [Error Handling](#error-handling)
- [Async I/O Libraries](#async-io-libraries)
- [Synchronization Primitives](#synchronization-primitives)
- [Mixing Sync and Async](#mixing-sync-and-async)
- [When to Use Async](#when-to-use-async)
- [Common Pitfalls](#common-pitfalls)
- [Testing Async Code](#testing-async-code)
- [Performance Considerations](#performance-considerations)

## Fundamentals

### async/await Syntax

Coroutines are declared with `async def` and awaited with `await`:

```python
import asyncio

async def main():
    print('hello')
    await asyncio.sleep(1)  # Non-blocking sleep
    print('world')

# Run the coroutine
asyncio.run(main())
```

**Source:** [Python asyncio - Coroutines](https://docs.python.org/3/library/asyncio-task.html#coroutines)

### Key Concepts

- **Coroutine function:** An `async def` function
- **Coroutine object:** Object returned by calling a coroutine function
- **Awaitable:** Object that can be used in an `await` expression (coroutines, Tasks, Futures)
- **Event loop:** Core of asyncio - runs async tasks and callbacks, performs network I/O

**Important:** Simply calling a coroutine doesn't execute it - it returns a coroutine object that must be awaited or scheduled:

```python
async def nested():
    return 42

async def main():
    # Wrong - creates coroutine but doesn't run it (raises RuntimeWarning)
    nested()

    # Correct - awaits the coroutine
    result = await nested()
    print(result)  # 42

asyncio.run(main())
```

### Entry Point

Use `asyncio.run()` to run the top-level coroutine:

```python
import asyncio

async def main():
    await asyncio.sleep(1)
    return 'done'

# This manages the event loop for you
result = asyncio.run(main())
print(result)  # 'done'
```

**Source:** [Python asyncio - Runners](https://docs.python.org/3/library/asyncio-runner.html)

## Creating and Running Tasks

### Sequential vs Concurrent Execution

**Sequential (slow):**

```python
import asyncio
import time

async def say_after(delay, what):
    await asyncio.sleep(delay)
    print(what)

async def main():
    print(f"started at {time.strftime('%X')}")

    await say_after(1, 'hello')  # Wait 1 second
    await say_after(2, 'world')  # Then wait 2 more seconds

    print(f"finished at {time.strftime('%X')}")
    # Total time: ~3 seconds

asyncio.run(main())
```

**Concurrent (fast) with create_task:**

```python
async def main():
    task1 = asyncio.create_task(say_after(1, 'hello'))
    task2 = asyncio.create_task(say_after(2, 'world'))

    print(f"started at {time.strftime('%X')}")

    # Wait for both tasks to complete
    await task1
    await task2

    print(f"finished at {time.strftime('%X')}")
    # Total time: ~2 seconds (tasks run concurrently)

asyncio.run(main())
```

**Source:** [Python asyncio - Creating Tasks](https://docs.python.org/3/library/asyncio-task.html#creating-tasks)

### Using asyncio.gather()

Run multiple coroutines concurrently and collect their results:

```python
import asyncio

async def factorial(name, number):
    f = 1
    for i in range(2, number + 1):
        print(f"Task {name}: Compute factorial({number}), currently i={i}...")
        await asyncio.sleep(1)
        f *= i
    print(f"Task {name}: factorial({number}) = {f}")
    return f

async def main():
    # Schedule three calls concurrently
    results = await asyncio.gather(
        factorial("A", 2),
        factorial("B", 3),
        factorial("C", 4),
    )
    print(results)  # [2, 6, 24]

asyncio.run(main())
```

**Key differences:**

- `gather()` collects results in order
- If `return_exceptions=False` (default), first exception propagates immediately
- If `return_exceptions=True`, exceptions are included in the results list

**Source:** [Python asyncio - gather()](https://docs.python.org/3/library/asyncio-task.html#asyncio.gather)

### Fire-and-Forget Background Tasks

**Important:** Save references to tasks to prevent garbage collection:

```python
background_tasks = set()

async def some_coro(param):
    await asyncio.sleep(1)
    print(f"Completed: {param}")

for i in range(10):
    task = asyncio.create_task(some_coro(param=i))

    # Add task to the set (creates strong reference)
    background_tasks.add(task)

    # Remove reference after completion
    task.add_done_callback(background_tasks.discard)
```

**Source:** [Python asyncio - create_task() Important note](https://docs.python.org/3/library/asyncio-task.html#asyncio.create_task)

## Structured Concurrency (Python 3.11+)

`TaskGroup` provides a modern, safer alternative to `create_task()` with automatic cancellation and exception handling.

### Basic TaskGroup Usage

```python
import asyncio

async def say_after(delay, what):
    await asyncio.sleep(delay)
    print(what)

async def main():
    async with asyncio.TaskGroup() as tg:
        task1 = tg.create_task(say_after(1, 'hello'))
        task2 = tg.create_task(say_after(2, 'world'))

        print(f"started at {time.strftime('%X')}")

    # The await is implicit when context manager exits
    print(f"finished at {time.strftime('%X')}")
    print(f"Both tasks completed: {task1.result()}, {task2.result()}")

asyncio.run(main())
```

**Source:** [Python asyncio - Task Groups](https://docs.python.org/3/library/asyncio-task.html#task-groups)

### TaskGroup Exception Handling

TaskGroup automatically cancels remaining tasks if one fails:

```python
import asyncio

async def task_that_fails():
    await asyncio.sleep(1)
    raise ValueError("Task failed!")

async def task_that_succeeds():
    await asyncio.sleep(2)
    return "success"

async def main():
    try:
        async with asyncio.TaskGroup() as tg:
            tg.create_task(task_that_fails())
            tg.create_task(task_that_succeeds())
    except* ValueError as eg:
        print(f"Caught exception group: {eg}")
        # Second task was cancelled automatically

asyncio.run(main())
```

**Key features:**

- All tasks must complete before exiting the context manager
- If any task fails, remaining tasks are cancelled
- Exceptions are collected into an `ExceptionGroup`
- Stronger safety guarantees than `gather()`

**Source:** [Python asyncio - TaskGroup behavior](https://docs.python.org/3/library/asyncio-task.html#asyncio.TaskGroup)

### TaskGroup vs gather() vs create_task()

| Method | Structured Concurrency | Exception Handling | Result Collection | Use Case |
| --- | --- | --- | --- | --- |
| **TaskGroup** | Yes | Automatic cancellation on error | By design (access via task.result()) | Managed parallel tasks, robust apps |
| **gather()** | No | Combined (all or first exception) | Yes (ordered list) | Collecting results from I/O calls |
| **create_task()** | No | Manual | Not directly | Background or long-lived tasks |

**Source:** [Best practices comparison (Perplexity 2024)](https://www.paulnorvig.com/guides/asynchronous-programming-with-asyncio-in-python.html)

## Common Async Patterns

### Concurrent HTTP Requests

```python
import asyncio
import aiohttp

async def fetch(session, url):
    async with session.get(url) as response:
        return await response.text()

async def main():
    urls = [
        'http://httpbin.org/delay/1',
        'http://httpbin.org/delay/2',
        'http://httpbin.org/delay/3',
    ]

    async with aiohttp.ClientSession() as session:
        # Run all requests concurrently
        results = await asyncio.gather(
            *[fetch(session, url) for url in urls]
        )
        print(f"Fetched {len(results)} pages")

asyncio.run(main())
```

**Source:** [aiohttp documentation](https://github.com/aio-libs/aiohttp)

### Producer-Consumer with Queue

```python
import asyncio
import random

async def producer(queue, n):
    for i in range(n):
        # Simulate work
        await asyncio.sleep(random.random())
        item = f'item-{i}'
        await queue.put(item)
        print(f'Produced {item}')

    # Signal consumers to exit
    await queue.put(None)

async def consumer(queue, name):
    while True:
        item = await queue.get()
        if item is None:
            # End signal received
            queue.task_done()
            break

        # Process item
        await asyncio.sleep(random.random())
        print(f'{name} consumed {item}')
        queue.task_done()

async def main():
    queue = asyncio.Queue()

    # Create producer and multiple consumers
    async with asyncio.TaskGroup() as tg:
        tg.create_task(producer(queue, 10))
        tg.create_task(consumer(queue, 'Consumer-1'))
        tg.create_task(consumer(queue, 'Consumer-2'))

asyncio.run(main())
```

**Source:** [Python asyncio - Queues](https://docs.python.org/3/library/asyncio-queue.html)

### Rate Limiting with Semaphore

```python
import asyncio

async def limited_worker(semaphore, worker_id):
    async with semaphore:
        print(f'Worker {worker_id} starting')
        await asyncio.sleep(2)
        print(f'Worker {worker_id} finishing')

async def main():
    # Limit to 3 concurrent workers
    semaphore = asyncio.Semaphore(3)

    # Create 10 workers (only 3 run at a time)
    await asyncio.gather(
        *[limited_worker(semaphore, i) for i in range(10)]
    )

asyncio.run(main())
```

**Source:** [Python asyncio - Semaphore](https://docs.python.org/3/library/asyncio-sync.html#asyncio.Semaphore)

### Timeouts

```python
import asyncio

async def long_running_task():
    await asyncio.sleep(10)
    return 'completed'

async def main():
    # Using asyncio.timeout (Python 3.11+)
    try:
        async with asyncio.timeout(5):
            result = await long_running_task()
    except TimeoutError:
        print("Task timed out after 5 seconds")

    # Using asyncio.wait_for (all versions)
    try:
        result = await asyncio.wait_for(long_running_task(), timeout=5.0)
    except asyncio.TimeoutError:
        print("Task timed out")

asyncio.run(main())
```

**Source:** [Python asyncio - Timeouts](https://docs.python.org/3/library/asyncio-task.html#timeouts)

### Retry Pattern

```python
import asyncio

async def fetch_data_with_retry(max_retries=3):
    for attempt in range(max_retries):
        try:
            # Simulate API call that might fail
            async with asyncio.timeout(2):
                result = await unreliable_api_call()
                return result
        except (TimeoutError, ConnectionError) as e:
            if attempt == max_retries - 1:
                raise
            wait_time = 2 ** attempt  # Exponential backoff
            print(f"Attempt {attempt + 1} failed, retrying in {wait_time}s...")
            await asyncio.sleep(wait_time)

async def unreliable_api_call():
    # Simulated unreliable API
    await asyncio.sleep(1)
    import random
    if random.random() < 0.7:
        raise ConnectionError("Connection failed")
    return "success"
```

**Source:** Best practices from [asyncio design patterns](https://dev-kit.io/blog/python/asyncio-design-patterns)

## Error Handling

### Try/Except in Async Functions

```python
import asyncio

async def risky_operation():
    await asyncio.sleep(1)
    raise ValueError("Something went wrong")

async def main():
    try:
        result = await risky_operation()
    except ValueError as e:
        print(f"Caught error: {e}")
    finally:
        print("Cleanup completed")

asyncio.run(main())
```

### Task Exceptions

```python
import asyncio

async def failing_task():
    await asyncio.sleep(1)
    raise ValueError("Task failed")

async def main():
    task = asyncio.create_task(failing_task())

    try:
        await task
    except ValueError as e:
        print(f"Caught exception: {e}")

    # Or check exception without raising
    if task.done() and task.exception():
        print(f"Task exception: {task.exception()}")

asyncio.run(main())
```

**Source:** [Python asyncio - Task Object](https://docs.python.org/3/library/asyncio-task.html#task-object)

### TaskGroup Exception Propagation

```python
import asyncio

async def task1():
    await asyncio.sleep(1)
    raise ValueError("Error in task1")

async def task2():
    await asyncio.sleep(2)
    raise TypeError("Error in task2")

async def main():
    try:
        async with asyncio.TaskGroup() as tg:
            tg.create_task(task1())
            tg.create_task(task2())
    except* ValueError as eg:
        print(f"Caught ValueError exceptions: {eg.exceptions}")
    except* TypeError as eg:
        print(f"Caught TypeError exceptions: {eg.exceptions}")

asyncio.run(main())
```

**Note:** Uses exception groups (PEP 654) - multiple exceptions are collected and raised together.

**Source:** [Python asyncio - TaskGroup exceptions](https://docs.python.org/3/library/asyncio-task.html#asyncio.TaskGroup)

### Cancellation Handling

```python
import asyncio

async def cancellable_task():
    try:
        await asyncio.sleep(10)
    except asyncio.CancelledError:
        print("Task was cancelled, cleaning up...")
        # Perform cleanup
        raise  # Re-raise to propagate cancellation

async def main():
    task = asyncio.create_task(cancellable_task())

    await asyncio.sleep(1)
    task.cancel()

    try:
        await task
    except asyncio.CancelledError:
        print("Task cancellation confirmed")

asyncio.run(main())
```

**Source:** [Python asyncio - Task Cancellation](https://docs.python.org/3/library/asyncio-task.html#task-cancellation)

## Async I/O Libraries

### aiohttp - Async HTTP Client/Server

```python
import asyncio
import aiohttp

async def fetch_page(session, url):
    async with session.get(url) as response:
        print(f"Status: {response.status}")
        return await response.text()

async def main():
    async with aiohttp.ClientSession() as session:
        html = await fetch_page(session, 'http://httpbin.org/get')
        print(f"Fetched {len(html)} characters")

asyncio.run(main())
```

**Base URL support:**

```python
async def main():
    async with aiohttp.ClientSession('http://httpbin.org') as session:
        async with session.get('/get'):
            pass
        async with session.post('/post', data=b'data') as resp:
            print(resp.status)

asyncio.run(main())
```

**Official Documentation:** [aiohttp](https://docs.aiohttp.org/)

**Source:** [aiohttp examples](https://github.com/aio-libs/aiohttp)

### aiofiles - Async File I/O

```python
import asyncio
import aiofiles

async def read_file():
    async with aiofiles.open('example.txt', mode='r') as f:
        contents = await f.read()
        print(contents)

async def write_file():
    async with aiofiles.open('output.txt', mode='w') as f:
        await f.write('Hello, async world!\n')

async def read_lines():
    async with aiofiles.open('example.txt', mode='r') as f:
        async for line in f:
            print(line.strip())

async def main():
    await write_file()
    await read_file()
    await read_lines()

asyncio.run(main())
```

**Concurrent file operations:**

```python
import asyncio
import aiofiles

async def read_file(filename):
    async with aiofiles.open(filename, mode='r') as f:
        content = await f.read()
        return filename, len(content)

async def main():
    files = ['file1.txt', 'file2.txt', 'file3.txt']

    # Read multiple files concurrently
    results = await asyncio.gather(
        *[read_file(f) for f in files],
        return_exceptions=True
    )

    for filename, size in results:
        print(f"{filename}: {size} bytes")

asyncio.run(main())
```

**Official Documentation:** [aiofiles](https://github.com/tinche/aiofiles)

**Source:** [aiofiles examples](https://github.com/tinche/aiofiles)

### asyncpg - Async PostgreSQL

```python
import asyncio
import asyncpg

async def main():
    # Create a connection pool
    pool = await asyncpg.create_pool(
        user='user',
        password='password',
        database='database',
        host='127.0.0.1'
    )

    async with pool.acquire() as connection:
        # Execute a query
        rows = await connection.fetch('SELECT * FROM users WHERE age > $1', 18)

        for row in rows:
            print(f"User: {row['name']}, Age: {row['age']}")

    await pool.close()

asyncio.run(main())
```

**Official Documentation:** [asyncpg](https://magicstack.github.io/asyncpg/)

**Source:** [asyncpg on Context7](https://context7.com/magicstack/asyncpg)

### httpx - Sync + Async HTTP

```python
import asyncio
import httpx

async def fetch_data():
    async with httpx.AsyncClient() as client:
        response = await client.get('https://api.github.com/repos/encode/httpx')
        print(response.status_code)
        return response.json()

# httpx also supports sync API
def fetch_data_sync():
    response = httpx.get('https://api.github.com/repos/encode/httpx')
    return response.json()
```

**Official Documentation:** [httpx](https://www.python-httpx.org/)

## Synchronization Primitives

### Lock

```python
import asyncio

lock = asyncio.Lock()
shared_resource = 0

async def increment():
    global shared_resource
    async with lock:
        # Critical section
        temp = shared_resource
        await asyncio.sleep(0.1)
        shared_resource = temp + 1

async def main():
    await asyncio.gather(*[increment() for _ in range(10)])
    print(f"Final value: {shared_resource}")  # 10

asyncio.run(main())
```

### Event

```python
import asyncio

async def waiter(event):
    print('Waiting for event')
    await event.wait()
    print('Event received!')

async def setter(event):
    await asyncio.sleep(2)
    print('Setting event')
    event.set()

async def main():
    event = asyncio.Event()
    await asyncio.gather(waiter(event), setter(event))

asyncio.run(main())
```

### Semaphore

```python
import asyncio

async def access_resource(semaphore, worker_id):
    async with semaphore:
        print(f'Worker {worker_id} acquired semaphore')
        await asyncio.sleep(1)
        print(f'Worker {worker_id} releasing semaphore')

async def main():
    semaphore = asyncio.Semaphore(2)
    await asyncio.gather(*[access_resource(semaphore, i) for i in range(5)])

asyncio.run(main())
```

**Source:** [Python asyncio - Synchronization Primitives](https://docs.python.org/3/library/asyncio-sync.html)

## Mixing Sync and Async

### Running Blocking Code in Threads

**Problem:** Blocking I/O blocks the entire event loop.

**Solution:** Use `asyncio.to_thread()` (Python 3.9+):

```python
import asyncio
import time

def blocking_io():
    print(f"start blocking_io at {time.strftime('%X')}")
    time.sleep(1)  # Blocking call
    print(f"blocking_io complete at {time.strftime('%X')}")

async def main():
    print(f"started main at {time.strftime('%X')}")

    # Run blocking code in a thread
    await asyncio.gather(
        asyncio.to_thread(blocking_io),
        asyncio.sleep(1)
    )

    print(f"finished main at {time.strftime('%X')}")

asyncio.run(main())
```

**Source:** [Python asyncio - to_thread()](https://docs.python.org/3/library/asyncio-task.html#asyncio.to_thread)

### Using run_in_executor (all versions)

```python
import asyncio
import time
from concurrent.futures import ThreadPoolExecutor

def blocking_function(x):
    time.sleep(1)
    return x * 2

async def main():
    loop = asyncio.get_running_loop()

    # Run in default thread pool
    result = await loop.run_in_executor(None, blocking_function, 5)
    print(f"Result: {result}")

    # Or use custom executor
    with ThreadPoolExecutor(max_workers=3) as pool:
        result = await loop.run_in_executor(pool, blocking_function, 10)
        print(f"Result: {result}")

asyncio.run(main())
```

**Source:** [Python asyncio - run_in_executor()](https://docs.python.org/3/library/asyncio-eventloop.html#asyncio.loop.run_in_executor)

## When to Use Async

### Use Async For (I/O-Bound Operations)

- **Network requests:** HTTP APIs, web scraping
- **Database queries:** Multiple concurrent queries
- **File I/O:** Reading/writing many files
- **High concurrency:** Thousands of concurrent connections
- **Waiting operations:** Any operation where you wait for external resources

**Example:** Web server handling many simultaneous connections, chat application, real-time data processing.

### Do NOT Use Async For (CPU-Bound Operations)

- **Data processing:** Heavy computations, number crunching
- **Machine learning:** Training models, data transformation
- **Image/video processing:** Encoding, decoding, filtering
- **Cryptography:** Hashing, encryption
- **Any tight loops with pure Python computation**

**Why:** Python's Global Interpreter Lock (GIL) prevents true parallelism for CPU-bound code. Use `multiprocessing` instead.

**Example:**

```python
# Bad - async doesn't help CPU-bound code
async def cpu_intensive():
    return sum(i * i for i in range(10_000_000))

# Good - use multiprocessing
from concurrent.futures import ProcessPoolExecutor

def cpu_intensive():
    return sum(i * i for i in range(10_000_000))

async def main():
    loop = asyncio.get_running_loop()
    with ProcessPoolExecutor() as pool:
        result = await loop.run_in_executor(pool, cpu_intensive)
```

### Decision Guide

```text
Is your code I/O-bound (waiting for network, disk, database)?
├─ Yes → Use async/await
└─ No → Is it CPU-bound?
    ├─ Yes → Use multiprocessing
    └─ No → Is it simple/straightforward?
        ├─ Yes → Use sync code (avoid unnecessary complexity)
        └─ No → Consider threading for I/O-bound blocking code
```

**Source:** [When to use async (Perplexity 2024)](https://www.theserverside.com/tutorial/Asynchronous-programming-in-Python-tutorial)

## Common Pitfalls

### 1. Blocking the Event Loop

**Problem:** Synchronous blocking operations freeze the entire event loop.

```python
import asyncio
import time

async def bad_example():
    time.sleep(1)  # WRONG - blocks event loop

async def good_example():
    await asyncio.sleep(1)  # Correct - yields control
```

**Solution:** Always use async equivalents:

- `await asyncio.sleep()` instead of `time.sleep()`
- `aiofiles` instead of built-in `open()`
- `aiohttp` instead of `requests`
- `asyncpg` instead of `psycopg2`

### 2. Not Awaiting Coroutines

**Problem:** Calling a coroutine without `await` doesn't execute it.

```python
async def fetch_data():
    await asyncio.sleep(1)
    return "data"

async def bad_example():
    fetch_data()  # WRONG - creates coroutine but doesn't run it
    # RuntimeWarning: coroutine 'fetch_data' was never awaited

async def good_example():
    result = await fetch_data()  # Correct
    return result
```

### 3. Using Sync Libraries in Async Code

**Problem:** Mixing sync and async libraries incorrectly.

```python
import asyncio
import requests  # Sync library

async def bad_example():
    # WRONG - requests.get() is blocking
    response = requests.get('http://example.com')
    return response.text

async def good_example():
    import aiohttp
    async with aiohttp.ClientSession() as session:
        async with session.get('http://example.com') as response:
            return await response.text()
```

### 4. Forgetting to Close Resources

**Problem:** Resource leaks from unclosed connections.

```python
async def bad_example():
    session = aiohttp.ClientSession()
    response = await session.get('http://example.com')
    # WRONG - session never closed

async def good_example():
    async with aiohttp.ClientSession() as session:
        async with session.get('http://example.com') as response:
            return await response.text()
    # Correct - session closed automatically
```

### 5. Not Handling Cancellation

**Problem:** Tasks don't clean up properly when cancelled.

```python
async def bad_example():
    await asyncio.sleep(10)
    # WRONG - no cleanup if cancelled

async def good_example():
    try:
        await asyncio.sleep(10)
    except asyncio.CancelledError:
        # Cleanup resources
        print("Cleaning up...")
        raise  # Re-raise to propagate cancellation
```

### 6. Improper Task References

**Problem:** Tasks get garbage collected if not referenced.

```python
async def bad_example():
    # WRONG - task may be garbage collected
    asyncio.create_task(some_background_work())

async def good_example():
    # Correct - keep strong reference
    background_tasks = set()
    task = asyncio.create_task(some_background_work())
    background_tasks.add(task)
    task.add_done_callback(background_tasks.discard)
```

**Source:** [Common pitfalls](https://docs.python.org/3/library/asyncio-task.html#creating-tasks)

## Testing Async Code

### pytest-asyncio Plugin

Install: `pip install pytest-asyncio`

**Basic async test:**

```python
import asyncio
import pytest

@pytest.mark.asyncio
async def test_async_operation():
    await asyncio.sleep(0.1)
    result = await fetch_data()
    assert result == "expected_value"

async def fetch_data():
    await asyncio.sleep(0.01)
    return "expected_value"
```

**Source:** [pytest-asyncio documentation](https://github.com/pytest-dev/pytest-asyncio)

### Async Fixtures

```python
import pytest
import pytest_asyncio

@pytest_asyncio.fixture
async def database_connection():
    # Setup
    conn = await create_connection("postgresql://localhost/test")
    await conn.execute("CREATE TABLE IF NOT EXISTS test_table (id INT)")

    yield conn

    # Teardown
    await conn.execute("DROP TABLE test_table")
    await conn.close()

@pytest.mark.asyncio
async def test_with_async_fixture(database_connection):
    result = await database_connection.execute("SELECT 1")
    assert result == 1
```

**Source:** [pytest-asyncio fixtures](https://github.com/pytest-dev/pytest-asyncio)

### Parametrized Async Tests

```python
import pytest

@pytest.mark.asyncio
@pytest.mark.parametrize("value,expected", [
    (1, 2),
    (3, 6),
    (5, 10),
])
async def test_parametrized(value, expected):
    result = await compute(value)
    assert result == expected

async def compute(x):
    await asyncio.sleep(0.01)
    return x * 2
```

**Source:** [pytest-asyncio parametrization](https://github.com/pytest-dev/pytest-asyncio)

### Testing with TaskGroup

```python
import asyncio
import pytest

@pytest.mark.asyncio
async def test_task_group():
    results = []

    async def worker(n):
        await asyncio.sleep(0.1)
        results.append(n)

    async with asyncio.TaskGroup() as tg:
        tg.create_task(worker(1))
        tg.create_task(worker(2))
        tg.create_task(worker(3))

    assert sorted(results) == [1, 2, 3]
```

### Mocking Async Functions

```python
import pytest
from unittest.mock import AsyncMock, patch

@pytest.mark.asyncio
async def test_with_mock():
    async def fetch_data():
        # This would normally do network call
        pass

    with patch('mymodule.fetch_data', new_callable=AsyncMock) as mock_fetch:
        mock_fetch.return_value = "mocked_data"

        result = await fetch_data()
        assert result == "mocked_data"
        mock_fetch.assert_called_once()
```

**Source:** [AsyncMock documentation](https://docs.python.org/3/library/unittest.mock.html#unittest.mock.AsyncMock)

## Performance Considerations

### Event Loop Overhead

Async code has overhead from task scheduling and context switching:

```python
# For very short operations, async may be slower
async def tiny_operation():
    return 1 + 1  # Too simple for async benefit

# Async shines with I/O waits
async def io_operation():
    await asyncio.sleep(0.1)  # Yields to other tasks
    return "done"
```

### When Async is Slower

- **Low concurrency:** Single or few concurrent operations
- **CPU-bound code:** No I/O waiting, just computation
- **Very simple operations:** Overhead exceeds benefit
- **Overhead dominates:** Creating tasks costs more than the work

### Optimal Use Cases

- **High concurrency:** Thousands of simultaneous I/O operations
- **I/O-bound workloads:** Network requests, database queries, file operations
- **Event-driven systems:** Web servers, chat applications, real-time data
- **Microservices:** Service-to-service communication

### Profiling Async Code

```python
import asyncio
import time

async def profile_example():
    start = time.perf_counter()

    tasks = [asyncio.create_task(io_operation()) for _ in range(100)]
    await asyncio.gather(*tasks)

    elapsed = time.perf_counter() - start
    print(f"Completed 100 operations in {elapsed:.2f}s")

async def io_operation():
    await asyncio.sleep(0.1)
    return "done"

asyncio.run(profile_example())
```

**Use cProfile for detailed profiling:**

```bash
python -m cProfile -s cumtime async_script.py
```

**Source:** [Performance considerations](https://docs.python.org/3/library/asyncio-dev.html)

## Summary

**Key Takeaways:**

1. Use `async def` to define coroutines, `await` to call them
2. `asyncio.run()` is the entry point for async programs
3. **Python 3.11+:** Prefer `TaskGroup` for structured concurrency
4. Use `gather()` when you need to collect results from multiple coroutines
5. Use `create_task()` for fire-and-forget background tasks (with proper references)
6. Always use async libraries (`aiohttp`, `aiofiles`, `asyncpg`) for I/O operations
7. Never block the event loop with sync operations - use `to_thread()` or `run_in_executor()`
8. Async is for I/O-bound code, not CPU-bound code
9. Test with `pytest-asyncio` and `@pytest.mark.asyncio`
10. Profile to ensure async actually improves performance

## Official Documentation Links

- [asyncio - Asynchronous I/O](https://docs.python.org/3/library/asyncio.html)
- [Coroutines and Tasks](https://docs.python.org/3/library/asyncio-task.html)
- [Synchronization Primitives](https://docs.python.org/3/library/asyncio-sync.html)
- [Queues](https://docs.python.org/3/library/asyncio-queue.html)
- [Developing with asyncio](https://docs.python.org/3/library/asyncio-dev.html)

## Last Verified

**Date:** 2025-11-17

**Python Version:** 3.11+ (TaskGroup features require 3.11+, most features work on 3.7+)

**Sources:**

- Python Official Documentation (docs.python.org)
- aiohttp (aio-libs/aiohttp)
- aiofiles (tinche/aiofiles)
- pytest-asyncio (pytest-dev/pytest-asyncio)
- asyncpg (magicstack/asyncpg)
- Perplexity Research (2024 best practices)
