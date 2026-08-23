# Hunter lenses — the recall stage of `/bugs:scan`

Loaded on demand by `/bugs:scan` Step 2. Each lens below is a **dispatch contract for one
fresh-context hunter subagent**, written in the four-part shape that keeps a fan-out from duplicating
work or leaving gaps: **objective**, **output format**, **tool and source guidance**, **task
boundaries**.

Dispatch one subagent per lens over the resolved scope. Do not merge two lenses into one agent — the
whole point of the decomposition is that each hunter reads a narrow context and finds whatever lives
there.

## Rules that apply to every lens (paste into every hunter prompt)

- **Evidence quote is mandatory.** Every candidate must carry a verbatim quote of the offending source
  lines, with `path:line`. Extract the quote before writing the claim. If you cannot find a quote that
  establishes the fault, **drop the claim** — do not weaken it into a suspicion.
- **Reason only from the code in front of you.** Do not assert how a library "usually" behaves from
  memory; if the behavior matters and is not visible in the repo, say the claim is unverifiable and
  drop it.
- **Reporting no candidate is a valid, expected outcome.** Most lenses on most runs find nothing. An
  empty return is a successful run. Never manufacture a candidate to look productive.
- **You are read-only.** Read, search, and (where a cheap check exists) run it. Never edit, never
  write to the repository, never branch, never file anything.
- **Excluded classes — do not report these**: denial of service, rate-limiting, resource exhaustion,
  generic input validation with no stated impact, open redirects, secrets-at-rest, and style or
  formatting opinions. They are FP-prone or belong to another lane.
- **Cap yourself.** Return at most 5 candidates, ranked by evidence strength. Quality of evidence beats
  quantity of claims.

### Shared output format

Return each candidate as:

```markdown
### Candidate <n> — <one-line present-tense symptom>

- **Lens**: <lens id>
- **Location**: `<path>:<line>` in `<function or class>`
- **Evidence**: verbatim quote of the offending lines
- **Fault**: what is wrong, in one or two sentences
- **Trigger**: the concrete input, state, or call sequence that reaches the fault
- **Impact**: what breaks for whom
```

If the lens found nothing, return exactly: `No candidates for <lens id>.`

## Lens 1 — contract vs body (same unit)

- **Objective**: find places where a unit of code does not do what its own contract says. The contract
  is the unit's signature, parameter and return types, nullability, docstring or doc comment, and any
  invariant named in that same unit (asserts, guard clauses, `@throws`, documented ranges).
- **Boundaries**: **same unit only.** The contract and the body must both be visible in the one
  function/method/class you are examining. A mismatch between a doc file and code is not yours — it
  belongs to the docs/config drift lane. Do not follow callers.
- **Sources**: the function bodies and their immediately attached documentation in the assigned files.
- **Look for**: a documented return that the body can never produce; a parameter documented as optional
  that is dereferenced unconditionally; a declared-non-null return with a path that returns null/None;
  an error the docstring promises that no path raises; a range or unit stated in the comment and
  violated in the arithmetic.

## Lens 2 — boundary and edge cases

- **Objective**: find inputs at the edges of a domain that the code mishandles — empty, zero, one,
  negative, maximum, off-by-one, duplicate, unicode, unsorted, `null`/`None`, overflow, timezone and
  DST edges, leap day, and the empty-collection case.
- **Boundaries**: only report an edge case whose *reachability* you can argue from the code — name the
  caller, entry point, or input source that can supply the value. A theoretically-possible value with
  no path to it is not a candidate.
- **Sources**: loops, slices and index arithmetic, comparisons (`<` vs `<=`), parsing and formatting,
  pagination and chunking, retry and backoff counters, date arithmetic.
- **Look for**: a loop bound that skips the last element; a `>=` that should be `>`; division without a
  zero guard; a slice whose start can exceed its end; an accumulator that assumes at least one item; a
  default that silently substitutes for a missing required value.

## Lens 3 — cross-file consistency drift

- **Objective**: find **behavioral divergence between code units that must agree** — duplicated logic
  that has drifted apart, parallel implementations of one rule, and caller/callee assumption
  mismatches (a caller that passes what the callee cannot accept, or handles a result shape the callee
  no longer returns).
- **Boundaries**: this lens is about **code vs code**. Factual claims in documentation or configuration
  measured against code are **not** in scope here — that is `codebase-health:audit`'s surface across
  all of its dimensions. If your candidate's evidence is a sentence in a doc or a value in a config
  file, drop it and say so.
- **Sources**: pairs of files that implement the same rule (validation in two layers, a constant
  defined twice, a serializer and its deserializer, a client and a server view of one payload).
- **Look for**: two copies of one calculation that no longer match; a validation applied on one path and
  not on its sibling; an enum extended in one place and switched on exhaustively in another; a
  caller-side null check that the callee's contract makes wrong.

## Lens 4 — state and concurrency hazards

- **Objective**: find defects that depend on ordering, sharing, or lifetime — mutable state escaping
  its owner, check-then-act races, unsynchronized shared access, resources not released on the error
  path, and re-entrancy or reuse of a single-use object.
- **Boundaries**: only report a hazard where the code shows the sharing or the ordering — a real
  concurrent entry point, a shared/global/static, a cached instance, a callback, or a documented
  reentrant path. Do not speculate that "this might be called concurrently".
- **Sources**: module-level and static state, caches, connection and file handles, locks, async and
  thread entry points, iterators and generators, cleanup/finally/dispose paths.
- **Look for**: a check followed by an act with no atomicity between them; a mutable default or shared
  buffer reused across calls; a resource opened outside a `try` whose close sits inside it; state
  mutated inside a retry so the second attempt starts dirty; an `await` between reading and writing a
  shared value.

## Lens 5 — git-hotspot guided read

- **Objective**: read where defects historically cluster. Rank the scope by change frequency and by
  fix-shaped commits, then read the top files with all four lenses above in mind.
- **Tool guidance**: `git log --format='%H' --since='<window>' -- <scope>` for churn;
  `git log --oneline --grep='fix\|bug\|revert\|hotfix' -- <path>` for fix density; read the two or
  three highest-ranked files closely rather than skimming ten.
- **Boundaries**: the ranking is a *reading order*, not evidence. A file being hot is never itself a
  candidate — every candidate still needs its own quote and trigger.
- **Degradation**: on a **shallow clone or a repository with no history**, this lens cannot rank. Skip
  it and print one notice — `lens 5 (git-hotspot) skipped: no usable history` — rather than guessing a
  ranking. The other four lenses run unchanged.

## Bundled generic default lanes

Used by rotation mode when no cascade layer declares `lanes` (see
[`${CLAUDE_PLUGIN_ROOT}/reference/config.md`](../../../reference/config.md)). They are deliberately
stack-neutral: match what exists, skip what does not, and never assume a repo layout.

| Lane | Globs (match what exists) | Why it is its own lane |
|---|---|---|
| `entrypoints` | CLI mains, HTTP handlers/routes/controllers, job and queue consumers, event handlers | Untrusted input arrives here first; boundary defects have the widest blast radius |
| `core-logic` | Domain/business/service/model source directories, excluding tests | Where correctness bugs cost the most and reviewers look the least |
| `data-access` | Repositories, DAOs, query builders, migrations, serializers/deserializers | State, transactions, and shape mismatches concentrate here |
| `integration` | Clients and adapters for external services, retry/backoff/timeout code, webhooks | Caller/callee assumption drift and error-path resource leaks |
| `config-and-startup` | Bootstrap, dependency wiring, feature flags, environment parsing | Runs once, is rarely tested, and fails in production only |

Rotation order is the table's order. A lane whose globs match no files in this repository is skipped
(recorded as skipped, not as exhausted) and rotation moves to the next one.
