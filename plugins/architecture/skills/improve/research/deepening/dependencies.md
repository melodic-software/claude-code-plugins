# Dependencies and Seams

How to deepen a cluster of shallow modules safely, given dependencies. Uses vocabulary from [vocabulary.md](vocabulary.md).

## Dependency categories

When assessing a candidate for deepening, classify dependencies. Category determines testing strategy across the seam.

### 1. In-process

Pure computation, in-memory state, no I/O. Always deepenable — merge the modules and test through the new interface directly. No adapter needed.

### 2. Local-substitutable

Dependencies with local test stand-ins (PGLite for Postgres, in-memory filesystem, SQLite for SQL Server). Deepenable if stand-in exists. Test with stand-in running in the test suite. Seam is internal; no port at the module's external interface.

### 3. Remote but owned (Ports and Adapters)

Own services across a network boundary (microservices, internal APIs). Define a **port** (interface) at the seam. Deep module owns logic; transport injected as **adapter**. Tests use in-memory adapter. Production uses HTTP/gRPC/queue adapter.

Recommendation shape: "Define a port at the seam, implement an HTTP adapter for production and an in-memory adapter for testing, so logic sits in one deep module even though deployed across a network."

### 4. True external (Mock)

Third-party services (Stripe, Twilio, etc.) you don't control. Deepened module takes external dependency as injected port; tests provide mock adapter.

## Seam discipline

- **One adapter = hypothetical seam. Two adapters = real seam.** Don't introduce a port unless at least two adapters are justified (typically production + test). Single-adapter seam is indirection.
- **Internal seams vs external seams.** Deep module can have internal seams (private, used by own tests) and external seam (at its interface). Don't expose internal seams through the interface.

## Replace, don't layer

When deepening merges shallow modules behind a deep interface:

- Old unit tests on shallow modules become waste once tests at the deepened interface exist — **delete them**
- Write new tests at the deepened module's interface. The **interface is the test surface**
- Tests assert on observable outcomes through the interface, not internal state
- Tests should survive internal refactors — they describe behavior, not implementation. If a test changes when implementation changes, it's testing past the interface

This principle applies beyond the deepening lens — any module consolidation that moves the test surface to a deeper interface. Choose test doubles at the deepened seam per the dependency category above.
