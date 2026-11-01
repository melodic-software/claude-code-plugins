# Prototype discipline (every facet)

This file binds `/prototype:pressure-test`, `/prototype:explore-directions` and
`/prototype:build-generator`. Each run exists for a single open question and its code is deleted
once the answer is recorded (for a generator, once its output is harvested). Which to run depends on
that question:

| Facet | Kind of question | Example |
|---|---|---|
| `logic` (`/prototype:pressure-test`) | A behavioral or feasibility spike: does this work, and which approach holds? | "Can an overdue loan still be renewed?" |
| `ui` (`/prototype:explore-directions`) | A design prototype: "what should this look like?" | "A table or a card per parcel on the shipments page?" |
| `generator` (`/prototype:build-generator`, run by a person) | An artifact prompting cannot hit: a tool the person tunes, whose output goes into the project | "A torn-paper edge that looks hand-ripped, not stamped" |

A prototype belongs after product intent is settled and before an implementation plan exists: it
shows, at low cost, that an approach behaves as intended before anyone designs around it. When
reading the code or reasoning it through settles the question, skip the prototype. Build one when
the answer only shows up by doing something to a running model and watching the result.

## Model auto-invoke gate

When the model reaches for a prototype without an explicit request to spike, **STOP** and confirm
scope before writing any throwaway code. Do not detour out of an active workflow without
checkpointing your current work first (`/session-flow:handoff` when installed).

## Rules (every facet)

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

One canvas-scoped exception to rules 3 and 6: when the user, offered `/design` by
`/prototype:explore-directions`, runs the bundled `design` skill's canvas as an alternative to the
throwaway HTML mockup, the variants live in a published, persistent Artifact under the user's account.
That persistence is opted into knowingly at the offer site, not a rule violation; the repo side
stays clean either way (nothing tracked references the canvas, and the durable answer is still
captured in markdown before the prototype is closed out).

A second exception to rules 3 and 6, scoped to `/prototype:explore-directions`'s review mode: the
variants and the reviewers' answers live in `/planning:interview`'s shared session, and stay in its
untracked data dir after the session ends. The user opts in knowingly when saying yes to review
mode, nothing tracked references the session, its data dir or its link, and the durable answer is
still captured in markdown before the prototype is closed out.

A third exception, to rules 3 and 6, for `/prototype:build-generator`: while the person tunes,
its generating tool may live in the project and its save button may write the configuration to a
project file, because production imports that file. Once the person picks a keeper and the output
is harvested into the project, the tool is deleted; the saved configuration and any export stay,
since they are the harvested output.

A fourth exception, to rule 6, for the [evidence step](#evidence-step): the shell still leaves the
working tree when the prototype is closed out, but the prototype's files can stay reachable on a
pushed throwaway branch. That branch holds the evidence only when the repository's own secrets and
machine-data check passed over those files; otherwise nothing is pushed, and the note records where
the files were and why they were not pushed.

## When done

Capture what the prototype taught somewhere durable: wherever your project keeps design
decisions (a decision note, commit message, ADR, or issue tracker). If the user is present, a
quick conversation captures the verdict; if not, leave a placeholder `NOTES.md` next to the
prototype so the answer gets filled in before deletion. Once the note holds the answer, run the
[evidence step](#evidence-step), and only after it delete the throwaway code.

**Record the directions that lost, not only the one that won.** Name each direction that was tried
and the reason it lost. A losing direction is the cheapest possible answer to "why not just do it
this way?", and it is the only part of the exercise a future reader cannot reconstruct from the
shipped result. When the verdict is a graft rather than a single winner, such as "this layout, but
that one's navigation", say which piece came from where, and what was in the discarded parts that
the graft deliberately left behind. The deletion that closes the prototype is irreversible: whatever
is not written here or pushed by the evidence step is gone, and the question gets re-litigated from
scratch the next time it comes up.

### Evidence step

Run it after the durable note is written and before the throwaway code is deleted. It adds no
check of its own: it relies on the repository's own secrets and machine-data check, and pushes only
when that check passes.

1. **Find the check.** It is the scan the repository already runs over files before they leave the
   machine, such as a pre-push or pre-commit secrets hook, or a pre-push secrets step its
   source-control tooling runs, as its contributing guide, agent instructions or hook configuration
   names it.
2. **Run it over the prototype files**: every file the prototype added or changed inside the
   working tree, the shell included. A file kept outside the repository, such as an HTML page in a
   temp directory, is never copied in; the note records its path.
3. **Name the branch** by the repository's declared branch-naming convention (its contributing
   guide, agent instructions or a branch-name check). Never use the default branch's name, or a
   name or prefix the repository reserves for automation lanes.
4. **Push, or record why not.**
   - When the check passed and the convention gave a name: create that branch in a separate
     worktree, copy the prototype files into it, commit only them, push that branch (never the
     default branch), and remove that worktree. The working tree keeps the prototype files as they
     were, for the lift and the deletion that follow. Write the branch name and the commit SHA into
     the durable note.
   - Otherwise push nothing: the repository has no such check, the check failed, no convention is
     declared, or the push itself failed. Write the prototype's local path and
     `not pushed: <reason>` into the note, such as `not pushed: no secrets check in this repository`.
     When the push failed after the commit, also write the local branch name.

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
