# Backend and API Code Review Checks

## Overview

This Tier 2 reference provides backend/API-specific code review checks for server-side languages (.py, .java, .cs, .go, .rb, .php). These checks supplement the universal checks in the main SKILL.md with backend-focused concerns.

**When to load:** Reviewing backend services, APIs, database access, background jobs, or server-side business logic.

---

## 1. Security (OWASP-Based) - Backend Focus

### 1.1 Authentication and Authorization

- [ ] **Authentication mechanisms** - Use proven libraries (OAuth2, JWT, SAML) instead of custom auth
- [ ] **Password handling** - Never store plaintext passwords; use bcrypt, Argon2, or PBKDF2 with proper work factors
- [ ] **Session management** - Secure session tokens, proper expiration, rotation on privilege escalation
- [ ] **Authorization checks** - Verify permissions at every endpoint/method, not just UI layer
- [ ] **Privilege escalation** - Prevent horizontal/vertical privilege escalation through proper checks
- [ ] **Token validation** - Validate all tokens (JWT, API keys, session tokens) on every request
- [ ] **Multi-factor authentication** - Support MFA where appropriate, especially for privileged operations

### 1.2 Input Validation and Sanitization

- [ ] **All inputs validated** - Validate type, length, format, range for every input (query params, body, headers)
- [ ] **Allowlist approach** - Use allowlists (known-good) rather than denylists (known-bad)
- [ ] **SQL injection prevention** - Use parameterized queries/ORMs, never string concatenation
- [ ] **Command injection prevention** - Avoid executing shell commands; if necessary, sanitize thoroughly
- [ ] **Path traversal prevention** - Validate file paths, prevent `../` attacks
- [ ] **XML/JSON injection** - Use safe parsers, validate structure, disable dangerous features (XXE)
- [ ] **Size limits** - Enforce request size limits to prevent DoS
- [ ] **Content-Type validation** - Verify Content-Type headers match actual content

### 1.3 Data Protection

- [ ] **Sensitive data encryption** - Encrypt PII, credentials, payment data at rest and in transit
- [ ] **TLS/HTTPS enforcement** - All external APIs use HTTPS, proper certificate validation
- [ ] **Secrets management** - Use secret vaults (AWS Secrets Manager, Azure Key Vault, HashiCorp Vault), not config files
- [ ] **No secrets in logs** - Never log passwords, tokens, API keys, credit cards
- [ ] **Data masking** - Mask sensitive data in logs, error messages, debug output
- [ ] **Secure defaults** - Default to secure configurations, require explicit opt-in for less secure options

### 1.4 Error Handling and Information Disclosure

- [ ] **Generic error messages** - Don't expose stack traces, SQL errors, internal paths to clients
- [ ] **Detailed logging internally** - Log full details for debugging, but sanitize external messages
- [ ] **HTTP status codes** - Use appropriate codes (400 vs 404 vs 500) without leaking existence of resources
- [ ] **Rate limit disclosure** - Don't reveal exact rate limits in error messages

---

## 2. Concurrency and Thread Safety - Backend Focus

### 2.1 Locking and Synchronization

- [ ] **Lock granularity** - Use fine-grained locks to minimize contention
- [ ] **Lock ordering** - Document and enforce consistent lock acquisition order to prevent deadlocks
- [ ] **Minimize critical sections** - Keep locked regions as small as possible
- [ ] **Async-safe operations** - Ensure async/await patterns don't introduce race conditions
- [ ] **Database transactions** - Use appropriate isolation levels, handle deadlocks with retries
- [ ] **Distributed locks** - Use Redis, ZooKeeper, or similar for distributed system coordination

### 2.2 Shared State Management

- [ ] **Immutability preferred** - Use immutable data structures where possible
- [ ] **Thread-safe collections** - Use concurrent collections (ConcurrentHashMap, ConcurrentQueue, etc.)
- [ ] **Atomic operations** - Use atomic primitives for simple shared counters/flags
- [ ] **Race condition analysis** - Check for TOCTOU (Time-of-Check-Time-of-Use) bugs
- [ ] **Cache coherence** - Ensure distributed caches remain consistent

### 2.3 Background Processing

- [ ] **Job idempotency** - Background jobs must be idempotent (safe to retry)
- [ ] **Job failures** - Handle failures gracefully with retries and dead-letter queues
- [ ] **Resource cleanup** - Close connections, release locks, clean up resources in finally blocks
- [ ] **Graceful shutdown** - Handle SIGTERM/SIGINT to finish in-flight work before exiting

---

## 3. Database Access Patterns

### 3.1 Query Efficiency

- [ ] **N+1 query prevention** - Avoid loading related entities in loops; use joins or eager loading
- [ ] **Pagination** - Implement cursor-based or offset-based pagination for large result sets
- [ ] **Index usage** - Ensure queries use appropriate indexes (review query plans)
- [ ] **Projection** - Select only needed columns, not `SELECT *`
- [ ] **Connection pooling** - Use connection pools with appropriate sizing

### 3.2 Transaction Management

- [ ] **Transaction boundaries** - Keep transactions as short as possible
- [ ] **Rollback handling** - Ensure rollback on errors, release resources in finally blocks
- [ ] **Isolation levels** - Use appropriate isolation (READ COMMITTED, REPEATABLE READ, etc.)
- [ ] **Optimistic locking** - Use version fields or ETags to detect concurrent modifications
- [ ] **Distributed transactions** - Avoid if possible; use saga pattern or eventual consistency instead

### 3.3 ORM and Data Access

- [ ] **ORM efficiency** - Understand generated queries; avoid lazy loading traps
- [ ] **Batch operations** - Use bulk insert/update for multiple records
- [ ] **Raw SQL safety** - If using raw SQL, still use parameterized queries
- [ ] **Migration safety** - Database migrations are reversible and tested

---

## 4. Caching Strategies

- [ ] **Cache invalidation** - Clear cache on updates; use TTLs to prevent stale data
- [ ] **Cache keys** - Use unique, deterministic keys that include version/tenant information
- [ ] **Cache-aside pattern** - Implement proper cache-aside (lazy loading) with race condition handling
- [ ] **Distributed cache consistency** - Handle cache coherence across multiple servers
- [ ] **Cache stampede prevention** - Use locking or probabilistic early expiration to prevent thundering herd
- [ ] **Cache warmup** - Warm critical caches on deployment/restart

---

## 5. Rate Limiting and Throttling

- [ ] **Rate limit implementation** - Use token bucket, sliding window, or fixed window algorithms
- [ ] **Per-user limits** - Apply rate limits per user/API key, not globally
- [ ] **Graceful degradation** - Return 429 status with Retry-After header
- [ ] **Distributed rate limiting** - Use Redis or similar for distributed rate limit tracking
- [ ] **Bypass for internal services** - Allow trusted services to bypass rate limits

---

## 6. Logging and Monitoring

### 6.1 Logging Best Practices

- [ ] **Structured logging** - Use JSON or structured format for machine parsing
- [ ] **Log levels** - Use appropriate levels (DEBUG, INFO, WARN, ERROR, FATAL)
- [ ] **Correlation IDs** - Include request/correlation IDs to trace requests across services
- [ ] **Performance metrics** - Log response times, database query times, external API latency
- [ ] **Business events** - Log significant business events (orders placed, payments processed)
- [ ] **No sensitive data** - Never log passwords, tokens, credit cards, PII without masking

### 6.2 Observability

- [ ] **Metrics collection** - Expose metrics (requests/sec, error rate, latency percentiles)
- [ ] **Health checks** - Implement /health and /ready endpoints for load balancers
- [ ] **Distributed tracing** - Use OpenTelemetry, Jaeger, or similar for tracing across services
- [ ] **Alerting** - Define alerts for error spikes, latency increases, resource exhaustion

---

## 7. Error Handling and Retries

### 7.1 Error Handling Patterns

- [ ] **Exception hierarchy** - Use specific exception types, not generic Exception
- [ ] **Error recovery** - Attempt recovery before failing; use circuit breakers for external dependencies
- [ ] **Error context** - Include relevant context in exceptions (request ID, user ID, operation)
- [ ] **Global error handlers** - Implement top-level handlers for uncaught exceptions
- [ ] **Validation errors** - Return 400 with clear field-level validation messages

### 7.2 Retry Logic

- [ ] **Idempotent operations** - Only retry operations that are idempotent
- [ ] **Exponential backoff** - Use exponential backoff with jitter for retries
- [ ] **Retry limits** - Set maximum retry attempts to prevent infinite loops
- [ ] **Circuit breaker** - Use circuit breaker pattern for external service calls
- [ ] **Timeout configuration** - Set appropriate timeouts for all external calls

---

## 8. API Design

### 8.1 RESTful Principles

- [ ] **HTTP verbs** - Use correct verbs (GET, POST, PUT, PATCH, DELETE)
- [ ] **Resource naming** - Use nouns for resources, plural forms (/users, not /getUsers)
- [ ] **Statelessness** - Each request contains all needed information; no server-side session dependency
- [ ] **HATEOAS** - Include hypermedia links where appropriate for discoverability

### 8.2 API Versioning

- [ ] **Version strategy** - Use URL versioning (/v1/), header versioning, or content negotiation
- [ ] **Backward compatibility** - Maintain backward compatibility within major versions
- [ ] **Deprecation notices** - Provide advance notice and sunset dates for deprecated endpoints

### 8.3 Request/Response Design

- [ ] **Consistent structure** - Use consistent JSON structure across all endpoints
- [ ] **Pagination** - Support pagination with links (next, prev) and metadata (total, page size)
- [ ] **Filtering and sorting** - Support query parameters for filtering, sorting, field selection
- [ ] **Compression** - Support gzip/brotli compression for large responses
- [ ] **Content negotiation** - Support multiple formats (JSON, XML) via Accept header

### 8.4 Documentation

- [ ] **OpenAPI/Swagger** - Provide OpenAPI spec for all endpoints
- [ ] **Example requests** - Include example requests and responses in documentation
- [ ] **Error codes** - Document all possible error codes and their meanings

---

## 9. Background Job Processing

- [ ] **Job queues** - Use reliable queue systems (RabbitMQ, AWS SQS, Redis Queue)
- [ ] **Idempotency** - Jobs must be idempotent (safe to execute multiple times)
- [ ] **Error handling** - Failed jobs go to dead-letter queue after max retries
- [ ] **Job monitoring** - Monitor queue depth, processing time, failure rates
- [ ] **Priority queues** - Use priority queues for time-sensitive jobs
- [ ] **Graceful shutdown** - Wait for in-progress jobs to complete on shutdown

---

## 10. Service Communication Patterns

### 10.1 Synchronous Communication

- [ ] **Timeouts** - Set aggressive timeouts for all HTTP/gRPC calls
- [ ] **Circuit breaker** - Implement circuit breaker for external service dependencies
- [ ] **Retry logic** - Use exponential backoff with jitter
- [ ] **Service discovery** - Use service registry (Consul, Eureka) for dynamic discovery

### 10.2 Asynchronous Communication

- [ ] **Message durability** - Use durable queues/topics for critical messages
- [ ] **Message ordering** - Handle out-of-order messages if ordering matters
- [ ] **Event schemas** - Version event schemas; maintain backward compatibility
- [ ] **Dead-letter handling** - Process dead-letter queue messages

---

## 11. Configuration Management

- [ ] **Environment-specific configs** - Separate configs for dev/staging/production
- [ ] **Secrets externalized** - No secrets in code or config files; use secret vaults
- [ ] **Config validation** - Validate configuration on startup, fail fast if invalid
- [ ] **Feature flags** - Use feature flags for gradual rollouts and A/B testing
- [ ] **Hot reload** - Support config hot-reloading where appropriate (without restart)

---

## 12. Testing (Backend-Specific)

### 12.1 Unit Tests

- [ ] **Business logic coverage** - Test all business logic paths with high coverage
- [ ] **Mock external dependencies** - Mock databases, external APIs, file systems
- [ ] **Test edge cases** - Null values, empty collections, boundary conditions
- [ ] **Fast execution** - Unit tests run in milliseconds, no I/O

### 12.2 Integration Tests

- [ ] **Database tests** - Test against real database (in-memory or containerized)
- [ ] **API contract tests** - Verify API contracts with external services
- [ ] **End-to-end flows** - Test complete user workflows
- [ ] **Test data management** - Use factories/fixtures for consistent test data

### 12.3 Performance Tests

- [ ] **Load testing** - Test under expected and peak load
- [ ] **Stress testing** - Identify breaking points and bottlenecks
- [ ] **Database performance** - Test query performance with realistic data volumes
- [ ] **Memory profiling** - Check for memory leaks under sustained load

---

## Quick Reference Checklist

Before approving backend code, verify:

- [ ] All inputs validated and sanitized
- [ ] Authentication/authorization enforced
- [ ] Secrets managed securely (no hardcoding)
- [ ] Database queries optimized (no N+1)
- [ ] Caching implemented with proper invalidation
- [ ] Rate limiting applied
- [ ] Structured logging with correlation IDs
- [ ] Error handling with retries and circuit breakers
- [ ] API design follows REST principles
- [ ] Background jobs are idempotent
- [ ] Tests cover business logic and edge cases

---

**Last Updated:** 2025-11-28
**Token Count:** ~2,400 tokens
