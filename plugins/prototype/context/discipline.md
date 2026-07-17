# Prototype discipline (both facets)

Shared by `/prototype:logic` and `/prototype:ui`. A prototype is **throwaway code that
answers a question** — the question decides the shape. The `logic` facet is a behavioral /
feasibility spike ("does this work / which approach?"); the `ui` facet is a design prototype
("what should this look like?").

Prototyping sits between locking product intent and committing to an implementation plan: a
prototype proves "X works like THIS" cheaply before you architect it. Skip when the question is
answerable by reading code or thinking — prototype when you need to push buttons and watch state
change.

## Model auto-invoke gate

When the model reaches for a prototype without an explicit request to spike, **STOP** and confirm
scope before writing any throwaway code. Do not detour out of an active workflow without
checkpointing your current work first (`/session-flow:handoff` when installed).

## Rules (both facets)

1. **Throwaway from day one, clearly marked.** Locate it close to where production code will live
   so context is obvious. Name it so a reader sees it's a prototype, not production. Obey existing
   routing/directory conventions — don't invent new structure.
2. **One command to run.** Use the project's existing task runner. The user starts it without
   thinking.
3. **No persistence by default.** State lives in memory. Persistence is what the prototype is
   *checking*, not depending on. If the question involves a database, use a scratch DB or local
   file with a clear "PROTOTYPE — wipe me" name.
4. **Skip polish.** No tests, no error handling beyond runnable, no abstractions. Learn fast,
   delete fast.
5. **Surface the state.** After every action (logic) or variant switch (UI), show the full
   relevant state so the user sees what changed.
6. **Delete or absorb when done.** The answer is the only thing worth keeping.

## When done

Capture what the prototype taught somewhere durable — wherever your project keeps design
decisions (a decision note, commit message, ADR, or issue tracker). If the user is present, a
quick conversation captures the verdict; if not, leave a placeholder `NOTES.md` next to the
prototype so the answer gets filled in before deletion. Then delete the throwaway code.

## What a prototype does NOT do

- **Does not produce production code** — prototype constraints (no tests, minimal error handling)
  mean the code is rewritten when folded in.
- **Does not explore what IS** — reading and tracing the codebase understands what exists; a
  prototype tests what *could* be.
- **Does not generalize** — no "what if we wanted to support X later." One question, one answer.

## Composition

| When | Skill | How it composes |
|------|-------|-----------------|
| Product intent locked | `/planning:prd` (when installed) | PRD says "users need X" — prototype proves X works |
| Architecture discovery surfaced a design question | `/architecture:improve` (when installed) | Improvement pass surfaces the opportunity → prototype validates the approach |
| Prototype answered the question | `/planning:plan` (when installed) | Validated decision feeds the plan |
| Logic module worth keeping | `/implementation:implement` (when installed) | Lift the pure module into production; delete the TUI shell |
