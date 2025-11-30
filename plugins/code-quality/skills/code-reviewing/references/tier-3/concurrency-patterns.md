# Concurrency Patterns

Deep-dive code review checks for concurrent and parallel code. Auto-loaded when patterns like `async*`, `await*`, `thread*`, `lock*`, `mutex*`, `semaphore*`, `concurrent*`, `parallel*`, `atomic*`, `synchronized*`, `Task*`, `Promise*`, `Future*` are detected.

## Thread Safety Patterns

- [ ] **Immutability first** - Prefer immutable data structures that eliminate shared mutable state
- [ ] **Thread confinement** - Data owned by single thread (thread-local storage, actor model)
- [ ] **Synchronization primitives** - Use appropriate locks/mutexes when sharing required
- [ ] **Stateless design** - Prefer stateless components that can safely run concurrently
- [ ] **Copy-on-write** - Use COW patterns for read-heavy, write-light scenarios
- [ ] **Thread-safe collections** - Use concurrent collections instead of manual synchronization

## Lock Types and Selection

- [ ] **Mutex/Monitor** - Exclusive access, use for critical sections with writes
- [ ] **Reader-writer locks** - Multiple readers OR single writer, use when reads dominate
- [ ] **Semaphore** - Limit concurrent access to N threads, use for resource pooling
- [ ] **Spinlock** - Busy-wait lock, use only for very short critical sections
- [ ] **Recursive locks** - Allow same thread to acquire multiple times, avoid when possible
- [ ] **Lock-free structures** - Use atomic operations, best for high-contention scenarios

## Deadlock Prevention

- [ ] **Lock ordering** - Acquire locks in consistent global order across all threads
- [ ] **Timeout on acquire** - Use try-lock with timeout, never indefinite blocking
- [ ] **Avoid nested locks** - Minimize holding multiple locks simultaneously
- [ ] **Lock hierarchies** - Define and enforce lock levels (low to high acquisition)
- [ ] **Deadlock detection** - Monitor for cycles in lock wait graphs
- [ ] **Single lock strategy** - Prefer one coarse lock over multiple fine-grained locks when complexity outweighs performance

## Race Condition Detection

- [ ] **Check-then-act** - Atomicize compound operations (check + act must be atomic)
- [ ] **Read-modify-write** - Use atomic operations or locks for updates
- [ ] **Double-checked locking** - Avoid unless using proper memory barriers
- [ ] **Lazy initialization** - Use thread-safe patterns (lock, atomic flag, language-specific)
- [ ] **Publication safety** - Ensure fully-constructed objects before sharing
- [ ] **Happens-before relationships** - Verify memory visibility guarantees

## Async/Await Patterns by Language

### JavaScript/TypeScript

- [ ] **Avoid blocking** - Never use synchronous I/O in async functions
- [ ] **Promise handling** - Always handle rejections (catch or propagate)
- [ ] **Parallel vs sequential** - Use `Promise.all()` for independent operations
- [ ] **Cancellation** - Use AbortController for cancellable async operations

### C#/.NET

- [ ] **ConfigureAwait** - Use `ConfigureAwait(false)` in library code to avoid context capture
- [ ] **Task vs ValueTask** - Use `ValueTask<T>` for hot paths with synchronous completion
- [ ] **Async all the way** - Don't mix async and sync (no `.Result` or `.Wait()`)
- [ ] **Cancellation tokens** - Support cancellation via `CancellationToken` parameters

### Python

- [ ] **asyncio event loop** - Don't block event loop with CPU-bound or sync I/O
- [ ] **Task groups** - Use `asyncio.gather()` or `TaskGroup` for concurrent tasks
- [ ] **Sync in async** - Use `loop.run_in_executor()` for blocking calls
- [ ] **Async context managers** - Use `async with` for resource cleanup

### Rust

- [ ] **Send + Sync traits** - Verify types are thread-safe before sharing
- [ ] **Future polling** - Ensure futures make progress, avoid blocking executors
- [ ] **Tokio vs async-std** - Use runtime-appropriate patterns

## Thread Pool Management

- [ ] **Right pool size** - CPU-bound: core count, I/O-bound: higher (measure)
- [ ] **Queue bounds** - Limit work queue to prevent memory exhaustion
- [ ] **Task granularity** - Tasks should be neither too small (overhead) nor too large (starvation)
- [ ] **Thread lifecycle** - Reuse threads, avoid creating/destroying frequently
- [ ] **Work stealing** - Use work-stealing pools for load balancing
- [ ] **Graceful shutdown** - Drain queue and join threads on shutdown

## Concurrent Collections

- [ ] **Right collection** - Use concurrent queue, map, set as appropriate
- [ ] **Weak consistency** - Understand iterators may not reflect concurrent modifications
- [ ] **CAS operations** - Use compare-and-swap for atomic updates
- [ ] **Bulk operations** - Prefer bulk ops over loops with individual ops
- [ ] **Lock striping** - Verify collections use striping for scalability

## Atomic Operations and Memory Ordering

- [ ] **Atomic types** - Use `AtomicInteger`, `std::atomic`, `Atomic*` primitives
- [ ] **Memory ordering** - Choose weakest ordering that maintains correctness (relaxed, acquire, release, seq_cst)
- [ ] **ABA problem** - Use versioning/tags when necessary
- [ ] **Compare-and-swap loops** - Verify retry logic for failed CAS
- [ ] **Volatile/atomic reads** - Ensure visibility without full locks

## Producer-Consumer Patterns

- [ ] **Bounded queue** - Use bounded buffer to prevent producer overwhelming consumer
- [ ] **Backpressure** - Handle slow consumer (block producer, drop, buffer)
- [ ] **Multiple consumers** - Ensure fair distribution and no starvation
- [ ] **Poison pill** - Use sentinel values for graceful shutdown
- [ ] **Batch processing** - Reduce lock contention with batching

## Advanced Lock-Free Techniques

- [ ] **Lock-free algorithms** - Verify progress guarantees (wait-free > lock-free > obstruction-free)
- [ ] **ABA mitigation** - Use tagged pointers or hazard pointers
- [ ] **Memory reclamation** - Use epoch-based reclamation or hazard pointers for safe memory reuse
- [ ] **Linearizability** - Verify operations appear atomic at some point between invocation and response

## Testing Concurrent Code

- [ ] **Stress tests** - Run with many threads, high load, long duration
- [ ] **Thread sanitizers** - Use TSan, Helgrind, or similar tools
- [ ] **Controlled scheduling** - Use tools like Coyote, Loom for deterministic replay
- [ ] **Property-based testing** - Verify invariants under random concurrent operations
- [ ] **Race detectors** - Enable runtime race detection in tests
- [ ] **Timeouts in tests** - Detect deadlocks with reasonable timeouts

## Common Anti-Patterns

- [ ] **Avoid busy-waiting** - Don't spin in loops checking conditions, use proper synchronization
- [ ] **No sleep for sync** - Never use `sleep()` as synchronization mechanism
- [ ] **Lock everything** - Don't use overly coarse locks harming performance
- [ ] **Async over sync** - Don't wrap sync code in async without threading benefit
- [ ] **Shared mutable state** - Minimize shared mutable state, prefer message passing or immutability

## Platform-Specific Considerations

- [ ] **JVM** - Verify proper use of `volatile`, `synchronized`, `java.util.concurrent`
- [ ] **CLR** - Check `lock`, `Interlocked`, `volatile` usage, memory model awareness
- [ ] **C/C++** - Verify memory ordering, avoid data races (undefined behavior)
- [ ] **Go** - Use channels and goroutines idiomatically, avoid shared memory when possible
- [ ] **Rust** - Trust but verify `Send`/`Sync`, leverage ownership for safety

---

**Last Updated:** 2025-11-28
