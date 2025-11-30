# API Design Patterns - Code Review Checks

## Activation Pattern

This reference is loaded when code contains API-related patterns:

- Route definitions: `route*`, `router*`, `@app.*`, `@Get*`, `@Post*`, `@Put*`, `@Delete*`, `@Patch*`
- API endpoints: `endpoint*`, `handler*`, `controller*`, `api/*`
- API types: `REST*`, `GraphQL*`, `gRPC*`

## RESTful Design Principles

### Resource Modeling

- [ ] **Noun-based resource names** - Resources use nouns (e.g., `/users`, `/orders`), not verbs (avoid `/getUsers`)
- [ ] **Plural resource names** - Collections use plural forms (`/users/123`, not `/user/123`)
- [ ] **Resource hierarchy** - Nested resources reflect relationships (`/users/123/orders`, not `/userOrders?userId=123`)
- [ ] **Avoid deep nesting** - Limit nesting to 2-3 levels maximum (e.g., `/users/123/orders/456` is okay, deeper nesting suggests poor design)
- [ ] **Resource identifiers** - Use path parameters for resource IDs, query parameters for filtering

### HTTP Method Usage

- [ ] **GET for retrieval** - GET requests are idempotent, cacheable, and have no side effects
- [ ] **POST for creation** - POST creates new resources, returns 201 Created with Location header
- [ ] **PUT for full replacement** - PUT replaces entire resource, is idempotent
- [ ] **PATCH for partial updates** - PATCH modifies specific fields, prefer JSON Patch or JSON Merge Patch
- [ ] **DELETE for removal** - DELETE removes resources, is idempotent
- [ ] **Safe methods** - GET and HEAD are safe (no side effects)
- [ ] **Idempotent methods** - GET, PUT, DELETE, HEAD, OPTIONS are idempotent (multiple identical requests have same effect)

### Status Code Usage

- [ ] **2xx for success** - 200 OK, 201 Created, 202 Accepted, 204 No Content used appropriately
- [ ] **3xx for redirection** - 301 Moved Permanently, 302 Found, 304 Not Modified used correctly
- [ ] **4xx for client errors** - 400 Bad Request, 401 Unauthorized, 403 Forbidden, 404 Not Found, 409 Conflict, 422 Unprocessable Entity
- [ ] **5xx for server errors** - 500 Internal Server Error, 502 Bad Gateway, 503 Service Unavailable, 504 Gateway Timeout
- [ ] **Specific over generic** - Use specific status codes (e.g., 409 Conflict for duplicate) rather than generic 400

## GraphQL Best Practices

### Schema Design

- [ ] **Nullable by default** - Fields are nullable unless explicitly non-null (avoid breaking changes)
- [ ] **Descriptive type names** - Types and fields have clear, business-domain names
- [ ] **Separation of concerns** - Queries for reads, mutations for writes, subscriptions for real-time
- [ ] **Input types** - Use input types for mutation arguments (not inline object types)
- [ ] **Connection pattern** - Use edges/nodes pattern for pagination (Relay-style connections)

### Query Design

- [ ] **Avoid N+1 queries** - Use DataLoader or similar batching/caching mechanisms
- [ ] **Depth limiting** - Limit query depth to prevent malicious deeply-nested queries
- [ ] **Cost analysis** - Implement query cost analysis to prevent expensive queries
- [ ] **Field-level permissions** - Enforce authorization at field level, not just query level

## API Versioning Strategies

- [ ] **Version strategy chosen** - URI versioning (`/v1/users`), header versioning (`Accept: application/vnd.api+json;version=1`), or query parameter versioning
- [ ] **Consistent versioning** - All endpoints follow same versioning strategy
- [ ] **Version negotiation** - Default version specified when client doesn't request one
- [ ] **Version deprecation** - Deprecated versions clearly marked with sunset dates

## Request/Response Design

### Request Design

- [ ] **Accept headers** - Support content negotiation via Accept header (JSON, XML, etc.)
- [ ] **Request validation** - Validate all inputs at API boundary (types, formats, ranges, required fields)
- [ ] **Content-Type** - Require Content-Type header for POST/PUT/PATCH requests
- [ ] **Request size limits** - Enforce maximum request body size to prevent abuse

### Response Design

- [ ] **Consistent structure** - Responses follow consistent envelope format across all endpoints
- [ ] **Include metadata** - Responses include relevant metadata (timestamps, version, request ID)
- [ ] **Hypermedia controls** - Include links/actions where appropriate (HATEOAS principle)
- [ ] **Compression** - Support gzip/brotli compression for large responses

## Error Handling and Formats

- [ ] **Consistent error format** - All errors follow same structure (e.g., RFC 7807 Problem Details)
- [ ] **Error codes** - Include machine-readable error codes (not just HTTP status)
- [ ] **Error messages** - Provide human-readable messages suitable for display
- [ ] **Field-level errors** - Validation errors specify which fields are invalid
- [ ] **Error details** - Include additional context (request ID, timestamp, documentation link)
- [ ] **No sensitive data** - Error responses don't leak sensitive information (stack traces, internal paths)

## Pagination Patterns

- [ ] **Pagination strategy** - Offset-based (`?page=2&limit=20`), cursor-based, or keyset pagination implemented
- [ ] **Default limits** - Reasonable default page size (e.g., 20-50 items)
- [ ] **Maximum limits** - Enforce maximum page size to prevent abuse
- [ ] **Pagination metadata** - Include total count, page info, next/prev links in responses
- [ ] **Cursor stability** - Cursors remain valid across reasonable time periods

## Filtering and Sorting

- [ ] **Query parameter filtering** - Support filtering via query params (e.g., `?status=active&role=admin`)
- [ ] **Operator support** - Support comparison operators where appropriate (`?created_after=2025-01-01`)
- [ ] **Multiple sort fields** - Allow sorting by multiple fields (`?sort=created_at,-priority`)
- [ ] **Sort direction** - Clear syntax for ascending/descending (e.g., `-` prefix for descending)

## HATEOAS (Hypermedia as the Engine of Application State)

- [ ] **Self links** - Resources include link to themselves (`"_links": {"self": "/users/123"}`)
- [ ] **Related resources** - Include links to related resources and actions
- [ ] **Discoverability** - API root provides links to all top-level resources
- [ ] **State transitions** - Available actions depend on resource state

## Rate Limiting

- [ ] **Rate limit headers** - Return `X-RateLimit-Limit`, `X-RateLimit-Remaining`, `X-RateLimit-Reset` headers
- [ ] **429 status** - Return 429 Too Many Requests when limit exceeded
- [ ] **Retry-After header** - Include Retry-After header in 429 responses
- [ ] **Multiple tiers** - Support different rate limits per authentication tier
- [ ] **Quota visibility** - Clients can query their current quota/usage

## API Documentation

- [ ] **OpenAPI/Swagger** - API documented with OpenAPI 3.x specification
- [ ] **Schema definitions** - All request/response schemas defined
- [ ] **Example values** - Examples provided for all endpoints
- [ ] **Authentication docs** - Authentication/authorization flows documented
- [ ] **Error documentation** - All possible error responses documented
- [ ] **Changelog** - API changes tracked in changelog with version numbers

## Backward Compatibility

- [ ] **Additive changes only** - New fields/endpoints added without breaking existing clients
- [ ] **Optional parameters** - New parameters are optional with sensible defaults
- [ ] **Deprecation warnings** - Deprecated features return deprecation headers (`Sunset`, `Deprecation`)
- [ ] **Version overlap** - Old and new versions supported simultaneously during transition
- [ ] **Field evolution** - Fields can be marked deprecated but not removed immediately

## Deprecation Strategies

- [ ] **Deprecation notice** - Advance notice given (e.g., 6-12 months before removal)
- [ ] **Sunset header** - HTTP Sunset header indicates removal date (RFC 8594)
- [ ] **Documentation updates** - Deprecated features clearly marked in docs
- [ ] **Migration guide** - Guide provided for migrating from old to new version
- [ ] **Monitoring** - Track usage of deprecated features to understand impact

## API Security

- [ ] **Authentication required** - All sensitive endpoints require authentication
- [ ] **Authorization checks** - Verify user has permission for requested resource/action
- [ ] **TLS/HTTPS only** - API only accessible over HTTPS in production
- [ ] **CORS configuration** - CORS headers properly configured (not wildcard `*` in production)
- [ ] **Input sanitization** - All inputs sanitized to prevent injection attacks
- [ ] **CSRF protection** - State-changing operations protected against CSRF
- [ ] **API keys secure** - API keys transmitted in headers (not query strings)
- [ ] **Token expiration** - Authentication tokens have reasonable expiration times

## Performance Optimization

- [ ] **Caching headers** - Appropriate Cache-Control, ETag, Last-Modified headers
- [ ] **Conditional requests** - Support If-None-Match, If-Modified-Since for cache validation
- [ ] **Field selection** - Allow clients to request subset of fields (`?fields=id,name,email`)
- [ ] **Bulk operations** - Support batch requests where appropriate (e.g., bulk create/update)
- [ ] **Async operations** - Long-running operations return 202 Accepted with status endpoint
- [ ] **Response compression** - Enable gzip/brotli compression
- [ ] **Database query optimization** - N+1 queries avoided, proper indexing
- [ ] **CDN integration** - Static/cacheable responses served via CDN where appropriate

## Additional Considerations

- [ ] **Webhook support** - Webhooks implemented for event notifications where appropriate
- [ ] **API monitoring** - Logging, metrics, and tracing enabled for all endpoints
- [ ] **Circuit breakers** - Circuit breakers implemented for external service calls
- [ ] **Graceful degradation** - API continues functioning when non-critical services fail
- [ ] **Health checks** - Health/readiness endpoints available for load balancers/orchestrators

---

**Pattern Category:** API Design and Web Services
**Complexity Level:** Advanced
**Review Priority:** High (APIs are contracts with external consumers)
