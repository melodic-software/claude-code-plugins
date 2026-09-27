<!-- markdownlint-disable MD049 -->

# Security and failure semantics

Self-contained. Pin: 2026-09-19, Claude Code 2.1.278. Basis labels: `OBSERVED` /
`SOURCE` / `BINARY` / `STAFF` / `COMMUNITY` / `INFERRED`.

The authoritative file for this section is
`architecture-pdf/DENY-AND-ERROR-SEMANTICS.md` (read + locally observed, in the
test kit and in two live headless runs). It **supersedes** the corresponding
passages in `architecture-pdf/ARCHITECTURE-PDF.md`, which are marked in place.

## Deny — what blocks, and what does not

| Construction | Effect | Basis |
|---|---|---|
| `tool.call` hook returns a well-formed `{ deny: reason }` **instead of** calling `next(e)` | **Blocks.** Caller receives the deny, the hook beneath never runs, the model receives `<tool_use_error>reason</tool_use_error>` with `is_error: true`, and the side effect does not happen (the shell command did not run; the file was not created). | `OBSERVED` HIGH — test kit + live headless run |
| `tool.check` hook returns `{ decision: 'deny', reason }` instead of `next` | **Blocks**, same way. `decision` is `'allow' \| 'ask' \| 'deny'`; the last word up the chain is the decision. | `OBSERVED` `SOURCE` HIGH |
| `{ deny }` returned **after** `await next(e)` | **Does not un-run anything.** Beneath ran; the caller still receives the deny; the file is on disk. Ground truth and what the model is told diverge. | `OBSERVED` HIGH |
| Returning `{}` or `undefined` without calling `next` | **Fails open.** The site refuses the shape, treats the hook as failed, skips it, and the chain beneath runs: the tool executes and the model is told it succeeded. | `SOURCE` `COMMUNITY` HIGH |
| `{ deny: "" }` | Blocks the effect but reaches the model as an empty `<tool_use_error></tool_use_error>`, which reads as a broken tool rather than a policy refusal. | `COMMUNITY` HIGH |

**The rule, in one sentence:** a guard needs a well-formed `{ deny: reason }`
**and** no `next` call. Both halves are load-bearing. A deny branch that can fall
through to an implicit `undefined` return is fail-open with only `--debug` as
witness.

The maintainer comment that circulated as "deny does not block" is about a
`{ deny }` returned *after* `next(e)`:

> The return of 'deny' here is not somehow making the tool not get called. To
> make the tool not get called, don't call `next(e)`. … Our logic for determining
> "did the chain _say_ it denied it or not" is merely
> `const approved = result.deny === undefined`.

`STAFF` · HIGH · #91870 comment 5546290346, 2026-09-04T20:49:39Z. Read in
context it says `deny` is a **report** to the model and the block comes from not
calling `next`. Both halves agree with the `.d.ts` and with every primary
example, which all have the same shape:
`return dangerous ? { deny: reason } : next(e)` (`.d.ts:L7250`; PDF Listings 1
and 6; `mods/sec-default/hooks/register.ts`).

One behavior change is on record: a community member measured `{deny:""}` not
blocking on **2.1.260** and blocking on **2.1.261** and **2.1.263**. The early
"deny does not block" reading plausibly originates there. It does not hold on
2.1.278. `COMMUNITY` · HIGH.

`classic.PreToolUse` keeps the exact `allow` / `ask` / `deny` result shape and
receives the flattened `{ tool, command, … }` envelope, so an existing PreToolUse
guard's contract ports unchanged. `SOURCE` · HIGH; the layering is confirmed live
(classic hooks ran only when the mod was skipped), but a `classic.PreToolUse`
deny *returned from a mod* was not itself exercised. `OBSERVED` · MEDIUM.

Observed live: a `tool.call` deny lands **above** the classic chain, so the
classic chain never runs. `OBSERVED` · HIGH.

## Throw, overrun, and the fail-open trap

`.d.ts:L3209-3211`, on every engine event:

> At every one, a hook that fails (throws, overruns its budget: HookBudget,
> answers a wrong shape) is skipped: the hooks beneath and core run in its place,
> or its last `next` result stands; the failure is reported by name.

`SOURCE` · HIGH. Observed:

- **Throw, no `.catch` → fail-open.** The caller receives the answer from beneath,
  indistinguishable from a chain in which nothing failed. `OBSERVED` · HIGH
- **Throw with `.catch` returning a deny → fail-closed.** Caller receives
  `{ deny: "CAUGHT_throw: …" }`, beneath counter 0. `next.error.kind` is
  `'throw'` and `next.error.message` carries the original message.
  `OBSERVED` · HIGH
- **Overrun past 10 s → fail-open, live.** Engine's own debug record:
  `[ERROR] hook failed: denymod: … (tool.call; skipped; what is below it ran in
  its place)`, cut at **10,249.9 ms**, `next(e)` run on the hook's behalf, core
  ran, and the model received a *different* guard's text. `OBSERVED` · HIGH
- The only witness is an `[ERROR]` line in `--debug-file`. **No transcript row,
  nothing on stdout under `-p`, no `$.ui.log` line.** `COMMUNITY` `OBSERVED` · HIGH

`HookBudget`: `ms: 10_000` per dispatch (*"past it the hook is absent (its
`.catch` asked, else `next(e)` run on its behalf)"*), `catchMs: 1_000` grace,
`lingerMs: 5_000`. Each bounds the hook's **own** time: the clock stops while a
`next(e)` or any `$` call is in flight, **a `$.clock` wait excepted**.
`SOURCE` · HIGH. So an external policy call over `$.http.fetch` or
`$.process.run` is not the risk; a slow regex over a long command string is, as
is any `$.clock` backoff inside the guard.

**`.catch` is shipped, not a proposal.** `Registration.catch` is in the `.d.ts`
(*"Sets the handler run when the hook throws or overruns its budget; its answer
within the grace stands as the hook's result for the dispatch … without it a
failed hook is absent"*) and works in practice. Latest maintainer restatement:
*"Have you come across the `on(...).catch(...)` spelling yet? I think this would
address your use-case re fail-closed / fail-open."* `STAFF` · HIGH ·
comment 5702935782, 2026-09-16T18:58:28Z. `.catch` has only 1,000 ms of grace,
charged fresh — the handler should return a constant deny and nothing else.

### The four conditions for a guard written as a mod today

1. Return a well-formed `{ deny: reason }` (or `{ decision: 'deny', reason }`)
   **instead of** `next(e)`, never after. Non-empty reason; never an implicit
   `undefined` fall-through.
2. Attach `.catch(() => ({ deny: … }))` to **every** guard hook. Without it a
   throwing or slow guard is removed and the tool runs — **strictly weaker than
   the classic command hook it replaces**, since a classic hook exiting with code
   2 blocks.
3. Keep the guard's own code well under 10 s.
4. For authority over other *plugins* rather than over the model alone, the guard
   must be seated in a managed tier. A user-tier install binds the model's tool
   calls — the normal guard threat model — but not sibling plugins.

`OBSERVED` · HIGH · `architecture-pdf/DENY-AND-ERROR-SEMANTICS.md` verdict.

`tool.check` is the better seat for a pure policy guard: it is the permission
decision rather than the invocation, `$.tool.check` can be called as a query that
executes nothing, and guards there can run concurrently. Staff: *"the latter's
core _is_ the action of invoking the tool, so there would be no sensible way to
parallelize guards over that monoid."* `STAFF` · HIGH · comment 5618866247. A
guard needing to rewrite the command, or to see what the tool returned, needs
`tool.call`.

**The engine's *default* on an uncaught throw is still undecided upstream** and
nothing about it is documented; the maintainer's position moved through four
recorded positions between 2026-09-03 and 2026-09-08. But author-side fail-closed
is constructible today and is the right framing: *the engine default is
undecided; a guard that wants fail-closed must construct it itself rather than
rely on an engine default.* `STAFF` · HIGH ·
`community-falsification/VERIFICATION.md` row 2e (which corrected an earlier
over-strong "rests on an undecided behavior").

## `sec-default` and managed tiers

`sec-default` constrains by **ordering, not policy**. Its whole register body is
three moves over twelve patterns: continue past the user tier
(`next.to(e, 'append')`), refuse a user-tier caller by name (`{ deny }` when
`next.origin.tier === 'user'`), or pass (`next(e)`). Policy is read through
`$.settings.read({ source: 'policy' })`, one read serving a burst; **both fail
closed**, so an unreadable policy counts as a policy in force.
`SOURCE` · HIGH · `mods/sec-default/README.md:L12-17`.

What it leaves untouched, explicitly: `prompt.submit`, `turn.*`, `tool.call`,
`tool.check`, `command.run`, `command.register`, `session.*`, `ui.*`, `fs.*`,
`http.fetch`, `process.run`, `store.*`, `clock.*`, `model.*`, `mcp.call`,
`audio.*`, `agent.list`, `engine.create`. `SOURCE` · HIGH.

Consequences for a third-party author:

1. On a managed machine your plugin is seated **beneath** `sec-default` and
   cannot reach what it guards. Design for that, not around it.
2. `prependPlugins` is the managed-settings key that changes seating. It is
   implemented in 2.1.278 (`BINARY` · HIGH) and has **zero** issue-tracker hits —
   undocumented in the community record and unexercised in public.
3. **Outside a managed org, `sec-default` is not seated at all**, so none of this
   protection exists.

Mods that draw UI, wrap tool calls or add context additively are unaffected by
`sec-default`; mods that rewrite settings reads, re-describe org-provided tools
or agents, or register tools while `allowedMcpServers` is set will be refused on
managed machines. `SOURCE` · HIGH ·
`surfaces-desktop/RESEARCH-enterprise-policy.md`.

## Isolation is not part of the contract

Asked whether isolation is a boundary or a convention, the maintainer answered:

> It's a boundary! The current design is a Bun Worker surrounding the entire
> plugin realm, with each plugin then having a `node:vm` wrapper - **that's not
> part of the contract though, the contract is merely that you don't get access
> to ambients.** So it _is_ mechanically the case that you cannot `import fs`
> etc. The boundary's job is to make sure everything goes through `$`.

`STAFF` · HIGH · comment 5546290346. Two things to carry:

- **Do not design against the Worker.** The mechanism is today's implementation;
  the promise is only "no ambients". `STAFF` · HIGH
- **`node:vm` is not a security sandbox.** This is *this corpus's inference*, not
  a maintainer concession — he asserted the opposite in form and nobody in the
  thread challenged it. The support is Node's own documentation: *"The `node:vm`
  module is not a security mechanism. Do not use it to run untrusted code."*
  **No independent security review of mods was found.** `INFERRED` · HIGH-supported ·
  `community-falsification/VERIFICATION.md` row 2d.

Corroborating the no-ambients half empirically: in the live-session probe a
`node:fs` import in module scope left no marker while `$.fs.write` did.
`OBSERVED` · HIGH.

The stated security posture is **mediation, not restriction**, and the threat
model is explicitly delegated to the org admin:

> Our prerogative is not to restrict what plugins can do; that's your org
> admin's job. The point is that there's no _ambient_ support, everything goes
> through `$` so that admins can audit, allowlist, deny, log, etc. any event.

`STAFF` · HIGH. **For a team with no managed settings and no admin-authored gate
plugin, there is no constraint beyond the decision to install.**

Staff also flag `next.trace` as a deliberate hazard — it exposes the chain's
event snapshots below you — and propose surfacing its use as `plugin.register`
metadata so admins can refuse plugins that read it. `STAFF` · MEDIUM.

## Supply chain

- **No signing. No mod-specific provenance. No new review gate.** The question
  was asked explicitly and answered *"dependencies, versions, etc. will all go
  unchanged."* `STAFF` · HIGH
- **No marketplace listing** for the built-in mods, and by extension none
  established for third-party ones. `SOURCE` · HIGH
- **In-process arbitrary TypeScript**, mediated but not contained, running inside
  the CLI that holds credentials and repository access. A mod is materially more
  dangerous than a classic plugin because it can rewrite rendered output and tool
  results. `INFERRED` · HIGH-supported
- The engine's protections here are **availability, not integrity**: it refuses a
  module that fails the static scan, and skips a hook that throws, overruns, or
  returns the wrong shape. `SOURCE` · HIGH
- Compare the adjacent *shipped* surface: `claude plugin eval`'s own `--help`
  warns that *"the run's sandboxing limits what a malicious plugin can reach but
  is not a guarantee, and a bundled suite passing is not a security vetting."*
  The same honesty applies to mods and is not written down anywhere for them.
  `SOURCE` · HIGH

## Issue #92533 — the worktree break

**The highest-value known defect for this repository.**

Registering **any** `tool.call` hook on Bash breaks `Agent(isolation:
"worktree")`. The reporter bisected it properly:

| Configuration | Subagent `pwd` |
|---|---|
| Project plugin with Bash hooks active | refused |
| Same, with `CLAUDE_CODE_ENABLE_FUNCTION_HOOKS=0` | OK |
| Fresh repo, minimal plugin, only a `session.start` hook | OK |
| Fresh repo, minimal plugin, only a Bash `tool.call` **passthrough** | **refused** |

Reporter, verbatim: *"The hook itself can be a pure passthrough `next(e)` with no
logic: the mere registration of a Bash `tool.call` hook triggers the loss
(`tengu_agent_worktree_cwd_escape_blocked` / `context_lost`)."* Read/Edit and MCP
tools keep working; only Bash is blocked; retrying never helps.

**Side effect:** if the blocked subagent calls `EnterWorktree` to recover, the
**parent session** is switched into that worktree and its own `git` commands are
refused outside that directory until `ExitWorktree`.

State on 2026-09-19: **OPEN, filed 2026-09-06 on 2.1.263 (macOS), no staff
reply in 13 days**, labels `bug, has repro, platform:macos, area:bash,
area:hooks, area:agents`. Its sole comment is an independent **Windows**
reproduction at 2.1.272. `COMMUNITY` · HIGH ·
`community-falsification/VERIFICATION.md` row 3.

**Per M1, this hazard may not be opt-in.** Because the env var is only an
override over a rollout gate, a plugin shipping a `tool.call` hook on Bash could
break worktree isolation for consumers who never set the variable, should the
gate and its further conditions resolve true.

Adjacent open defects, all `COMMUNITY`: #92675 plugin-native `PreToolUse` hooks
auto-discovered via `hooks/hooks.json` reported not enforced in interactive
sessions (OPEN, 0 comments) — this undermines the coexistence story; #95328 a
`session.compact` hook's compaction undone on resume; #92469 and #92440 on
generated-type incompleteness and drift.

## Performance — do not plan against either number

Two figures exist and disagree by four orders of magnitude because they measure
different things: **~50 µs p99 per hook**, a vendor claim about in-process
dispatch on Bun (`STAFF`), and **1.4 s first draw** through a render hook, one
community cold-start measurement to which the maintainer replied *"the numbers
ought be faster than this"*. **No independent benchmark exists.** This is the
weakest-evidenced area in the whole corpus and no performance claim is accepted.
`COMMUNITY` · LOW.
