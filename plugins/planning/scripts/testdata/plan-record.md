# Plan: Add caching to query handlers

## Brief

### Problem

- Repeated order lookups hit the database on every request.
- Peak latency is twice the target.

### Goal

Cache repeated query results so a repeated lookup skips the database.

- Intent (why, in the user's words): "the order page is slow"
- Vision (where this heads): none stated

### Constraints

- No new runtime dependency.

### Acceptance criteria

- AC1: A repeated lookup within the TTL reads from the cache.
- AC2: The hit rate is logged.
- AC3: The PR body links the issue it closes.

### Out-of-scope

- Cache invalidation across instances.

## Design

Gate: PASS (design handoff).

### Contracts

```text
get(key) -> value?
```

## Plan

Citations checked at: 0123456789abcdef0123456789abcdef01234567

### Behavior

- B1: A repeated order lookup returns without a database read. (AC1)
- B2: Each lookup logs whether it hit the cache. (AC2)

Process criteria: AC3

### Decisions made (gate-passed)

| Decision | What it changes in the plan | Basis (evidence) | Source |
|---|---|---|---|
| D1 In-process cache first | Phase 1 adds a map-backed cache | the handler runs in one process | plan |
| D2 Log through the existing logger | Phase 2 reuses `log.info` | the logger module read this session | plan |

### Phase 1: Cache layer [DONE]

**Satisfies:** AC1
**Delivers:** B1

Add the cache module and read through it in the order handler.

```shape src/orders/handler.py#get_order
get_order
+ cache.get
  db.fetch_order
```

- **Sanity Check:** `pytest tests/test_cache.py` exits 0
- **Sanity Check:** `grep -c "cache.get" src/orders/handler.py` prints 1

### Phase 2: Wire the hit-rate log [TODO]

**Satisfies:** AC2, AC3
**Delivers:** B2

Log each lookup's hit or miss.

```text
## a heading inside a fence stays text
```

**Sanity Check:**

- [ ] `pytest tests/test_log.py` exits 0

## Blast radius

MEDIUM: two modules change.
