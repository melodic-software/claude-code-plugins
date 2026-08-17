---
topic: claude-code-workflows-context-cost-and-disable
section: payload-removal
abstract: Disabling removes the Workflow tool from the tool list before the request is built — its isEnabled() is the disable predicate and the tool array is filtered by isEnabled() — so the schema leaves the payload rather than the tool merely refusing invocation.
claims:
  - claim: "The Workflow tool's `isEnabled()` is exactly the workflows-enabled predicate `jD()`, which returns false when disableWorkflows or CLAUDE_CODE_DISABLE_WORKFLOWS is set."
    confidence: HIGH
    tiers: [0]
    sources:
      - url: "local: claude.exe v2.1.232, `isEnabled:()=>jD()` in the WorkflowTool object"
        tier: 0
        pool: "installed CLI binary (direct tool output)"
      - url: "local: claude.exe v2.1.232, `function jD(){if(Fkr())return!1; …}`"
        tier: 0
        pool: "installed CLI binary (direct tool output)"
      - url: "https://code.claude.com/docs/en/settings"
        tier: 1
        pool: "Anthropic (code.claude.com docs)"
  - claim: "The session tool list is filtered by each tool's isEnabled() before the request is built, so a disabled Workflow tool is absent from the tool array rather than present-and-refusing."
    confidence: HIGH
    tiers: [0]
    sources:
      - url: "local: claude.exe v2.1.232, `let a=o.map((c)=>c.isEnabled()),l=o.filter((c,u)=>a[u])`"
        tier: 0
        pool: "installed CLI binary (direct tool output)"
      - url: "local: claude.exe v2.1.232, `...B3r&&jD()?[B3r]:[]` on the simple/coordinator path"
        tier: 0
        pool: "installed CLI binary (direct tool output)"
      - url: "https://www.aihero.dev/how-to-kill-the-bloat-in-claude-codes-system-prompt"
        tier: 2
        pool: "aihero.dev (named practitioner blog) — request-body diff"
  - claim: "An empirical request-body diff confirms the schema leaves the wire payload: disabling workflows removed ~5,391 tokens from the captured request."
    confidence: MEDIUM
    tiers: [2]
    sources:
      - url: "https://www.aihero.dev/how-to-kill-the-bloat-in-claude-codes-system-prompt"
        tier: 2
        pool: "aihero.dev (named practitioner blog)"
      - url: "local: claude.exe v2.1.232, 19588-byte description consistent in magnitude"
        tier: 0
        pool: "installed CLI binary (direct tool output)"
produced_by: phase-2
---

# Does disabling remove the schema from the payload, or only refuse invocation?

**This was the load-bearing question, and it is settled: disabling REMOVES the tool from the request
payload.** It is not a runtime refusal with the schema still resident.

All evidence captured **2026-08-17**; Tier 0 from the installed **v2.1.232** binary.

## Why the docs alone do NOT settle it — say this plainly

The official docs never make the distinction. The strongest statement is:

> "When workflows are disabled, the bundled workflow commands are unavailable, the `ultracode`
> keyword no longer triggers a run, and `ultracode` is removed from the `/effort` menu."
> — [workflows](https://code.claude.com/docs/en/workflows) (fetched 2026-08-17)

Every item in that sentence is a *behavioral* consequence. None of them says the tool definition
leaves the request, and the `disableWorkflows` settings row ("Disable dynamic workflows and the
bundled workflow commands") is equally silent. **A reader restricted to first-party prose cannot
answer this question**, which is exactly why the answer below rests on Tier 0 and an empirical diff
rather than on documentation.

Claude Code *does* document this pattern for a different tool family, which establishes that removal
from the payload is a thing it deliberately does:

> "In Claude Code v2.1.233 and later, the following tools aren't available on Opus 4.8, Sonnet 5,
> Fable 5, Mythos 5, or later versions of those families unless you opt in: `TodoWrite`, `TaskCreate`,
> `TaskGet`, `TaskUpdate`, and `TaskList`. … **the tools' definitions and reminders take up context,
> so Claude Code leaves them out.**"
> — [tools-reference](https://code.claude.com/docs/en/tools-reference) (fetched 2026-08-17)

That is an analogy, not proof for workflows. The proof follows.

## Tier 0: the mechanism, in three linked facts

**1. The Workflow tool declares its enablement as the disable predicate.**

```js
isEnabled:()=>jD()
```

**2. `jD()` is false whenever any disable mechanism is active.**

```js
function Fkr(){ return Y.CLAUDE_CODE_DISABLE_WORKFLOWS || U5()?.settings.disableWorkflows === !0 }

function jD(){
  if(Fkr())                      return !1;
  if(!uBo())                     return !1;          // gs("allow_workflows")
  let {available:e, defaultOn:t} = B4s();
  if(!e)                         return !1;
  return U5()?.settings.enableWorkflows ?? t
}
```

**3. The tool list is filtered by `isEnabled()` before the request is assembled.**

On the main path, the registry `TY()` is mapped and filtered:

```js
let n = TY().filter((c)=>!r.has(c.name)),
    o = Vde(n,e),
    …
    a = o.map((c)=>c.isEnabled()),
    l = o.filter((c,u)=>a[u]);
return l
```

`l` — the returned tool array — contains only tools whose `isEnabled()` was true. A disabled
`Workflow` never reaches it, so its 19,588-byte description is never serialized into the request.

On the `CLAUDE_CODE_SIMPLE` / coordinator path the same gate is applied inline and even more
explicitly, as a conditional spread:

```js
...B3r && jD() ? [B3r] : []
```

where `B3r` is the `WorkflowTool` binding
(`B3r=(()=>((b8f(),dn(_8f)).initBundledWorkflows(),(w6a(),dn(E6a)).WorkflowTool))()`).

Both code paths agree: **the tool is conditionally included, never included-then-refused.**

Note the contrast with the tool's *other* guards. `validateInput` returns
`{result:!1, message:"This session restricts the Workflow tool to named workflows …"}` and
`checkPermissions` returns `{behavior:"deny", …}`. **Those are the refuse-at-invocation paths, and
they are separate from `isEnabled()`.** Claude Code has both kinds of mechanism, and
`disableWorkflows` is wired to the removal kind, not the refusal kind.

## Empirical confirmation on the wire

The Tier 0 reading predicts that a captured request body loses ~19.6 KB of tool schema when
workflows are disabled. That prediction was tested independently, by pointing `ANTHROPIC_BASE_URL`
at a local server, running `claude -p "hi"` with the flags off and then on, and diffing the two
captured request bodies. Reported outcome: **~27% smaller baseline, ~5,391 tokens saved per request,
with the entire delta attributable to `disableWorkflows` removing the Workflow tool**
(<https://www.aihero.dev/how-to-kill-the-bloat-in-claude-codes-system-prompt>, reached 2026-08-17).

The two lines of evidence are independent — one reads the binary's control flow, the other observes
the serialized HTTP body — and they agree in mechanism and in magnitude.

**Confidence split, deliberately.** The *mechanism* claim (removal, not refusal) is **HIGH**: it
rests on Tier 0 control flow I read directly, on two separate code paths. The *specific number*
(~5,391) is **MEDIUM**: `www.aihero.dev` is egress-blocked in this environment for both `WebFetch`
and `curl`, so that figure reached me only through WebSearch synthesis of a single publishing pool
and I never read the page first-hand.

## What this means for the skill

- `disableWorkflows` / `CLAUDE_CODE_DISABLE_WORKFLOWS` is a **genuine fixed-prefix trim**, not a
  cosmetic toggle. It is the strongest single built-in-tool trim currently available.
- The trim is **all-or-nothing**. There is no supported way to keep the `Workflow` tool while
  shrinking its description, and no per-field pruning.
- Because the gate is `isEnabled()` and the filter runs at tool-list assembly, the saving applies to
  **every request in the session**, not only the first — the 19,588 bytes are re-sent on each turn
  when workflows are on, subject to prompt caching.
- A Pro-plan user who has never opted in is **already** not paying this cost, so a baseline harness
  must record the plan/opt-in state or it will report a phantom saving.
