# Design resolution — batch-simplify repo-wide mode

```yaml
outcome: early-exit
tier: B
date: 2026-08-18
```

## Why the design stage exits early

`/planning:design` owns types, contracts, module boundaries, and package topology. This change has
none of those to resolve:

- **No new types.** The deliverable is skill prose (markdown) plus one JSON evals file. There is no
  code module, no class, no function signature, no data structure.
- **No module or package topology change.** No new plugin, no new script, no new agent. The
  `context/repo-mode.md` spoke is a progressive-disclosure document, not a code unit — and it follows
  a shape this same skill already uses (`context/reference.md`).
- **No cross-module integration.** Repo mode composes only surfaces batch-simplify already invokes.
  The one sibling touched, `tidy`, receives a one-line reciprocal boundary statement — prose
  reconciliation, not an interface.
- **No data-model change.** The run-state inventory is a working note in a consumer-resolved
  location, deliberately not a schema (Brief constraint 5).

## The one contract that does change, and where it is already resolved

The skill's **argument grammar** is the only contract this work alters, and the locked Brief already
specifies it completely — including the two defects that must be fixed for it to be coherent:

```text
/code-tidying:batch-simplify [<scope>] [docs]

<scope> :=  <N>h | <N>d | <N>w     time-window mode (default 48h)
         |  branch                  branch-diff mode
         |  repo                    NEW — whole-repository mode
         |  <empty>                 → default 48h

docs     :=  optional flag, composes with every scope value
```

Two existing defects in the parser this grammar implies, both fixed in Phase 1:

1. **Stripping precedence.** `docs` is stripped from `$ARGUMENTS` before mode parsing (`SKILL.md:55`),
   so no scope value can ever carry a path containing the word.
2. **Substring matching.** Mode detection routes any argument *containing* "branch" to branch mode
   (`SKILL.md:41`), so a value that merely mentions it misroutes.

The grammar is deliberately closed in v1: `repo <path>` is out of scope (Brief, Deferred Q26), which
is what keeps this a fixed enumeration rather than an open argument language needing design work.

## Verdict

Tier B requirement satisfied by this early-exit record plus the grammar sketch above. Proceed to
`/planning:plan`. Nothing here is deferred to implementation as an unresolved design thread.
