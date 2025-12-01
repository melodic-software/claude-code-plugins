# Engineering Best Practices

Generic software engineering principles for building robust, scalable systems. Load when designing systems, implementing features, or reviewing code for production readiness.

## Concurrency

When designing concurrent operations, choose appropriate locking strategies:

- **Optimistic locking** (version numbers, timestamps, compare-and-swap): For low-contention scenarios where conflicts are rare - allows higher throughput and better scalability
- **Pessimistic locking** (mutexes, database locks): For high-contention scenarios where conflicts are likely - prevents wasted work but reduces parallelism
- Consider idempotency for retry-safe operations
- Prefer immutable data structures where possible
- Use appropriate synchronization primitives (locks, semaphores, channels, async/await) based on the concurrency model
- Document concurrency assumptions and thread-safety guarantees clearly

## Caching Strategy

Identify valid caching opportunities during planning, auditing, and review phases:

**What to cache:**

- Expensive computations (API calls, database queries, file I/O, complex calculations)
- Frequently accessed read-only data (configuration, reference data, compiled templates)
- Derived/aggregated data (statistics, search indexes)

**Cache design considerations:**

- Cache invalidation strategy (TTL, event-driven, manual)
- Cache consistency requirements (strong vs eventual)
- Cache levels (in-memory, distributed, CDN) based on access patterns
- Document cache keys, TTLs, and invalidation logic
- Monitor cache hit rates and adjust strategies based on metrics

**What NOT to cache:**

- Sensitive data
- Frequently changing data
- Data where staleness causes correctness issues

## Error Handling and Resilience

Design for failure - assume external dependencies will fail:

- Use retry with exponential backoff for transient failures
- Implement circuit breakers to prevent cascading failures
- Provide graceful degradation when services are unavailable
- Log errors with sufficient context for debugging but avoid exposing sensitive data
- Use structured error types and avoid generic exceptions
- Return actionable error messages to users
- Consider idempotency for operations that may be retried
- Handle partial failures gracefully (e.g., batch operations)

## Idempotency

Design operations to be idempotent when possible - repeated calls with the same input produce the same result:

- Use idempotency keys for external API calls
- Implement idempotency checks for state-changing operations
- Document which operations are idempotent and which are not
- This enables safe retries and prevents duplicate side effects

## Observability

Include logging, metrics, and tracing in designs:

- Log at appropriate levels (debug, info, warn, error) with structured data
- Emit metrics for business and technical KPIs (latency, throughput, error rates)
- Use distributed tracing for request flows across services
- Make observability data queryable and actionable
- Avoid logging sensitive information
- Use correlation IDs to track requests across systems

## Resource Management

Properly manage resources (connections, file handles, memory):

- Use connection pooling for databases and external services
- Implement timeouts for all external calls
- Clean up resources in finally blocks or using context managers/RAII
- Monitor resource usage and set appropriate limits
- Prefer lazy initialization for expensive resources that may not be used

## API Design

Design APIs with longevity in mind:

- Use semantic versioning for breaking changes
- Provide backward compatibility when possible
- Include rate limiting and authentication
- Document request/response schemas
- Use appropriate HTTP methods and status codes
- Consider pagination for list endpoints
- Provide clear error responses with actionable messages

## Data Consistency

Understand consistency requirements:

- Use transactions for operations requiring ACID guarantees
- Consider eventual consistency for distributed systems where strong consistency is costly
- Document consistency guarantees and trade-offs
- Use appropriate isolation levels in databases
- Handle race conditions explicitly

## Performance Optimization

Profile before optimizing - measure actual bottlenecks:

- Optimize for the common case, not edge cases
- Consider algorithmic complexity (Big O) before micro-optimizations
- Use appropriate data structures for access patterns
- Cache expensive operations
- Batch operations when possible
- Use async/parallel processing where beneficial
- Monitor and measure improvements

---

**Keywords:** concurrency, caching, error handling, resilience, idempotency, observability, logging, metrics, tracing, resource management, API design, data consistency, performance optimization, locking, circuit breaker, retry, backoff

**Last Updated:** 2025-11-30
