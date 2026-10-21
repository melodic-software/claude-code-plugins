# Design Threads: session-gateway

## Thread 1: Tunnel exposure boundary. RESOLVED

Decision: the gateway accepts tunnel traffic only through an authenticated proxy that
terminates TLS and strips client-supplied identity headers; the gateway itself never
listens on a public interface.
Rationale: once a deployment exposes the gateway directly, every integrator builds against
that exposure and the trust model cannot be tightened without breaking them. It is a
security boundary, enforced by network topology rather than by any single code path, so a
reader of the handlers would not see why requests are trusted. Direct public exposure with
per-request token checks was rejected because one missed check becomes an open endpoint.

## Thread 2: Data folder per session. RESOLVED

Decision: each session writes to its own data folder named by session id.
Rationale: the folder name is derived in one helper and visible in the session constructor;
moving to a shared folder later is a one-function change plus a small data move. A single
shared folder was rejected only because it needs locking, which is not worth adding yet.

## Thread 3: Log line format. RESOLVED

Decision: log one JSON object per line.
Rationale: the existing log reader already parses JSON lines, and the format can be changed
by editing one formatter. Plain text lines were rejected because they would need a new
parser.

## Thread 4: Principles. RESOLVED

Principles applied: information hiding keeps the trust decision in the proxy, out of the handlers.
Generalize now or wait: the Brief's `Variation intent: not applicable (confirmed)` line settles it: no
variation question.
Rationale: the Variation intent line is the user's answer.

## Thread 5: Lifecycle and reversibility. RESOLVED

Door: Thread 1 one-way (integrators build on the exposure); Threads 2 and 3 two-way.
Rationale: Thread 1 is the only call that integrators build on.
