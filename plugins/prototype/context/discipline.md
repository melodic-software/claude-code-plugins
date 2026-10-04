# Prototype discipline (both facets)

This file binds `/prototype:pressure-test` and `/prototype:explore-directions`. Each run of either
exists for a single open question and its code is deleted once the answer is recorded. Which of the
two to run depends on that question:

| Facet | Kind of question | Example |
|---|---|---|
| `logic` (`/prototype:pressure-test`) | A behavioral or feasibility spike: does this work, and which approach holds? | "Can an overdue loan still be renewed?" |
| `ui` (`/prototype:explore-directions`) | A design prototype: "what should this look like?" | "A table or a card per parcel on the shipments page?" |

A prototype belongs after product intent is settled and before an implementation plan exists: it
shows, at low cost, that an approach behaves as intended before anyone designs around it. When
reading the code or reasoning it through settles the question, skip the prototype. Build one when
the answer only shows up by doing something to a running model and watching the result.

## Model auto-invoke gate

When the model reaches for a prototype without an explicit request to spike, **STOP** and confirm
scope before writing any throwaway code. Do not detour out of an active workflow without
checkpointing your current work first (`/session-flow:handoff` when installed).

## Rules (both facets)

Grouped by who each rule serves. Each row shows what breaking it looks like in the two running
examples.

| Serves | # | Rule | Broken when |
|---|---|---|---|
| The person driving it | 1 | **Starts with one command** | The user has to find a file path or a flag before the loans prototype runs, instead of one entry in the project's existing task runner |
| | 2 | **State in full view** | After a key press, a click or a variant switch, a value changed that the screen does not show, such as a fine that grew while only the due date was printed |
| The code itself | 3 | **Memory only, unless storage is the question** | Loan state is still there after the process exits. Only when storage behavior is what is being tested does a store exist, and then its name says it may be wiped, such as `prototype-scratch.sqlite` |
| | 4 | **No polish** | Time went into shared helpers, test files or error handling beyond what keeps it running; each one slows the next change, and the next change is the point |
| Whoever comes later | 5 | **Marked as disposable from the start** | A reader who opens `src/loans/renewal.prototype.ts` or the `/shipments` variant folder cannot tell it is not production code, or it sits in a new top-level directory instead of next to the code it would replace, inside the project's existing layout and routing |
| | 6 | **Delete or absorb when done** | Code is removed before the answer, including more than the winner (see [When done](#when-done)), is written down |

One substrate-scoped exception to rules 3 and 6: when the user, offered `/design` by
`/prototype:explore-directions`, runs the bundled `design` skill's canvas as an alternative to the
throwaway HTML mockup, the variants live in a published, persistent Artifact under the user's account.
That persistence is opted into knowingly at the offer site, not a rule violation; the repo side
stays clean either way (nothing tracked references the canvas, and the durable answer is still
captured in markdown before the prototype is closed out).

## When done

Capture what the prototype taught somewhere durable: wherever your project keeps design
decisions (a decision note, commit message, ADR, or issue tracker). If the user is present, a
quick conversation captures the verdict; if not, leave a placeholder `NOTES.md` next to the
prototype so the answer gets filled in before deletion. Then delete the throwaway code.

**Record the directions that lost, not only the one that won.** Name each direction that was tried
and the reason it lost. A losing direction is the cheapest possible answer to "why not just do it
this way?", and it is the only part of the exercise a future reader cannot reconstruct from the
shipped result. When the verdict is a graft rather than a single winner, such as "this layout, but
that one's navigation", say which piece came from where, and what was in the discarded parts that
the graft deliberately left behind. The deletion in the next step is irreversible: whatever is not
written here is gone, and the question gets re-litigated from scratch the next time it comes up.

## Outside a prototype's job

- **Production code.** A prototype skips tests and most error handling on purpose, so any part of
  it that survives is rewritten when it is folded in.
- **Describing the current system.** Reading and tracing the codebase shows what exists; a
  prototype tries out what might exist.
- **Future requirements.** One question gets one answer. A request that starts "and later we might
  also need" waits for a prototype of its own.

## Composition

| When | Skill | How it composes |
|------|-------|-----------------|
| Product intent locked | `/planning:prd` (when installed) | PRD says "users need X", and the prototype proves X works |
| Architecture discovery surfaced a design question | `/architecture:improve` (when installed) | Improvement pass surfaces the opportunity → prototype validates the approach |
| Prototype answered the question | `/planning:plan` (when installed) | Validated decision feeds the plan |
| Logic module worth keeping | `/implementation:implement` (when installed) | Lift the pure module into production; delete the TUI shell |

Ordering note: **mock before you wire**. When a change has both a "does the interaction work"
question and real integration work, run the throwaway mock (this plugin) before any wiring. A
mock that fails kills the wiring work for free; wiring first turns every design misfire into
rework of live code.
