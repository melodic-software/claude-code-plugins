# Database Checks

Database-specific code review checks for SQL files, migrations, ORMs, and database-related code.

**Loaded for:** .sql files, migrations/* directories, database configuration files, ORM model files

## 1. Query Optimization

- [ ] **Use SELECT with explicit columns** - Never use SELECT * in production code; specify exact columns needed
- [ ] **Limit result sets appropriately** - Use LIMIT/TOP clauses to prevent excessive data retrieval
- [ ] **Use WHERE clauses efficiently** - Filter data early in query execution; use indexed columns in WHERE
- [ ] **Avoid functions on indexed columns** - Don't wrap indexed columns in functions (e.g., WHERE YEAR(date) = 2025)
- [ ] **Use JOIN instead of subqueries** - JOINs are typically more performant than correlated subqueries
- [ ] **Minimize DISTINCT usage** - DISTINCT is expensive; consider if query logic can eliminate duplicates
- [ ] **Use EXISTS instead of COUNT** - When checking existence, EXISTS stops at first match vs COUNT scanning all
- [ ] **Avoid OR in WHERE clauses** - Use UNION or IN instead; OR prevents index usage
- [ ] **Use UNION ALL instead of UNION** - UNION ALL is faster when duplicates are acceptable

## 2. Index Design

- [ ] **Index foreign keys** - All foreign key columns should have indexes for join performance
- [ ] **Index WHERE clause columns** - Columns frequently used in WHERE/JOIN should be indexed
- [ ] **Consider composite indexes** - Multi-column indexes for queries filtering multiple columns
- [ ] **Index column order matters** - Most selective columns first in composite indexes
- [ ] **Avoid over-indexing** - Too many indexes slow INSERT/UPDATE/DELETE operations
- [ ] **Use covering indexes** - Include all columns needed by query to avoid table lookups
- [ ] **Consider partial indexes** - Index subset of rows for frequently filtered data
- [ ] **Monitor index usage** - Remove unused indexes; they have maintenance cost

## 3. N+1 Query Prevention

- [ ] **Use eager loading** - Load related data in single query, not loop of queries
- [ ] **Batch fetching** - Use IN clauses to fetch multiple records at once
- [ ] **Use JOINs for related data** - Fetch parent and child data in single query
- [ ] **Implement data loaders** - Use patterns like DataLoader (GraphQL) to batch requests
- [ ] **Monitor ORM query patterns** - ORMs can generate N+1 queries; review generated SQL
- [ ] **Use query profiling** - Detect N+1 patterns in development/staging

## 4. Transaction Handling

- [ ] **Use transactions for multi-step operations** - Ensure atomic operations with BEGIN/COMMIT/ROLLBACK
- [ ] **Keep transactions short** - Long transactions block other operations and increase deadlock risk
- [ ] **Use appropriate isolation levels** - Read Committed, Repeatable Read, Serializable based on needs
- [ ] **Handle rollback correctly** - Always rollback on error; use try/catch/finally or equivalent
- [ ] **Avoid user interaction in transactions** - Never wait for user input inside transaction
- [ ] **Use savepoints for nested operations** - Allow partial rollback within transaction
- [ ] **Consider optimistic locking** - Use version columns for concurrent update detection

## 5. Connection Pooling

- [ ] **Use connection pooling** - Never create new connection per request; reuse pool
- [ ] **Configure pool size appropriately** - Balance between concurrency and resource usage
- [ ] **Set connection timeouts** - Prevent indefinite waiting for connections
- [ ] **Close connections properly** - Return connections to pool; use try/finally or using/with
- [ ] **Monitor pool health** - Track active/idle connections, wait times, errors
- [ ] **Handle connection failures** - Implement retry logic and circuit breakers

## 6. Migration Safety

- [ ] **Make migrations reversible** - Include UP and DOWN migrations; test rollback
- [ ] **Avoid data loss** - Never DROP columns/tables without explicit confirmation
- [ ] **Use backward-compatible changes** - Add nullable columns, then backfill, then add NOT NULL
- [ ] **Test migrations on production-like data** - Verify performance with realistic data volumes
- [ ] **Lock awareness** - Understand which operations acquire table locks (ALTER TABLE)
- [ ] **Use online schema changes** - For large tables, use tools supporting zero-downtime migrations
- [ ] **Version migrations sequentially** - Use timestamps or sequential IDs; avoid conflicts
- [ ] **Document breaking changes** - Clearly note migrations requiring application code changes

## 7. Schema Design

- [ ] **Normalize appropriately** - Eliminate redundancy; use 3NF for transactional data
- [ ] **Denormalize strategically** - For read-heavy workloads, controlled denormalization acceptable
- [ ] **Use appropriate data types** - Choose smallest type that fits; INT vs BIGINT, CHAR vs VARCHAR
- [ ] **Define NOT NULL where appropriate** - Avoid NULL when values should always exist
- [ ] **Use ENUM/CHECK constraints** - Enforce valid values at database level
- [ ] **Separate hot and cold data** - Archive old data; partition tables by date
- [ ] **Design for sharding** - Include shard key if horizontal scaling planned

## 8. Data Integrity Constraints

- [ ] **Define primary keys** - Every table should have primary key
- [ ] **Use foreign key constraints** - Enforce referential integrity at database level
- [ ] **Add unique constraints** - Prevent duplicate data (email, username, etc.)
- [ ] **Use CHECK constraints** - Validate data ranges, formats at database level
- [ ] **Consider triggers cautiously** - Use for audit trails, but beware performance impact
- [ ] **Default values for columns** - Provide sensible defaults where applicable
- [ ] **ON DELETE/UPDATE actions** - Define CASCADE, SET NULL, RESTRICT appropriately

## 9. Stored Procedures and Functions

- [ ] **Keep logic simple** - Complex business logic belongs in application layer
- [ ] **Use parameterized inputs** - Prevent SQL injection; enable query plan caching
- [ ] **Return consistent result sets** - Same columns/types from all execution paths
- [ ] **Handle errors explicitly** - Use TRY/CATCH (SQL Server), EXCEPTION blocks (PostgreSQL)
- [ ] **Avoid cursors** - Set-based operations are faster than row-by-row processing
- [ ] **Document input/output contracts** - Clear comments on parameters and return values

## 10. Views and Materialized Views

- [ ] **Use views for data abstraction** - Hide schema complexity from applications
- [ ] **Avoid nested views** - Multiple view layers degrade performance
- [ ] **Consider materialized views for aggregations** - Pre-compute expensive calculations
- [ ] **Refresh materialized views appropriately** - Schedule or trigger-based refresh strategy
- [ ] **Index materialized views** - They are tables; benefit from indexes like any table

## 11. Security

- [ ] **Prevent SQL injection** - Use parameterized queries/prepared statements ALWAYS
- [ ] **Apply least privilege** - Database users should have minimum necessary permissions
- [ ] **Encrypt sensitive data** - Use encryption for PII, passwords, financial data
- [ ] **Audit sensitive operations** - Log access to critical tables (users, payments, etc.)
- [ ] **Use row-level security** - Restrict data access based on user context (PostgreSQL RLS, etc.)
- [ ] **Avoid dynamic SQL** - Parameterized queries are safer; if dynamic SQL needed, validate inputs

## 12. Performance Monitoring

- [ ] **Log slow queries** - Enable slow query log; review regularly
- [ ] **Use EXPLAIN/EXPLAIN ANALYZE** - Understand query execution plans
- [ ] **Monitor query patterns** - Identify most frequent/expensive queries
- [ ] **Track table bloat** - VACUUM (PostgreSQL), rebuild indexes (SQL Server)
- [ ] **Monitor lock contention** - Detect and resolve blocking queries
- [ ] **Review execution statistics** - Use database-specific tools (pg_stat_statements, sys.dm_exec_query_stats)

## 13. Deadlock Prevention

- [ ] **Access tables in consistent order** - Always acquire locks in same sequence
- [ ] **Keep transactions short** - Less time holding locks reduces collision probability
- [ ] **Use appropriate isolation levels** - Lower isolation reduces locking
- [ ] **Handle deadlocks gracefully** - Implement retry logic for deadlock errors
- [ ] **Use row-level locking** - More granular than table/page locks

## 14. Backup and Recovery

- [ ] **Regular backup schedule** - Daily full backups, transaction log backups
- [ ] **Test restore procedures** - Verify backups are recoverable
- [ ] **Document recovery time objectives** - Know RTO/RPO requirements
- [ ] **Use point-in-time recovery** - Transaction log backups enable PITR
- [ ] **Offsite backup storage** - Protect against site-wide failures

## Related Checks

- See performance-checks.md for general performance patterns
- See security-checks.md for broader security concerns
- See api-checks.md for API endpoint database interaction patterns
