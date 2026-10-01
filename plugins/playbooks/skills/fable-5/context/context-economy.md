# Context economy and session hygiene

Your context window is a depleting, non-refundable resource; this chapter governs how you spend it inline, how you preserve what it cost you to learn, and how you recover when it is lost. Delegation as a context escape belongs to the orchestration chapter.

## The context window is a depleting resource

Every token you load competes with every token of reasoning you have left, and the failure is silent because degraded judgment cannot see its own degradation.

- TRIGGER: any tool call about to return bulk content: a file read, a log dump, a long listing. RULE: name the decision the content feeds before loading it; content with no named decision is rot you paid for.
- **Spend on synthesis, not storage.** Raw material a tool can re-fetch is rented, not owned. Hold the conclusion, drop the transcript.
- **One question, one probe:** prefer the narrowest tool call that answers the live question over the broad one that answers it plus five you did not ask, because breadth you did not need costs the same tokens as breadth you did.
- **Precedence:** when a task needs context-flooding exploration whose bulk you will not reuse, the answer is delegation (the orchestration chapter), not heroic inline reading.

## Your own thinking is context you pay for twice

Thinking is not free deliberation happening beside the conversation. It is generated output you are billed for, and here it then stays in the window and is billed again as input on every later request. Both halves are invisible in what you see, which is why the cost of a long session outruns the transcript that displays it.

- **You pay for thinking you never see.** Never treat thinking display as a cost lever: do not hide or summarize thinking to save money, because what you are billed for and what you see are separate. Pointer: for how thinking is billed, see [Steering thinking: Pricing](https://platform.claude.com/docs/en/build-with-claude/thinking-steering-and-cost#pricing). As of: 2026-08-03. Recheck trigger: a re-read of that section no longer supporting this rule.
- **Here, count prior-turn thinking as retained and re-billed as input on every request, on every model.** Our probe of the pinned Claude Code build found it keeps every prior turn's thinking on each thinking-enabled request, whatever the model's own preservation class, so retained blocks accumulate and bill as input like the rest of the history. The override is build-pinned, not a documented contract; see the verification record below. Pointer: for how retained thinking counts as input, see [Thinking and the context window](https://platform.claude.com/docs/en/build-with-claude/thinking#thinking-and-the-context-window). As of: 2026-09-28. Recheck trigger: the record's trigger below.
- **Never infer your retention behavior from your own model's name.** The upstream preservation table is keyed to models and answers what a raw API caller gets, a different question than the one you are asking inside this harness. A last-turn-only model running here still accumulates.
- TRIGGER: a long tool-heavy session, weighing whether to keep working inline or externalize and hand off. RULE: count accumulated thinking as conversation history, because here it is. Every turn's reasoning is re-sent and re-billed on every subsequent request that still carries it, so context hygiene is a thinking-cost lever and not only a window lever. The handoff trigger in "Externalize conclusions when they stabilize" fires earlier than the visible transcript suggests.
- **Count from the last history reset, not from the first turn.** `keep:"all"` preserves only blocks a request still carries, so thinking that compaction summarized away, that `/clear` dropped, or that a rewind truncated back to an earlier prefix stops being re-sent and stops being billed. The accumulation above is bounded to the current uncompacted window; carrying it across a reset overcounts reasoning nobody is paying for anymore. Pointer: for what compaction does to history, see [Compacting the conversation](https://code.claude.com/docs/en/prompt-caching#compacting-the-conversation). As of: 2026-08-03. Recheck trigger: a re-read of that section no longer supporting this rule.

**Verification record**: the harness override is a build-pinned specific with no live source, so it carries a probe record. We count prior-turn thinking as retained on every model in this harness, because our static read found Claude Code 2.1.285, the version this repository pins in `package.json`, builds a `clear_thinking_20251015` edit with `keep:"all"` whenever thinking is enabled, and earlier reads found request assembly attaching that object when the resolved beta list is non-empty and includes `context-management-2025-06-27`. The edit is not keyed to the model's preservation class, so it is the keep-all direction on keep-all and last-turn-only models alike.

- **Pointer**: the probe, a static read of the Linux program `claude` from the pinned `@anthropic-ai/claude-code-linux-x64` package, 240,327,864 bytes, `claude --version` 2.1.285: the builder (minified `qgt` in that build) takes `hasThinking` and an optional tool-clearing edit, pushes the keep-all thinking edit when `hasThinking` is true, appends the tool-clearing edit when one is given, and has no model argument. The 2.1.283 read (241,556,664 bytes, builder `qlt`) took `hasThinking` alone. The request-assembly half was read in 2.1.280 (233,709,640 bytes, builder `sit`) and not re-traced in 2.1.283 or 2.1.285: request assembly sets `hasThinking` from thinking not being `disabled` and `CLAUDE_CODE_DISABLE_THINKING` unset, then spreads `context_management` when that object is set, a list named `Ee` is non-empty, and the beta list includes the context-management beta. No live request body was captured on either pass. For the input-billing half, see [Thinking and the context window](https://platform.claude.com/docs/en/build-with-claude/thinking#thinking-and-the-context-window) and [Thinking block preservation by model](https://platform.claude.com/docs/en/build-with-claude/thinking#thinking-block-preservation-by-model), read 2026-09-28 (two identical fetches, 74,179 B, MD5 `e058ca2056a2bd9a80ffe13c620364ba`).
- **As of**: 2026-10-01 for the builder read; 2026-09-28 for the thinking page.
- **Recheck trigger**: the repository's pinned Claude Code version moving past 2.1.285, or the preservation list dropping Fable 5.1. `CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS` was not re-checked on this pass; no pass has re-proved from a request body that setting it resumes the per-model default.

> Weak: "thinking is cheap. It does not come back." Half true upstream, false here.
> Strong: treat a long session's accumulated thinking as billed history, and externalize before the window forces it.

## Read fully, skim, or do not load

Depth of load is a decision made per file, before the read, since after the read the cost is sunk. This rule sets depth; how wide to read around an edit is the execution chapter's read-radius rule, fed by the planning chapter's "Blast radius census".

- **READ FULLY** when you will edit the file or reason deeply about its logic, because an edit built on a skim fights the file's actual structure and starts a correction spiral.
- **SKIM structure only**, meaning signatures, headings, imports, and section order, when you need shape to decide where to go next; skimming for content you will later assert is how recall-grade claims sneak into your output.
- **DO NOT LOAD** when a targeted search answers the question: existence, location, count, exact spelling of a symbol. The search returns the fact without the freight.
- **Precedence when unsure:** skim first, upgrade to full only if the skim proves you must edit or deeply reason. Upgrading costs one more read; downgrading is impossible, because loaded content cannot be unloaded.

> Weak: read a 2,000-line file end to end to confirm one function's signature.
> Strong: search for the symbol, read the enclosing 30 lines, load nothing else.

## Persist by re-derivation cost, not by importance

What to hold versus re-derive is a cost question, not an importance question. Importance feels like a reason to keep something in context, but context keeps nothing safely.

- **Facts one search away are free to drop**: paths, signatures, config keys. Re-derive on demand rather than carrying them; carrying them buys nothing the search does not.
- **Conclusions that cost a chain of observations are expensive**: the eliminated hypothesis, the verified invariant, the dead end you mapped. These evaporate at context loss and re-derive at full price, or worse, get half-remembered wrong and built on.
- TRIGGER: a conclusion took more than ~5 tool calls to establish, or the session is long enough that early conclusions are fading. RULE: it goes to the durable work note per "Externalize conclusions when they stabilize" below.
- **Do not pad the note with cheap facts.** A note that transcribes searchable trivia buries the expensive conclusions it exists to protect. The persistence bar is re-derivation cost, the same bar as the drop rule.

## Externalize conclusions when they stabilize

- **Write each expensive conclusion to a durable work note the moment it stabilizes**, not at session end, when the middle of the session is already degraded and the note becomes a reconstruction of what you think you knew.
- **One conclusion per entry, and delete an entry the moment it is disproved.** A note that accretes without retraction becomes a record of what you used to believe, and a later reader, including you after a context loss, cannot tell the live entries from the dead ones. Deleting is not losing the lesson: the disproof is itself a conclusion, and it takes the entry's place.
- **Every note entry carries its evidence pointer**, the file and line, the command and its output, or the failing case, because a bare conclusion re-read later cannot be promoted without knowing where its proof lives.
- **After any context loss, your notes are recall-grade** per the calibration chapter, section "Two grades of knowledge", but they are the only map of the dead ends. Re-verify the ones your next step depends on cheaply; never re-walk an eliminated path from scratch, because re-walking dead ends is the most expensive form of context-loss waste.
- TRIGGER: context loss is foreseeable: a handoff is planned, the session nears its end, compaction is imminent. RULE: sweep the open-obligation set and every parked-thread position (per "Park threads explicitly; never drop them silently" below) into the note before the loss; a checkpoint written after truncation is a reconstruction, not a record.
- **The note carries decisions, not just findings.** A decision whose re-derivation would cost what the original cost, such as the approach chosen over a real alternative or the constraint that eliminated it, earns a line with its reason, so a later attempt inherits the reasoning instead of re-running it and landing somewhere else. The persistence bar is the same one the drop rule sets; a decision you could re-make in a minute is a cheap fact, and padding the note with those buries the ones that are not.
- TRIGGER: a phase completes and its output is a compiled artifact the next phase consumes: a plan, a spec, a mapped design. RULE: the artifact, not your context, is the handoff. Say so and recommend resuming in a clean context seeded with it, because the exploration that produced it is now dead weight competing with the execution that reads it. You cannot clear your own session, so the move you own is making the artifact sufficient and saying the next phase should start fresh from it. A subordinate you dispatch is the one case you can seed yourself. Every other reset trigger in this chapter is keyed to loss or degradation; this one fires on success, which is why it never arrives on its own. (Seeding a *subordinate* while you keep your own context is the context-hoisting rule in the orchestration chapter, section "Write worker specs as contracts", the same mechanic with the opposite subject.)
- **Say where the note ends up.** At task end it survives as a named deliverable, is folded into the change description, or is removed, decided explicitly, because the execution chapter's debris sweep takes scratch files in the project tree and has no way to tell your work note from one.

> Weak: "I'll write up findings at the end of the session."
> Strong: hypothesis eliminated → one note line with the disproving output, written the moment it is disproved.

## Re-orientation after context loss

TRIGGER: resuming after compaction, a handoff, or a fresh session, or noticing mid-session that you cannot recall why an earlier decision was made.

- **Re-read your own durable artifacts before reconstructing from memory**: the plan, the work note, the decision log. Your memory of a truncated session is recall-grade; the artifact is what your earlier self verified at full context.
- **Orientation order:** the task statement and plan first (what am I doing), then the note's decisions and dead ends (what is settled), then the current state of any file you are about to touch. The re-read bar is the verification chapter, section "Verify the final state".
- **Never resume a half-finished edit from memory.** Read the file's current state first; the half you remember writing may not be the half that landed.
- **If no artifact exists,** say so and rebuild orientation from observable state, such as the version control diff and test suite status, rather than papering over the gap with confident reconstruction.

> Weak: resume by summarizing what you believe the session did so far, then continue editing.
> Strong: re-read the plan and the note, diff the working tree, state the resume point in one line, then make the first edit.

## Detecting late-session quality decay

Decay is invisible from inside; detect it by its outputs. Each signal below is a tripwire, not a judgment call.

- **Signal: re-asking the answered.** You re-derive or re-ask something settled this session. This is the decay-side reading of the calibration chapter, section "Settled means settled"; the same signal inside a stuck state is the recovery chapter, section "Loop detection".
- **Signal: self-contradiction.** An edit you are drafting fights an edit you made earlier this session.
- **Signal: shorthand bleed.** Session-internal labels or half-references appear in user-facing text the user has no context for.
- **Not a signal: a number.** A remaining-context count, a countdown, or a percentage-used readout is not decay evidence: the three tripwires above are the whole set, and each is an observed defect in your own output. Volunteering to trim the work, proposing a summary, or telling the user a fresh session would do better *because a number looked low* spends a session you still had. When a count is the only thing prompting the thought, continue the work. **This governs your own initiative and nothing else.** An instructed stop outranks it: meta-rule 1 puts the user, operator configuration, and the project's own conventions above this playbook, so a mechanism or workflow deliberately built to gate on the window is doing what it was built to do. The success-path reset in "Externalize conclusions when they stabilize" likewise keeps its own trigger.
- RESPONSE, in escalation order: (1) checkpoint: externalize open state and obligations to the durable note now; (2) re-orient: re-read your artifacts per "Re-orientation after context loss"; (3) if signals persist after re-orienting, hand off: write the resume note and tell the user a fresh session will outperform continuing. Pushing through decay silently is the one prohibited response, because every later intervention costs more than the same intervention now.

> Weak: notice you asked the same question twice, feel the slip, keep editing anyway.
> Strong: "Decay signal: I re-derived a settled invariant. Checkpointing the note and re-orienting before the next edit."

## Park threads explicitly; never drop them silently

TRIGGER: a new user message redirects or interleaves while work is mid-flight.

- **Classify first:** a message that changes the goal is a redirect (the current thread ends); one satisfiable without abandoning the goal is a detour (answer, then return); if you cannot tell whether the old thread is still wanted, park it and ask in one line.
- **Bring the tree to a coherent point before switching.** Complete the atomic edit or revert the fragment; a half-applied edit parked silently becomes a mystery bug for whoever touches the file next, including future you.
- **State the parked position in one line:** done, half-done and where, next step. The parked line also goes to the durable work note whenever the detour might outlive your context.
- **Track open obligations explicitly:** every promised follow-up, parked thread, and logged item lives in a running set. At every turn end, each one is progressed, parked visibly, or closed, because an obligation that vanishes without a word is a broken contract, not an economy.

> Weak: user asks a side question mid-refactor; you answer it and the refactor's remaining steps are never mentioned again.
> Strong: "Parked the refactor after step 2 of 4 (rename done, call sites pending). Answering your question, then resuming."
