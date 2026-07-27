# Changelog — session-flow plugin

## [0.17.16]

### Fixed

- **0.17.15 was based on a wrong diagnosis and did not fix anything
  (melodic-software/claude-code-plugins#1687).** That release removed git from seven skills'
  pre-compute blocks on the theory that the harness composes a block into one shell invocation and
  the worktree-isolation guard refuses a git-bearing compound command. An adversarial re-probe
  refutes it. `git status --porcelain 2>/dev/null | head -20 || echo clean` — git, a pipe, a
  redirect, and a `||` — **passes** from a worktree-isolated agent. `echo "${CLAUDE_CODE_SESSION_ID:-unknown}" || echo "unknown"`,
  which has no git at all, is **refused**. Git, pipes, redirects, `||`, and multi-line composition
  are all irrelevant.
  - **The real trigger is a `$`-expansion.** A command is refused iff it contains one in any form
    other than bare `$HOME` or `"$HOME"`; a skill fails to load iff its pre-compute block contains at
    least one such expansion. Because 0.17.15 kept
    `` !`echo "${CLAUDE_CODE_SESSION_ID:-unknown}" || echo "unknown"` `` in six of the seven skills,
    `handoff`, `continue-in-background`, `orient`, `retro`, `running-retro`, and `find-handoff`
    stayed uninvocable from an isolated agent for the whole of 0.17.15. Only `workflow` was fixed,
    and only incidentally — its entire pre-compute block had been deleted.
  - The session-id pre-compute line is removed from all six. The value is re-acquired in the skill
    body with `printenv CLAUDE_CODE_SESSION_ID`, which carries no `$` and is observed to pass under
    isolation. Failure is treated as "unknown, carry on", as before.
  - Deleting that line emptied the `## Pre-computed context` block of `handoff`,
    `continue-in-background`, `orient`, `retro`, and `running-retro`, so the now-bare heading is
    removed too. Only `find-handoff` still has a pre-compute block.
  - `find-handoff`'s transcript-dir glob keeps its pre-compute line with `${HOME}` reduced to bare
    `$HOME`; the full line was run verbatim under isolation and passes. Its body reference to the
    "pre-computed" session id is repointed at the gathered value.
  - The 0.17.15 body prose asserted the falsified mechanism and derived an instruction from it ("do
    not restore it as a `| head -20` pipe" — a form now observed to pass). That rationale is
    corrected and compressed to one sentence in all seven skills, `workflow` included. The 20-entry
    read bound is kept as a plain instruction; only its false justification is dropped.
  - **New observation, beyond what #1687 recorded.** `echo $CLAUDE_CODE_SESSION_ID` — bare, no
    braces — is also refused, while `echo $HOME` passes. The guard's allowlist is therefore
    name-specific, not merely form-specific, and `HOME` is the only member found across two
    independent probe sessions. That is uncharacterized upstream behavior: a guard tightening would
    regress `find-handoff`'s remaining pre-compute line, and nothing else in this plugin.
  - What was verified, precisely: from this worktree-isolated agent, every command form above was
    run standalone and its PASS/REFUSED result recorded, including the replacement `printenv` call
    and `find-handoff`'s rewritten glob line. The **edited skills have not been invoked** from an
    isolated agent and cannot be — skills load from the version-keyed plugin cache, so `0.17.16`
    does not exist there until this ships and plugins are updated. Confirm then, with a negative
    control. CI cannot prove this fix; it never invokes a skill from an isolated agent.
  - Still out of scope: several bodies and `reference/` snippets run `$`-bearing shell (for example
    `retro`'s transcript parser invocation). Those skills now **load** under isolation, but those
    specific body commands remain subject to the same guard.

## [0.17.15]

### Fixed

- **Every git-bearing skill in this plugin was uninvocable from a worktree-isolated agent
  (melodic-software/claude-code-plugins#1619).** The harness composes an entire
  `## Pre-computed context` block into ONE shell invocation, and the worktree-isolation Bash guard
  refuses a git-bearing compound command it cannot statically verify — so `handoff`,
  `continue-in-background`, `workflow`, `running-retro`, `orient`, `retro`, and `find-handoff` all
  failed at load with `this command is too complex to verify that it stays inside the worktree`.
  The failure hit hardest exactly where these skills matter most: an isolated parallel agent could
  not write a save-point, orient itself, or recover a handoff.
  - The git lines are removed from each skill's pre-compute block and re-acquired in the skill body
    as **individual** Bash calls, one command per call. Non-git pre-compute lines are untouched —
    they were never the problem (`knowledge:course-digest`, four complex non-git lines, loads fine
    under isolation).
  - The old lines carried caps (`git status --porcelain | head -20`) and `2>/dev/null || echo`
    fallbacks that a plain Bash call does not reproduce. Both are restated as reading rules: treat a
    failed command as "unknown, carry on", and honor the 20-entry bound **when reading** rather than
    re-adding a `| head -20` pipe — a piped git command is compound, which is the shape that started
    this.
  - `find-handoff` is the proof that line count is not the trigger: it carried a single, pipe-free
    git line among three non-git lines and was refused, while a skill whose *only* pre-compute line
    is a compound git command loads. The rule is git-in-a-composed-block, not per-line complexity.
  - `shell: bash` is deliberately left in place on every affected skill, including `workflow`, which
    now has no `!` lines at all. The key is inert without pre-compute lines, and removing it is a
    frontmatter-contract change with no behavioral benefit.
  - What was verified, precisely: from an `Agent` with `isolation: "worktree"`, the **unfixed**
    skills were observed to be refused, plain git commands were observed to succeed as individual
    Bash calls, and a multi-line non-git pre-compute block was observed to load
    (`knowledge:course-digest`, the positive control). The **edited** skills have not been invoked
    from an isolated agent: skills load from the version-keyed plugin cache, so `0.17.15` does not
    exist there until this ships and plugins are updated. Confirm then. CI cannot prove this fix —
    it never invokes a skill from an isolated agent.

## [0.17.14]

### Fixed

- **`orchestrate`'s nested-subagent sources were stale, but not in the direction the audit reported
  (melodic-software/claude-code-plugins#1479 audit follow-up).** The audit's top finding claimed
  `SKILL.md`'s "a configurable default of three" was factually wrong and that nesting is off by
  default. Re-verification refutes that: the byte-exact changelog records v2.1.219 —
  "Subagents can now spawn nested subagents up to depth 3 by default (was 1); set
  `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1` to disable nesting" — and the harness agrees (a non-fork
  subagent one layer down held a fully-schema'd `Agent` tool on 2.1.220 with the variable unset).
  The finding had been drawn from the `sub-agents` prose page, which still documents the superseded
  v2.1.217–2.1.218 off-by-default state. `SKILL.md`'s claim stands; what changed is where it is
  sourced from.
  - `context/sources.md`'s imperative-5 block is rewritten to current text. Its previous quotes
    ("a background subagent at depth five does not receive the Agent tool", "The limit is fixed and
    not configurable") no longer appear in the page and are contradicted by the env var existing.
    The block now carries version-pinned changelog quotes for the depth default, the current
    tool-list gating sentence, all three separately-overridable caps with their defaults, and an
    explicit drift note recording that the two official surfaces currently disagree and which one to
    believe for what.
  - `SKILL.md`'s depth paragraph re-attributes the depth-3 default to the changelog (which carries
    it) rather than the `sub-agents` page (which currently contradicts it), pins each state to its
    version, and adds a **confirm-nesting-from-behavior** rule: have a worker of the *same agent
    definition* you plan to use as the intermediate tier attempt a trivial nested spawn and report
    the outcome before committing a design to a second layer — a tree authored from either page
    alone can be wrong in both directions; the gate is definition-specific, so a spawn from another
    agent type proves nothing; and holding `Agent` is necessary but not sufficient, since the tool
    can be listed while the spawn is still refused.
    A refusal is then read rather than assumed: a depth rejection names depth, while a permission
    refusal says nothing about the ceiling, because spawns are classifier-evaluated before launch
    (v2.1.178).

### Added

- **A non-binding size anchor for imperative 7's small/medium/large.** The sizing had no numeric
  reference at all, leaving it rationalizable either way. The Tiered-delegation section (which the
  export brief omits, keeping the pasted brief model- and tool-agnostic) now cites the platform's
  own numbers — the `/config` workflow size guideline's "fewer than 5 / 15 / 50 agents" and the
  `Large workflow` flag above 25 — as a reference point, with an explicit instruction to say which
  one you are overriding when your sizing and the anchor disagree by an order of magnitude.
- **The priming addendum now reads the session's own effort level** via the documented
  `${CLAUDE_EFFORT}` substitution, closing one of the two calibration factors imperative 7 named
  with no consumable signal. It is the level a spawn inherits when neither the call nor the agent
  definition sets one — a definition's own `effort` frontmatter overrides the session — which is
  precisely the over-provisioning imperative 7 exists to stop. Priming-only and export-omitted, so
  the pasted brief stays agnostic; the addendum also notes `ultracode` reports as `xhigh` and so
  cannot reveal whether script-held workflow orchestration is active.
- **`context/gotchas.md`** — the skill had no gotchas surface (a `skill-quality:check` warning). It
  records four earned failure modes: the nesting ceiling outrunning the prose docs, a denied spawn
  being misread as a depth answer, a clean worker return that is a wrong-target return, and priming
  being mistaken for emitting. Routed from the Purpose section alongside `context/sources.md`, so it
  actually enters working context — a spoke the hub never points at clears the static check without
  changing behavior.
- **Two eval cases covering decision-criteria quality, not just export mechanics.** The existing
  five all tested formatting and emission; nothing exercised the judgments the skill is for.
  `sizes-small-ask-single-agent` forces a size classification on a concrete small ask, and
  `tiers-wide-fanout-cheaper-default` asserts the cheaper-tier default at wide fan-out with the
  judgment-heavy stage kept as the explicit exception.

## [0.17.13]

### Added

- **Handoff structure doc hardened from the upstream handoff-failure corpus audit
  (melodic-software/claude-code-plugins#1477).** Two write-side rules added, both adopted because a
  real failure mode upstream demonstrated the gap and nothing in the existing template guarded it:
  - **Claim provenance.** A status claim may be stated plainly only when this session verified it;
    anything inherited (a prior handoff's assertion, an issue label, a remembered state) carries an
    explicit `UNVERIFIED (<source>)` marker — an inherited claim is a claim to falsify, not a fact
    to forward. Closes the laundering gap where an unverified "not built yet" forwarded as fact
    causes the resuming session to rebuild something that already exists. The existing
    fresh-reads-this-turn checklist items governed only what the writing session could probe; they
    said nothing about claims the session inherited and could not probe. Lives in `save-point.md` as
    a BOTH-paths rule (mirroring the existing redaction pass) — `reference/structure.md` points to
    it for the full-file path's body sections, and `skills/handoff/SKILL.md`'s prompt-only checklist
    carries its own tick so an inline remaining-work bullet cannot forward an inherited claim
    unmarked either.
  - **Edge-case re-scan for Constraints that must hold.** Before closing the section, re-scan for
    *but* / *except* / *unless* / "the exception is" / "the corner case" — those words mark
    mid-discussion constraints that never rose to a top-line bullet, the category a resuming session
    ships as a bug. The template forced the section to exist but had no recall step for constraints
    buried inside accepted decisions. After an unexpected compaction the model-visible conversation
    is the summarizer's output, not the original turns, so `reference/structure.md` now requires the
    section to say explicitly whether it re-scanned the lossless on-disk transcript (`retro`'s
    parser reads the same record) or is disclosing that pre-compaction turns went unscanned — never
    presenting a post-compaction scan as complete without saying which.

## [0.17.12]

### Added

- **The detached observer's distilled observations now carry enough structure for the headless
  running-retro analysis to COMPUTE sequencing/batching/dependency claims, not just drop them.**
  `summarize_record()` previously stripped every tool call down to its name and every tool result
  down to a bare count, so `observer.py`'s headless `_analysis_prompt` — despite instructing the
  analyzer to "group tool-use events by API message id" and check for a dependency before flagging a
  missed-batching Efficiency finding — had no field it could actually compute either claim from. Two
  additions close the gap: an assistant event now carries `mid` (a bounded correlation key derived
  from the transcript's own API message id, when present) so events sharing one `mid` can be
  recognized as one batched turn versus separate sequential turns — verified against real session
  transcripts (of 6,352 tool-bearing message ids across 200 live sessions, 1,412 (~22%) spanned 2+
  tool-bearing records, confirmed again as a positive control against this repo's own session
  transcripts, 580/5,431 (~11%)), so `mid` — not record adjacency — is what makes batching computable
  at all — and both assistant
  (`calls[].in`) and user (`results[].out`) events now carry a bounded (80-char) preview of each tool
  call's input/result, keyed by a bounded correlation id, so a later call's input can be checked
  against an earlier call's output for a genuine dependency. Both fields are omitted (not padded) when
  the underlying data isn't present, and ids are shortened to an 8-char correlation key rather than
  persisting the full opaque id. This measurably grows the observations file on tool-heavy sessions:
  re-measured against the final schema over 24 real session transcripts carrying 20+ tool-bearing
  records each, distilled by this version and by the version it replaces, the observations grow
  **61.9% in aggregate** (per-file mean 63.0%, median 61.4%, range 43.7–116.0%). The growth is
  almost entirely the preview content itself, which is the point — a real, bounded,
  single-analysis-call cost against a cheap model, not an unbounded one. Every field has a hard cap,
  and the flags below are emitted only when they apply. Redundant/wasteful bytes (verbose ids, a
  `tool_results` count now superseded by `len(results)`, JSON-dumping a tool-result content-block
  list instead of extracting its text) were cut wherever doing so didn't reduce the analyzer's
  actual computing capability.
  Every bounded field pairs with an out-of-band flag when the preview is incomplete (`cut` on a
  `calls`/`results` entry, `say_cut`/`human_cut` beside the narration), so a value cut short of a
  dependency reads as unknown rather than as a clean absence that would license an
  asserted-and-wrong finding. The flag is out-of-band rather than a trailing marker in the text
  because an in-band marker can't be told apart from a value that genuinely ends in those characters
  (a complete tool result reading `Processing complete...`), which would suppress computable
  findings in the other direction. `cut` also covers a mixed content-block result — text alongside
  an image or document block keeps only the text, so the preview is incomplete even though it fits
  the limit. A `results` entry additionally carries `err` when the call failed, because a failed
  call's own output preview is routinely empty and a later retry is control-dependent on having
  seen that failure.
  `_analysis_prompt` updated to reference the new fields and flags. Its dependency check is now five
  explicit places rather than two, any one of which makes a sequential pair correctly sequential:
  it compares the earlier call's own `calls[].in` against the later call's, since a side-effecting
  call (`mkdir` before a `Write` into that directory) returns nothing and narrates nothing so a
  result-only comparison read a required sequence as a missed batch; it treats a state-wide consumer
  (a build, test, lint, typecheck, or VCS command) after a state mutation as dependent even though
  neither input names a shared path, since `Edit foo.py` then `Bash pytest` is the most common
  sequential pair in a coding session and the resource comparison structurally cannot see it, with an
  undecidable mutation dropping rather than routing; and it treats a retry after an
  `err` result as control-dependent — recognized by a shared resource, repeated arguments, or a
  visible correction of the failed input (`git stats` → `git status`), but never by tool name alone,
  since a failed `Read` of one file followed by a `Read` of another is two independent calls.
  Where a failure sits in the pair and none of that evidence is legible, the pair is unknown rather
  than independent and the claim is dropped — a failure between two calls is never license to report
  a missed batch. A candidate pair must also sit inside one user turn — no
  intervening `human` or `turn_boundary` event — before the dependency test runs at all, since two
  calls answering different human prompts could never have been batched however independent they
  are. That precondition needs the boundary to be visible, and keying it off extractable text left it
  invisible in every session carrying no `stop_hook_summary` record at that point — a prompt encoded
  as `content: ["next request"]` (a bare string, which retro's canonical `parse_transcript.py`
  already counts as a human message) emitted no `human`, and an image- or document-only prompt yields
  no readable narration at all, so calls answering prompts on either side became a candidate pair.
  `summarize_record()` now reads a bare string as a human message like a `text` block, and marks the
  boundary STRUCTURALLY: any user record carrying content that is not a `tool_result` is the human
  speaking — text, a bare string, an image, a document, or a block type that does not exist yet —
  while a pure tool-result record stays inside the turn, since marking those would split every
  genuinely batched turn and suppress real findings. Its grouping rule no longer both asserts sequential
  execution for a missing `mid` and calls
  that case uncomputable — a missing grouping key is now uniformly uncomputable, never evidence of
  sequential execution.
  `tools` is unaffected and still carries the tool-call names a "delegation" finding needs (a Task/
  Agent tool name), so delegation required no new field — the gap #1485 closes is sequencing/batching/
  dependency only. The in-session checkpoint path (which reads the raw transcript directly) is
  unaffected. Follow-up from #1473 (PR #1482) and Codex's review of it — filed as #1485, scoped to the
  schema change deferred out of that PR. This supersedes the headless prompt's 0.17.5 caveat that
  `summarize_record()` never preserves a message id: it now does, so the prompt's absent-key wording
  is scoped to the per-record case (the raw record carried no id) rather than to the schema.

## [0.17.11]

### Fixed

- **Two surfaces still described the pre-0.17.9 re-arm shape.** 0.17.9 made the loop re-arm one
  counted, length-delimited entry per surviving loop, but `handoff`'s gotcha entry was not swept
  with the rest — it still warned about "an active `/loop`" singular and called the re-arm a single
  unstructured follow-up message, which is the shape the engine stopped emitting. It now names the
  one-per-loop rule and the counted header, so the checklist, the engine doc, and the gotcha say the
  same thing.
- **The entry header no longer spells out an ungrammatical worked example.** `<L>` is a fixed
  `lines` token deliberately — a parser should not need English plurals to find a boundary — but the
  no-launch-signal fallback illustrated it as the literal `Re-arm 1 of 1 — 1 lines:`, putting
  "1 lines" into terminal output an operator reads. The invariance is now stated once as a property
  of the header, and both the engine doc and `find-handoff` reference the generic form, so the
  fallback needs no example of its own and `1 lines` reads as well-formed rather than as drift.

## [0.17.10]

### Fixed

- **`observer.py`'s `_pid_alive` Windows liveness check no longer assumes a fixed decoder for
  `tasklist` output.** #1483/#1496 (0.17.7-era) hardcoded `encoding="utf-8"` with
  `errors="replace"` on the `subprocess.run` call. `tasklist`'s piped output actually follows the
  **console output code page**, which is not fixed — measured on one machine, the same command in
  the same session returned UTF-8 bytes under `GetConsoleOutputCP=65001` and CP437 bytes under
  `GetConsoleOutputCP=437` (two shells in one session genuinely disagreed), so a hardcoded `oem`
  would have been wrong in the opposite direction just as often. Before #1496's `errors="replace"`,
  a CP437 console plus a process name containing an undefined-in-cp1252 byte (e.g. `ü`) raised
  `UnicodeDecodeError` inside `subprocess`'s reader thread, leaving `out.stdout` as `None` and
  `str(pid) in out.stdout` raising out of `_pid_alive` — `errors="replace"` closed that crash path
  but left the decoder assumption in place as a correctness smell (harmless today only because the
  predicate matches ASCII digits, which mojibake in a process *name* cannot change). `_pid_alive`
  now drops decoding entirely and matches `str(pid).encode("ascii")` against `tasklist`'s raw
  `stdout` bytes, removing the code-page question from the call site altogether (#1512).

## [0.17.9]

### Fixed

- **The multi-loop re-arm landed on the producer only, so recovery and the handoff checklists still
  spoke of one loop.** 0.17.8 taught `save-point.md` to emit "one re-arm message per loop left
  standing", but the surfaces that consume that output were not moved with it: `find-handoff`'s
  capture step asked for "the re-arm instruction" and matched a single `send /loop …` shape, its
  confirm gate surfaced the note "when one was found", and both of `handoff`'s enforcement
  checklists still read "if a loop is active, a below-the-rails note". A handoff written with three
  surviving loops therefore recovered one of them and dropped two after `/clear` — the producer-side
  failure 0.17.8 fixed, reintroduced one layer down in the consumer, which is the same shape as the
  two recovery defects already fixed in this series. The capture now keeps matching past the first
  hit; the confirm gate surfaces all of them; the redaction invariant and the
  *does NOT do* list are pluralized so they cannot be read as licensing a single-note recovery; and
  `save-point.md`'s own detection contract names the recoverable unit as every re-arm message the
  producer wrote, so the two sides state one rule.
- **The re-arm entries are length-delimited, so an arbitrary multi-line loop prompt survives
  recovery.** The producer quotes the original prompt verbatim and a `/loop` prompt can carry
  newlines, so an entry is not reliably one physical line — and no content test can bound it.
  Matching command wording cuts the first multi-line prompt in half and swallows every entry behind
  it; a marker fares no better, since a verbatim prompt is allowed to contain whatever marker is
  chosen and would then split its own command. Each entry is now headed
  `Re-arm <i> of <n> — <L> lines:` with the body on exactly the next `<L>` lines, and the block is
  emitted last in the message. Counting lines is the one boundary that cannot collide with what it
  delimits. `<n>` is retained as a self-check rather than a scanner: `find-handoff` reports what it
  recovered against what the producer said it wrote, instead of presenting a subset as the whole
  set. `save-point.md`'s detection contract states the same boundary, so the stable contract an
  agent reads cannot send it back to the wording match its consumer no longer performs.

## [0.17.8]

### Fixed

- **The save-point engine's resume prompt dropped the `/loop` wrapper.** The engine doc's
  goal-aware re-arm rule ("Emit the copy/paste resume prompt") had no loop-aware counterpart, so a
  resume prompt written for a session running under `/loop` read as a bare continuation task.
  Pasted after `/clear` — which clears every session-scoped scheduled task
  (<https://code.claude.com/docs/en/scheduled-tasks#limitations>) — that ran the continuation once
  and silently dropped the recurring behavior, with no error to signal it. `save-point.md` now
  carries a loop-aware re-arm rule: the rails block stays the unwrapped resume directive, and a note
  below the bottom rail has the reader send `/loop [<interval>] <original prompt>` as a SEPARATE
  follow-up message, quoting the interval and prompt verbatim from the launch turn. The re-arm
  carries the ORIGINAL loop prompt rather than the resume directive because `/loop` re-runs the
  prompt it was given on *every* iteration
  (<https://code.claude.com/docs/en/scheduled-tasks#run-a-prompt-repeatedly-with-%2Floop>) while a
  save-point is an immutable record of one moment — wrapping the directive would make every later
  tick re-read that frozen file and replay an already-finished remainder instead of doing the loop's
  actual recurring job. Order is stated (bootstrap first, re-arm second) so the re-armed loop's first
  iteration cannot run ahead of the continuation it resumes into. Both re-arm rules now key off a
  concrete conversational signal — this session's own `/loop` launch turn (corroborated, never
  gated, by a later `ScheduleWakeup` reschedule) and an established `/goal` call — rather than
  "infer from conversation" prose. Neither re-arm can ride inside the other's prompt argument, since
  a command is recognized only at a message's start
  (<https://code.claude.com/docs/en/commands>), so each is its own message: `/goal` keeps the first
  line between the rails, `/loop` follows separately. The launch-turn signal is read as a set rather
  than a single find: a session can hold up to 50 scheduled tasks at once
  (<https://code.claude.com/docs/en/scheduled-tasks#manage-scheduled-tasks>) and `/clear` takes all
  of them, so the rule enumerates every surviving loop and emits one re-arm message per loop —
  a singular rule would have preserved one and silently dropped the rest. Elapsed time retires a
  launch from that set alongside an explicit stop: a recurring task expires seven days after creation
  (<https://code.claude.com/docs/en/scheduled-tasks#seven-day-expiry>), so a launch turn older than
  that is already gone and re-arming it would resurrect a schedule that had already ended.
  `handoff/SKILL.md`'s two enforcement checklists and `handoff/context/gotchas.md` are updated to
  match.
- **Lost-handoff recovery dropped that same `/loop` re-arm.** The re-arm note is the one piece of a
  resume prompt that cannot sit between the rails — a command is recognized only at a message's
  start (<https://code.claude.com/docs/en/commands>), so it is a separate follow-up message and its
  instruction lives below the bottom rail. `find-handoff` recovered only the block between the
  rails, so an operator who ran `/clear` before copying and then recovered the handoff got the
  continuation back and the loop not at all — the very failure the re-arm rule exists to prevent,
  reintroduced one layer down. `save-point.md`'s detection contract now defines the recoverable
  resume prompt as the rails block PLUS the below-rail re-arm note, and `find-handoff` captures it
  (shape-matched and anchored to the bottom rail, on both file and prompt-only modes) and surfaces
  it at the confirm gate. The capture is deliberately not a detection key — it is read only from an
  already-qualified candidate, so it admits no new false positives — and it runs through the same
  redaction pass as everything else, since it quotes the operator's original loop prompt verbatim.
  The capture also runs on the known-location glob short-circuit, which reaches the confirm gate
  without a transcript in hand: it pulls step 5's `session_id` → `<session_id>.jsonl` lookup ahead
  of the gate and reads that one file's tail, so the default discovery path surfaces the note too
  rather than promising it and delivering nothing.
  The note is bound to its candidate by content — the rails block whose `Read @…` directive names
  that exact file — rather than by reading the transcript's tail, since one session can emit
  several handoffs and a loop stopped and relaunched between them would otherwise re-arm the wrong
  recurring work. Same correlate-by-content rule the background-delivery screening already uses.
- **The `/loop` re-arm note is now conditioned on the paste, not on the citing skill.** The engine
  is shared with `/session-flow:continue-in-background`, whose successful launch clears nothing and
  pastes nothing — it hands the rails prompt straight to a detached agent, so the loop stays armed
  on the foreground session and the note's unconditional "after pasting the block above" wording
  described a paste that never happens. Keying the note off the citing skill would have been just
  as wrong in the other direction: the engine emits the prompt BEFORE that skill's dirty-tree gate
  and launch run, and either can fall back to `/clear`-then-paste, which does clear. The note is
  therefore worded conditionally — re-arm if you paste after `/clear`, including on those
  fallbacks; a launch that succeeds needs none. Transferring the loop *into* the launched agent is
  deliberately not done: arming a recurring schedule inside a detached session the operator is not
  watching is a behavior to decide on its own merits, not a side effect of writing a save-point.

## [0.17.7]

### Fixed

- **`observer.py`'s `_pid_alive` Windows liveness check now decodes `tasklist` output as UTF-8
  explicitly.** Its `subprocess.run` call passed `text=True` with no `encoding=`, so Python fell
  back to the platform code page (cp1252 on Windows) instead of UTF-8 — the same class of defect
  `_run_analysis`'s subprocess call was fixed for (#1472). Currently harmless in practice (the only
  check is an ASCII integer substring match against `tasklist`'s stdout), but left implicit it
  risked the same silent-corruption pattern if the check's output-parsing ever changed.
  `errors="replace"` is set alongside it for the same reason as `_run_analysis`'s fix: a
  truncated/invalid byte sequence decodes rather than raising. A full sweep of every other
  `subprocess.run`/`subprocess.Popen` and `open()`/`read_text`/`write_text` call across
  `session-flow`'s production scripts (`observer.py`, `arm_observer.py`,
  `retro/scripts/parse_transcript.py`) found every other text-mode call site already
  UTF-8-explicit or intentionally binary (`"rb"` mode, or a raw `os.open` file descriptor with no
  text decoding involved) (#1483).

## [0.17.6]

### Fixed

- **`running-retro`'s detached observer launcher can spawn again — both the manual `arm` action and
  the opt-in SessionStart auto-arm hook were dead.** `arm_observer.py`'s spawn call referenced an
  undefined `observer` name for the child process's working directory (the resolved script-path
  variable is `observer_py`), raising an unhandled `NameError` on every invocation. Both entry points
  route through this same launcher, so the entire detached-observer feature was inoperable on any
  platform. Fixed the undefined name and widened the narrow `except OSError` guard around the spawn
  call to catch any spawn-time exception, so a future failure at that call site degrades gracefully
  (`observer: failed to spawn: ...`, exit 0) instead of escaping as a raw traceback.

## [0.17.5]

### Fixed

- **running-retro's analysis prompts had no rule requiring structural transcript claims to be
  computed rather than asserted.** An independent fresh-context validation found the checkpoint
  analyzer accurate on findings that harvested the session's own self-declared observations but
  0/2 on independently inferred structural claims (tool-call sequencing/batching/delegation,
  "emerging pattern" occurrence counts) — one asserted-and-wrong claim routed as a tracker issue a
  human would have filed for a non-problem. Both callers of the checkpoint method now carry a
  compute-don't-assert rule naming the observed failure modes: the in-session checkpoint
  delegation (`context/checkpoint.md`'s Method section and delegation prompt template) and the
  detached observer's headless analysis prompt (`observer.py`'s `_analysis_prompt`, which has no
  delegation prompt to fall back on and needed the rule inline). A structural claim that can't be
  computed from the record must now be dropped rather than asserted uncomputed (#1473). The
  headless prompt's message-id-grouping guidance now notes explicitly that the distilled
  observations it receives may not carry a message-id field at all — `summarize_record()` never
  preserves one — so an absent field reads as uncomputable rather than as license to assert from
  impression. The compute-don't-assert rule now also covers the judgment built on top of a
  computed structural fact: a correctly computed sequencing fact does not by itself prove a missed
  batching opportunity (genuinely dependent calls are correctly sequential, not a miss), so both
  prompts now require checking for a dependency before routing an Efficiency finding for
  unbatched/sequential calls — and that check is not narrowed to data flow alone: a control,
  resource, or side-effect dependency (e.g. a directory created before a file is written into it)
  is just as real a reason two calls had to run in order.

## [0.17.4]

### Fixed

- **The running-retro detached observer's analysis subprocess no longer flashes a visible console
  window on Windows, and no longer corrupts non-ASCII ledger entries into mojibake.** `observer.py`'s
  `_run_analysis` called `subprocess.run` for the headless `claude -p` analysis pass with no
  `creationflags` (unlike `arm_observer.py`'s own windowless `spawn_detached`, whose flag set was
  never carried to this later call) and no explicit `encoding=`, so Windows decoded UTF-8 output with
  the platform's cp1252 default. Both are now set explicitly: `CREATE_NO_WINDOW` on Windows only, and
  `encoding="utf-8", errors="replace"` unconditionally — `errors="replace"` keeps a truncated/invalid
  byte sequence from raising past the surrounding `TimeoutExpired`/`OSError` handling (#1472).

## [0.17.3]

### Fixed

- **The shared concern-value parser no longer reads a declared key as absent over YAML key spacing.**
  `parse-concern-value.sh` anchored on the exact regex `^<key>:`, so `memory_dir : .work` (YAML
  permits whitespace before the `:`) and a root block mapping written at a uniform indent both
  resolved to the caller's fallback — substituting a value the repo never chose for one it did.
  Both shapes now resolve, matched at the document's own base indentation so a same-named key
  nested under another mapping never answers for the root one — including when the root key is
  present but deliberately empty. Synced from `lib/parse-concern-value.sh`; version bumped so installed
  copies receive it.

## [0.17.2]

### Fixed

- **Setup's headless reconfigure recipe no longer claims `-y` is CLI-required for a non-TTY
  `uninstall`.** Verified against the live CLI (2.1.220) and current docs: `-y` only skips
  `uninstall`'s `--prune` confirmation, and this recipe never passes `--prune` — so `-y` had no
  effect and is no longer part of the recipe (#1410).

## [0.17.1]

### Changed

- **Setup's `apply` now documents the headless reconfiguration route beside the interactive one.**
  Every observer tunable is native `userConfig`, and `apply` routed reconfiguration through
  `/plugin configure session-flow` only. A headless or CI consumer reading that had no path at all,
  and the obvious guess — re-running `claude plugin install --config` — silently does nothing on an
  already-installed plugin, so the reader would have concluded the value was set when it was not.
  The flag's fresh-install-only behavior is now stated where the reconfiguration guidance lives,
  along with the uninstall-then-reinstall route it forces and the note that one install should carry
  every key being changed. The recipe passes `-s <scope>` on both halves and `-y` on the uninstall:
  both commands default to `-s user`, so an unscoped pair removes a separate user record while a
  project- or local-scoped install keeps loading, and a non-TTY uninstall requires the confirmation
  flag to run at all.

## [0.17.0]

### Changed

- **handoff: the save-point body-section taxonomy is restructured.** The old eight sections led with
  the costly layer — a resuming session learned what to do next in section six of eight — which
  inverts the ladder the org's `progressive-disclosure` convention prescribes. The set now opens
  with a six-line `Resumption brief` a reader can stop at, and the remaining sections are ordered
  frame, world, memory, frontier. Three kinds of state that previously had no home are now owned:
  invariants that must hold, persistent side effects that must not be repeated, and hard-won
  findings that are neither a decision nor a failed approach. `Open questions / next steps` is split
  four ways — a slash in a heading meant it owned more than one taxon, and its numbered list mixed
  the ordered remainder of the work with self-resolvable unknowns and outside blockers — and the
  `Progress` / `Files modified` overlap is resolved into a single file-role map. Every section is now always
  present, with an explicit "nothing to report" rather than an omission, so a cold reader can tell
  silence from oversight. The file-role map owns *how far each file's change got*, not just its
  role: the old blanket "nothing about what changed inside it" left completed progress and
  half-finished uncommitted edits with no owner at all — completion criteria describe outcomes and
  the ordered remainder describes future work — so a cold session had to reconstruct both from the
  working tree, the exact rediscovery this document exists to prevent. Committed work still points
  at its commit range rather than transcribing a diff; uncommitted or half-done work says which part
  is implemented and working and which part is not, because no commit records that.
- **handoff: the emitted resume directive no longer names a section.** It read
  `continue per its "Open questions / next steps"`; it now reads `continue its remaining next steps`.
  The heading was the only runtime coupling to the taxonomy, so the section set can move again
  without touching `save-point.md`, and handoffs already on disk stay resumable. Nothing parses a
  handoff body heading, so existing save-points are unaffected.
- **handoff: consumers cite the section list instead of restating it.** `save-point.md` carried a
  full inline recap that had already drifted from the owner doc on two of eight names, and four more
  files carried partial or differently-spelled copies — one section had accumulated five spellings.
  Per the org's `reference-dont-duplicate` convention a closed enumeration is a mapping table that
  must be cited, never recapped, so `reference/structure.md` is now the single home and the copies
  are pointers.
- **handoff: the "all eight body sections present" checklist assertion is retired.** A count is
  satisfiable by eight wrong sections, it has gone stale before, and it duplicated a value derivable
  from the doc it described. The checklist now walks the structure doc.
- **orchestrate: documents the shape of a multi-tier delegation tree** — what the top tier owns,
  why coordination belongs low in the chain, what a tier-crossing return payload should carry,
  ephemerality as a cost control rather than tidiness, and why a clean worker return is not
  evidence of a correct one. No new machinery; the existing imperatives already permit the tree,
  this names its shape.

### Removed

- **handoff: the write-only `previous_session_id` frontmatter field.** The chain walker
  (`skills/retro/scripts/parse_transcript.py`) only ever read `session_id` and `previous_handoff`;
  the third field was written by the spec, asserted by five documents, seeded by test fixtures, and
  consumed by nothing. Storing the prior session's id in a second place invited the two pointers to
  disagree — the walker resolves it by reading the prior file's own `session_id`. Chain-walking is
  unchanged, verified by the existing chain tests with the field removed from their fixtures.
  The `running-retro` ledger's own `previous_session_id` is a separate, live field and is untouched.

## [0.16.0]

### Added

- find-handoff: new skill (#976). Recovers a lost handoff after `/clear` — the
  failure mode where `/session-flow:handoff` wrote a save-point but the operator
  cleared the session before copying the dashed-rail resume prompt, leaving the
  fresh session with zero context and no path to the handoff on disk. Runs a
  read-only detection ladder: known-location glob of the current repo's
  `<memory_dir>/handoffs/`, then a bounded, recency-ranked scan of transcripts
  (excluding the current session's own file — `/clear` opens a new transcript in
  the same project dir, so the pre-clear content is a sibling) for the handoff
  directive and dashed-rail markers, then a confirm-before-resume gate. Detection
  is substring matching over transcript JSONL (empirically verified: the
  `Read @…-handoff-*.md` directive and `─` rails survive verbatim), not JSON
  parsing — so the skill ships no parser and does not couple to `retro`'s
  transcript parser. Handles both handoff output modes (file-based and
  prompt-only, which writes no file). Read-only and redaction-aware throughout:
  surfaces only the resume prompt + handoff metadata, never raw transcript
  content. Routes to `/session-flow:keep-going` when the recovered session ended
  mid-work. Chains in from `keep-going` step 4 when a post-`/clear` session has no
  known handoff path.

### Changed

- reference/save-point.md: documented the resume-prompt output shape (the
  `Read @…-handoff-*.md` directive, the `─` rails + instruction line, and
  `Prior session: <UUID>`) as a stable detection contract `find-handoff` keys
  off, so a future format change is a knowing break. reference/structure.md notes
  the `type: handoff` frontmatter is part of the same contract, and
  reference/topic-docs.md lists `find-handoff` among the skills that read the
  topic-docs binding to locate the handoffs directory. keep-going step 4 routes
  to `find-handoff` when the handoff path was lost.

## [0.15.2]

### Fixed

- **`reanchor`'s eval case 7 renamed off the pre-rename plugin name (`#1328`).**
  `skills/reanchor/evals/evals.json` still named the negative-routing case
  `negative-routing-rule-discipline-is-re-anchor-plugin` after the `re-anchor` -> `discipline`
  plugin rename (`#1276`); the case's `expected_output` and `expectations` were rewritten in that
  commit but its `id` field was missed. Renamed to
  `negative-routing-rule-discipline-is-discipline-plugin`, matching the sibling
  `negative-routing-*` case names. No other file references the old name.

## [0.15.1]

### Changed

- All five skills whose pre-computed context block injects the session id
  (`orient`, `retro`, `running-retro`, `handoff`, `continue-in-background`) now
  carry a `|| echo "unknown"` fallback on that injection, matching the sibling
  git injections in the same block. Injection failure, timeout, and stderr
  semantics are undocumented upstream, so the standing convention is a
  `|| <fallback>` on every injected command — `skill-quality:check` flags a
  missing one as an advisory WARN. On this particular line the guard is
  unreachable in practice (`${VAR:-unknown}` resolves at expansion time, so
  `echo` receives a formed string and exits 0); it buys block-wide uniformity
  and a quiet gate, not protection against a failure mode the sibling git lines
  genuinely have.

## [0.15.0]

### Added

- running-retro: detached-observer substrate + lifecycle. Evolves running-retro
  from PULL-only (invoked in-session) to a path that can also fire *after* the
  session ends — a `/loop` structurally cannot. A stdlib-only Python 3.10+ tailer
  (`skills/running-retro/scripts/observer.py`, launched detached by
  `arm_observer.py`) outlives the session, tails the transcript out-of-band at
  zero context cost via a no-persistent-handle poll→open→read-new-bytes→close
  loop (safe by construction against the Windows share-mode write edge), detects
  end by mtime-idle, then runs the same checkpoint method headless (a cheap
  `claude -p`) and appends the redacted findings to this session's ledger. The
  analysis run is Read-only (`--allowedTools Read` under `--permission-mode
  dontAsk`) — no code execution over untrusted transcript content — and is the
  single semantic redaction pass; the transient distilled observations are
  machine-local (`${CLAUDE_PLUGIN_DATA}/session-flow-observer/`) and deleted
  after use, so only redacted findings reach the durable ledger. Entry: a new
  `arm` action on running-retro is primary; an OPT-IN SessionStart hook
  (`observer_enabled`, default off — zero-config behavior unchanged) automates the
  same launcher, guarded against self-arming (`CLAUDE_CODE_ENTRYPOINT`, stdin
  `agent_type`, `source`, analysis-run marker). Untrusted-data boundary cites the
  shared `reference/off-thread-work.md`. Native Observer-Agents recorded as a
  deferred alternative (trigger: transcript-level feed / documented-stabilized
  upstream), substrate kept thin so migration stays cheap. Full substrate +
  lifecycle in `reference/observer.md`. The plugin now bundles twelve skills.
- setup: new check-centric skill (`disable-model-invocation`), added because the
  observer introduced an external prerequisite (Python 3.10+) and a `userConfig`
  surface — the uniform setup contract's trigger. `check` verifies the observer's
  prerequisites (Python 3.10+, `jq`, `claude` on PATH) and reports the effective
  config, flagging the `--bare`/OAuth-auth and idle-threshold hazards; no write
  path (reconfiguration routes through `/plugin configure`).
- `userConfig`: the plugin's first config surface — six observer keys
  (`observer_enabled`, `observer_analysis_enabled`, `observer_analysis_model`
  [default `claude-haiku-4-5`, the cost lever], `observer_analysis_bare`,
  `observer_idle_seconds`, `observer_max_seconds`), all defaulting to zero-config
  behavior.
- hooks: opt-in `SessionStart` hook (`hooks/observer-arm.sh`) — the plugin's
  first hook asset; no-ops unless `observer_enabled` is on.

### Notes

- `--bare` on the analysis run is off by default and gated behind
  `observer_analysis_bare`: verified on CLI 2.1.218, `--bare` drops the OAuth-login
  credential state and the run reports "Not logged in". The measured cost lever is
  the model, not `--bare` (which was a projected, never-measured optimization in
  the design memo). Enable it only where auth is an env-var API key that survives it.

## [0.14.0]

### Added

- reconcile: new skill. The prune-and-reconcile counterpart to
  `keep-going`'s resume — where keep-going asks "is it stuck, pick it back up",
  reconcile asks "is anything still running that should be retired, and
  does the task ledger
  match reality?" Inventories the off-thread work this session spawned, inspects
  each item's real state, retires the genuinely finished by clearing them from
  tracking, and closes this session's task-ledger items whose work is proven
  complete. Also reports the read-only liveness of sibling sessions in the same
  project — transcript mtime plus a coarse tail read, never a deep parse of the
  officially-unstable JSONL. Auto-settles the provably-finished (closing a task
  is evidence-gated — the mirror of keep-going's "never kill what you cannot
  prove is dead"); GATES any kill of still-running work, the gate kept in-skill
  because the three inventory skills' blast radii differ. Fixes this session
  only: sibling sessions are visible but report-only, and a spawned subagent's
  internal task list is not readable. MCP / browser / playwright tool-state
  enumeration is deferred with a trigger (no generic tool-state surface exists;
  closing user-owned state would be destructive-against-user). The plugin now
  bundles eleven skills.
- reference/off-thread-work.md: shared engine doc. The open-ended
  off-thread-work inventory kinds and the inspect-real-state-first invariant —
  the mechanics `keep-going`, `orient`, and `reconcile` all share (Rule of
  Three) — are extracted to a plugin-level reference all three cite via
  `${CLAUDE_PLUGIN_ROOT}`, each thinned to its own delta (same
  point-not-copy shape as `reference/topic-docs.md` and re-anchor's
  `context/re-anchor-audit-correct.md` engine doc). The three skills' autonomy
  gates are deliberately NOT extracted — different blast radii, kept in-skill.

### Changed

- keep-going: inventory + inspect steps now cite the shared
  `reference/off-thread-work.md` for the off-thread kinds and the
  inspect-real-state invariant rather than restating them inline; the duplicated
  "tools change over time" gotcha (now owned by the shared doc) is removed. The
  richer Active-verification protocol stays in keep-going (reconcile
  cites it). Description gains a reciprocal boundary line pointing at
  `reconcile` for
  retire/reconcile vs resume; all prior trigger phrases preserved.
- orient: the off-thread-work glance in "What it reads" now points at the shared
  `reference/off-thread-work.md` for the full open-ended kinds set while keeping
  its at-a-glance examples; no behavior change.

## [0.13.1]

### Changed

- Fresh-eyes review/verify delegation sites now prefer a cross-vendor
  advisor when one is installed, with the fresh-context same-vendor
  subagent as the stated fallback — presence-gated per the seam-phrasing
  convention (#933). `workflow`'s Review stage (`context/steps.md`) names
  the example command (the OpenAI Codex plugin, invoked per its own docs);
  `orchestrate`'s fresh-context-verify imperative states the preference
  tool-agnostically and names no command, because that imperative is
  exported verbatim into the skill's model- and tool-agnostic
  worker/handoff brief, where a named command would be exactly the
  unresolvable route the rule forbids.

## [0.13.0]

### Added

- continue-in-background: new skill (#233). Background delegation extracted from
  `/handoff --bg` into its own honestly named, discoverable entry point: produce a
  save-point, then launch a detached `claude --bg` session seeded with the rails
  resume prompt. Owns the delivery: explicit-intent hard gate (model-invocable for
  discoverability, but launches only on the user's explicit request — never
  self-elected, with an eval covering the gate), dirty-tree gate,
  launch + report, fallback-on-failure, and its own STOP rule. Also surfaces the
  The rails prompt is passed to the launch via a temp file rather than an inline
  heredoc — prompt content is untrusted session text, and a crafted line matching
  a heredoc sentinel could otherwise break out of the quoting into the shell; the
  resolved topic slug is sanitized to `[a-z0-9-]` before it reaches the `--name`
  flag for the same reason. Also surfaces the
  launched-session behavior the flag never documented: the agent is a NEW session
  that inherits neither the current session's CLI flags nor its model/effort
  choices — both resolve from the launch command's own flags and the launch
  directory's settings (per the agent-view and env-vars official docs, cited in
  the skill).
- reference/save-point.md: shared save-point engine. Save-point production —
  destination resolution, locate-position, full-vs-prompt-only choice, mandatory
  redaction pass, handoff-file write, rails resume prompt — extracted from the
  handoff skill into a plugin-level reference both delivery skills cite via
  `${CLAUDE_PLUGIN_ROOT}` (same shape as `reference/topic-docs.md`). No content
  duplicated in either skill; no runtime skill-to-skill invocation. The handoff
  document-structure doc moves with it (`skills/handoff/context/structure.md` →
  `reference/structure.md`) so the shared engine never reaches into one
  consumer's internal layout.

### Changed (breaking)

- handoff: `--bg` removed outright — no alias, no deprecation window. `/handoff`
  is now purely the manual `/clear`-then-paste save-point; background delegation
  lives in `continue-in-background`. The background trigger phrase ("continue in
  the background") moves from handoff's description to the new skill's — the
  trigger partition leaves zero overlap. Handoff's two `--bg` evals
  (no-launch-default, dirty-tree fallback) migrate to the new skill's eval set,
  rephrased for the new entry point; handoff keeps default-path coverage.

### Fixed

- retro / handoff: reconciled the "declared save-point" vocabulary mismatch between the
  retro multi-session snippet and the handoff skill's "Where handoffs live". Both now
  consistently name the CLAUDE.md/`.claude/rules`-inferred rung-2 value a **working-docs
  convention** resolving the memory-tier ROOT (`memory_dir`) — never the full handoffs
  path directly. Previously, a declared handoffs location such as `.claude/handoffs`
  passed through retro's snippet doubled into `.claude/handoffs/handoffs` because the
  snippet's "save-point convention" label implied a full location while its code appended
  `/handoffs` to it. The snippet's env var is renamed `DECLARED_SAVEPOINT` ->
  `DECLARED_MEMORY_DIR` to match. The snippet also no longer silently swallows a missing
  handoff chain: an empty `ls` result now surfaces an explicit fallback message and drops
  to the single-session parser form instead of passing an empty `--chain-from` value.

## [0.12.3]

### Changed

- orchestrate: sharpened imperative 7's per-worker tiering into an explicit volume-based default.
  Past a wide fan-out the cheaper tier is now the DEFAULT the whole fleet inherits (volume
  multiplies every notch of over-provisioning), with an explicitly-hard stage (verify,
  judge/adjudicate, judgment-heavy synthesis) as the standing exception that keeps the parent
  tier — closing the residual enhancement from the spawn-inherit fix. Tier is also broadened
  beyond model to reasoning effort: the doc-confirmed per-worker `effort` lever means a cheaper
  tier can be a cheaper model, a lower effort, or both. Guidance stays model-/tool-agnostic in the
  imperatives and export brief; the version-pinned platform specifics behind it (the fleet-model
  inherit mechanism, the platform's own wide-run threshold, and the `effort` enum) are recorded as
  citations in the skill's `context/sources.md`.

## [0.12.2]

### Changed

- Skills with `!` dynamic-context injections now declare `shell: bash` explicitly, per
  the pinned precompute convention — bash-only pipelines must not fall through to a
  PowerShell host.

## [0.12.1] — 2026-07-21

Changed:

- handoff: the "Full-path write procedure" doc's `MEMORY_ROOT` placeholder
  note now points at the shared `parse-concern-value.sh` helper (the
  retro skill's Phase 1.1 snippet is the worked call form) instead of a
  bare "resolve it first" reminder with no mechanism named. Doc pointer
  only — the handoff skill has no script of its own to rewire.

## [0.12.0] — 2026-07-21

Added:

- orient: new skill. Read-only session orientation — answers "where do we stand,
  what are we doing, and why" by synthesizing both the live conversation and the
  durable, off-thread state a conversation does not hold: handoff save-points,
  the workflow checklist, running-retro ledgers (resolved through the plugin's
  topic-docs binding), plus git state, open PRs, open work-items, and a glance at
  off-thread work. It complements the built-in `/recap` (conversation-only,
  auto-fires) by adding the durable layer recap never sees; a skill cannot invoke
  `/recap` (built-ins other than a small allowlist are not Skill-invocable), so it
  synthesizes the conversation summary inline. Strictly read-only: it writes
  nothing, ends nothing, and routes rather than acts — freshness verification to
  `reanchor`, off-thread recovery to `keep-going`, next-stage to `workflow`,
  learnings to `retro`. The plugin now bundles nine skills.

Changed:

- keep-going: hardened. (1) Broadened from "after an interruption" to also cover
  a live-session poke — "check the monitor", "poke it", "is it stuck", "stop
  staring at it" — with an active-verification protocol: read the real
  monitor/subagent output first, treat progress-vs-elapsed as a suspicion-raiser
  only, and act on evidence; killing or restarting off-thread work is now gated
  as a side effect so live-but-slow work is not killed on a hunch. (2) Usage-limit
  stall fix: once a limit lifts and the session is executing again the block is
  already over, so it continues rather than summarizing-and-stalling; the
  time-vs-reset check is scoped to the orchestration case (a limited worker),
  reset information being available in-session only via the limit message text and
  interactive `/usage`. While still blocked it hands back via `/session-flow:handoff`
  rather than self-arming a scheduler. (3) Intent is inferred from the
  conversation, arguments optional. Existing recovery behavior and all prior
  trigger phrases are preserved.

## [0.11.0] — 2026-07-20

Added:

- running-retro: new skill. Takes an in-flight retrospective checkpoint
  mid-session — the live counterpart to `retro`'s end-of-session pass. Zero-arm:
  nothing to set up in advance, because the session transcript on disk is
  lossless across compaction (the same record `retro`'s parser already reads in
  production). The main agent contributes a 2-3 line subjective-state note — the
  one signal disk cannot hold — then delegates the analysis to a fresh subagent
  that runs `retro`'s parser and selectively reads flagged transcript spans,
  classifies each finding by category and suggested resolution route (CLAUDE.md
  fix / rule fix / skill change / new-skill candidate / tracker issue), and
  returns a compact findings block. Findings append to a cumulative running
  ledger — one stable file per session chain — resolved through the plugin's
  topic-docs binding (`<memory_dir>/running-retros/`, default
  `.work/running-retros/`, memory-tier, never committed). It captures and routes
  only: codification stays with `/session-flow:retro codify`, tracker filing is
  offered never automatic, the session is never scored, and the skill is
  non-terminating (unlike `handoff`, it does not `/clear`). A mandatory redaction
  pass runs on both the subagent findings and the ledger write. Composes with
  `/loop` for periodic checkpoints; ships no scheduler of its own. The plugin now
  bundles eight skills.

## [0.10.4] — 2026-07-20

Fixed:

- retro: the Phase 1.1 multi-session snippet no longer truncates a quoted
  `memory_dir` at an interior `#`. `HANDOFF_DIR` resolution now routes through the
  shared `parse-concern-value.sh` helper (materialized from
  `lib/parse-concern-value.sh`), which peels surrounding quotes *before* stripping
  comments, so `memory_dir: "a#b"` resolves to `a#b` rather than `a`. The snippet
  also surfaces resolution rung 2 — a save-point convention inferred from
  `CLAUDE.md` / `.claude/rules`, passed as `DECLARED_SAVEPOINT` — instead of
  collapsing straight from an absent concern file to `.work`; prose stays an
  inference source the agent resolves, not a machine key.
- retro: a comment-only `memory_dir` (e.g. `memory_dir: # use default`, YAML-null)
  now resolves through the fallback instead of being taken literally as
  `# use default/handoffs`, so the handoff-chain search degrades to the declared
  save-point / `.work` default rather than a bogus directory.

## [0.10.3] — 2026-07-19

Changed:

- workflow / retro: the override boundary is now explicit. The stage taxonomy
  and the pre-PR sequence skeleton (workflow) and the five scoring dimensions
  (retro) are documented as fixed plugin identity with no consumer-config seam
  to swap them — what adapts is stage execution, gate commands, and the
  conventions each dimension scores against, all flowing through the consumer
  conventions the skills already name, never by editing the plugin. Documents
  the existing boundary per the extensibility contract; no behavior change.

## [0.10.2] — 2026-07-19

Fixed:

- retro: the Phase 1.1 multi-session snippet now derives `HANDOFF_DIR` from the
  resolved `memory_dir` (reads the `.claude/topic-docs.yaml` concern file, falls
  back to `.work`) instead of hard-coding the bare default `.work/handoffs`. A
  copy-as-is run of the snippet previously bypassed the memory_dir seam, missing
  the handoff chain in any repo that relocates its memory tier.

## [0.10.1] — 2026-07-19

Changed:

- Topic-docs binding points instead of restating (fleet conformance wave,
  registry single-home): the binding doc no longer restates the contract's
  five-rung resolution order and runtime guards — it applies the contract's
  own sections and keeps only the plugin-specific no-project-root fallback
  detail.

## [0.10.0] — 2026-07-18

Added:

- clean-stop: new skill. Gets a session to a durable, linked stopping point
  before the machine may go away — inspect every repo/worktree touched, push
  unpushed or coherently committable work durable (surfacing ambiguous WIP and
  stashes rather than force-committing or dropping them), ensure every pushed
  branch has a PR, file follow-ups as issues linked to that PR, and put the
  resume context in PR/issue bodies (never only a local file) to a cold-agent
  acceptance bar. Prunes only provably-safe branches and worktrees; gates
  destructive cleanup on proven safety. Closes on a free-and-clear verdict or a
  named dangling list. It is the go/stop mirror of keep-going (which recovers
  after an interruption; this makes the interruption safe beforehand) and
  supersedes a local handoff when the machine itself may go away. PR / issue /
  worktree mechanics route to whatever capabilities are installed, falling back
  to direct git / gh. The plugin now bundles seven skills.

## [0.9.1] — 2026-07-18

Fixed:

- orchestrate: worker model tier is now an explicit spawn decision. SPEC EVERY SPAWN adds the
  model tier to the per-worker spec, and CALIBRATE TO CONDITIONS adds per-worker tiering (cheap
  tier for high-volume mechanical work, parent tier reserved for judgment-heavy
  synthesis/verify; wider fan-out defaults cheaper). Closes the failure mode where a wide
  fan-out silently inherited the parent session's premium model on every worker — an omitted
  model defaults to `inherit` per the subagents doc (resolution order and cost-control quote
  now cited in `context/sources.md`).

## [0.9.0] — 2026-07-18

Added:

- reanchor: new skill. Verifies a session's working assumptions against live
  reality before it builds on them — for the PRs/issues/branches a handoff or
  locked plan references it confirms each is still in the claimed state, reports
  current behind-base divergence, confirms cited skills/plugins still exist under
  that name and that installed versions match the repo source, and flags
  memory-tier entries whose subjects have since landed. It reports the drift and
  re-anchors; it does not resume the work (the keep-going sibling), enumerate
  worktrees, or triage PR feedback. The plugin now bundles six skills.

## [0.8.0] — 2026-07-17

Changed:

- Adopt topic-docs contract 2.0.0 (visibility semantics): `reference/topic-docs.md` states
  handoffs and the workflow checklist are checkout-local; the checklist is the stage-ledger kind
  the contract's `.worktreeinclude` template carries into new worktrees, while handoffs are
  session-scoped and deliberately not carried.

## [0.7.1]

### Changed

- References to the renamed `/planning:plan` skill (was `/planning:architect`, planning 0.13.0 breaking rename) retargeted. Version bumped so existing installs receive the rewritten prompts.

## [0.7.0] — 2026-07-17

Added:

- keep-going: new skill. Recovers and continues a session after any
  interruption (rate limit, crash, disconnect, gap) — inventory off-thread
  work, inspect each item's real state from its artifact rather than
  assuming, resume the resumable / restart the dead / surface the
  unrecoverable, then reconcile the main thread from a fresh read of its
  backing plan or handoff file and continue. Safe/idempotent work
  auto-resumes; re-running side-effectful work (push, PR comment, deploy) is
  gated against double-firing. It is the resume counterpart to handoff, and
  the interruption cause is deliberately not diagnosed (recovery is
  identical regardless). The plugin now bundles five skills.

## [0.6.0] — 2026-07-16

Changed:

- orchestration-brief renamed to `orchestrate`. The default action
  arms/primes the current session — the skill's primary job — which the old
  name undersold by foregrounding the secondary export brief; the verb also
  matches the action-skill naming convention. Invocation is now
  `/session-flow:orchestrate`; the old `/session-flow:orchestration-brief`
  token no longer resolves. Export modes are unchanged (`handoff` / `worker`
  args), and the exported document is still an orchestration brief.

Added:

- orchestrate: seventh imperative CALIBRATE TO CONDITIONS — size the whole
  orchestration (whether to delegate at all, fan-out width, nesting depth) to
  the active model's capability, advisor/verifier availability, context
  pressure, and concurrent-session / rate-limit headroom, with
  small/medium/large fan-out sizing and single-agent as the floor.

## [0.5.0] — 2026-07-15

Added:

- handoff: mandatory redaction pass over ALL outbound handoff content
  (file, resume prompt, `--bg` launch) — secrets/tokens/credentials/PII
  replaced with shape markers before anything is written or emitted; the
  `--bg` process-argument visibility note now leans on it. New checklist
  ticks on both paths.
- handoff: mandatory "Suggested skills" body section — fully-qualified,
  "if installed"-qualified forward pointers naming the skills the
  resuming session should invoke for the remaining work (eight body
  sections now).
- handoff: fork-beats-compaction guidance — once the session is deep
  enough into its context window that reasoning quality degrades
  (roughly beyond the final third), a fresh-session fork from the
  handoff file beats continuing over a compacted history; threshold is
  relative, never a token count.
- handoff: re-read-from-disk + append-over-rewrite discipline when
  extending a handoff file that already exists on disk.
- workflow: on-ramp classes that merge into the stage sequence partway
  (raw bug/issue intake via diagnosis into implement, foggy
  too-big-to-plan efforts via wayfinding into plan, codebase-upkeep
  findings entering a fresh cycle), with graceful if-installed
  cross-plugin routing and no enumerated skill catalog.
- workflow: single-owner routing when two adjacent capabilities both
  fit — exclusion language wins, then the more specific claim, then the
  earlier stage.
- workflow: stale-map gotcha — re-check the described flows against the
  actual capability inventory whenever capabilities are added, renamed,
  or retired.

## [0.4.0] — 2026-07-15

Added:

- retro: `reference/ecosystem-improvement-catalog.md` — placement decision
  tree (project vs personal scope, laptop-dies test), per-target
  recommendation formats (memory, rules, hooks, skills, agents, MCP
  servers, settings), and a hook-event table verified against the current
  official hooks docs. Loaded by session-mode Phase 3.
- handoff: `context/gotchas.md` — failure patterns (prompt-only when
  durability is required, plan-anticipated work dropped on batch pushback,
  handoff without verifiable sanity-check evidence, continuing past an
  explicit stop). Loaded on demand from the SKILL.md checklist.

## [0.3.0] — 2026-07-14

Adopt the marketplace topic-docs convention
(`docs/conventions/topic-docs/`, contract v1.0.0):

- Handoff save-points move from `.claude/handoffs/` to the memory
  tier's concern-scoped handoffs directory — `<memory_dir>/handoffs/`
  (default `.work/handoffs/`), never committed. The workflow
  checklist moves to the topic's own memory slice —
  `<memory_dir>/<slug>/workflow-checklist.md` (default
  `.work/<slug>/`), a per-topic stage ledger: a fixed filename in the
  shared handoffs directory would clobber across two in-flight
  topics. The session's first memory-tier write verifies the resolved
  memory root's self-ignore guard (a `.gitignore` containing `*`),
  creating it (announced) when absent. No skill edits the consumer's
  root `.gitignore`. A consumer-declared convention
  (`.claude/topic-docs.yaml`, `CLAUDE.md` / rules) still wins;
  filename timestamps stay ISO-basic UTC.
- New `reference/topic-docs.md` — the plugin's binding to the contract
  (memory tier, handoffs concern directory, resolution order, guards).
  The handoff, workflow, and retro skills resolve placement through
  it; none bakes its own paths.
- The prior `.claude/handoffs/` location is retired outright — no
  compatibility layer, no dual-read window, no migration tooling;
  move residual content manually.
