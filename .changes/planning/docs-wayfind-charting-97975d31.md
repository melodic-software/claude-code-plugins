---
bump: minor
---

### Added

- **Plugin-eval cases for `/planning:wayfind`:** each `evals.json` case as an `evals/wayfind-*` case with one grader per expectation, and `fixtures/wayfind-charting/prepare-arm.sh` to build a before or after arm.

### Changed

- **`/planning:wayfind` routes its argument.** An item link, `#<n>` or tracker key works that item on its map; any other text is the topic. A bare call with an open map lists the frontier, recommends one item and waits for the pick.
- **Chart proposes the whole map and waits for one yes** before it creates anything on the tracker: the destination, each item with its type, mode and what it waits on, the Not-yet-specified bullets and the Out-of-scope list.
- **Chart's first question is what done looks like**, recommending a PRD for a coding effort and a decision record or summary otherwise.
- **"I don't know" is a full answer.** Chart sorts each unknown by who can settle it: evidence (a research item, researched before anyone recommends an answer), the user (an interview item), or nobody yet (fog).
- **Chart reads the repository's glossary and work-item conventions** before its first question.
- **Shorter maps.** Notes holds only standing constraints, the skills to consult and durable pointers; fog is one labeled bullet per uncertainty; an item body is the question and the criteria an answer must meet.
- **Items are topics.** A decision item is a topic one session can work, with its related questions inside it. Sharp questions that already have a recommendation and wait on nothing are asked in one interview round before the map exists.
- **Research findings reach the dossier branch.** After `/discovery:research` returns, wayfind copies the findings file and its sidecars to the item's folder on the map's dossier branch, and the resolution comment gives the pick and why, costs, how the alternatives compare, what could not be verified, and a link to the findings. Map research asks for the `light` verification level, with no separate verifier pass.
- **The interview stays the entry** and may offer wayfind in its first round; the description no longer says wayfind is "not the first step".
- **`wayfind_hitl_concurrency` counts per person** (assignee) on a map, default 1, instead of per map across every session.
- **Each worked item ends with a report and a resume line:** the closed item, its Decisions-so-far line, new items and what is now unblocked, then "clear, then `/planning:wayfind <next item link>`".
- **Resolution comments have shapes:** an interview item's is the agreed result as a table plus out of scope, deferred, glossary changes and what later items inherit; a prototype's is its verdict; a human-only task, routed to `/wizard:generate`, records names and locations, never values.
- **Prototype items** follow a template (what to prove, pass checks, the action on fail, the fallback), and a decision resting on a prototype not yet run is provisional until that prototype confirms or reverses it.
- **One dossier branch per map, one folder per item,** pushed with fetch, rebase and a plain push retried on rejection. The branch is deleted when the destination's container closes, and the map's closing comment names it.
- **A map does not close while Not-yet-specified holds a bullet:** each is charted, moved into a mop-up interview item, or ruled out of scope explicitly.
- **A build-set map closes to `/planning:plan`, then `/work-items:decompose`** from the plan; direct decompose stays for a map whose decisions already read as slices.
