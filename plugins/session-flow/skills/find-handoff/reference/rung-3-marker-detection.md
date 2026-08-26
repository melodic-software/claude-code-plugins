# Rung 3: marker detection over candidate tails

Rung 3 of the recovery ladder in [`../SKILL.md`](../SKILL.md), reached only when rung 1's
known-location glob produced no candidate that cleared the bar and rung 2 has ranked the transcript
candidates. Read-only throughout, like every rung. A run that resolved at rung 1 never executes any
of it.

Scan the tail of each candidate transcript for the contract signals the hub's contract-signals
section names. **Accept hits only from assistant text output**, in two stages:

- *Cheap same-line pre-filter:* each transcript event is one physical JSONL line carrying its
  own role field, so drop any matching line that does not also contain `"type":"assistant"`, a
  substring check, no parsing. Rails in a user message or a tool result (a pasted sample, a doc
  echoed by a read) are not a handoff emission.
- *Confirm on the per-candidate decode:* when un-escaping the surviving line (below), verify
  **both** that the decoded event's top-level `type` actually equals `assistant` (the
  pre-filter is only a substring, a user message *quoting* transcript JSON or docs contains
  the literal `"type":"assistant"` and would pass it) **and** that the marker sits in a
  `message.content` entry whose own `type` is `text`. An assistant
  `Write`/`Edit` call serializes its file content on an assistant line too, so a `tool_use`
  input carrying rails (writing a doc or fixture) is not assistant-visible output and not a
  handoff. This decode is per-candidate, a handful of lines, never a bulk parse.
- **File mode**. Match the `Read @…/handoffs/<TS>-handoff-<topic>.md` directive. **Filter out
  the template placeholder:** a match containing the template's own placeholder tokens
  (`<handoffs-dir>`, `<TS>`, `<topic>`) is the `save-point.md` doc being read into some
  session's context, not a real handoff. Keep only concrete paths. Then confirm the referenced
  file exists on disk, **by the directive's path form**:
  - **Rooted directive** (the current producer shape). Check the absolute path as given. No cwd
    is involved, so nothing can resolve it against the wrong root. **A rooted path can still
    miss**, and for a reason the rootless form does not have: an absolute path is machine-local,
    so a resume on a different machine or a different checkout of the same repository finds
    nothing there. That is exactly the case the producer emits `Handoff origin:` for, so on a
    rooted miss, read that line and re-resolve its repo-relative path against the repository it
    names; a hit there surfaces the recovered file normally, and only if that re-resolution
    ALSO finds nothing does the candidate fall through to the shared rule below. Never treat a
    rooted miss as absence: it is the same not-found-here condition, reached from the other
    direction.
  - **Rootless directive** (every handoff written before the producer rooted its path).
    **resolve it against the source transcript's `cwd` field, not the current session's cwd**. A
    handoff recovered from another repo's transcript is otherwise falsely reported missing when
    checked from here. These blocks carry no `Handoff origin:` line: it shipped with the rooted
    form, so nothing older than that has one.
  - **A path that resolves to nothing, rooted or rootless, is UNRESOLVED, never dropped.**
    Neither resolution is proof of absence. The rootless one is an inference: it assumes the
    producer's cwd *was* the repository it wrote into, which is the very assumption that loses
    the handoff when a session works in a repo that is not cwd's project root. The rooted one is
    a machine-local literal that a different machine or checkout cannot satisfy. Either way,
    discarding the candidate throws away a directive that names the right filename and is the
    strongest evidence in hand. Keep it, carry the filename plus whichever path form was tried,
    and surface it at step 4 marked UNRESOLVED. Before doing so, spend one bounded, read-only
    widening: glob that filename under the **verified repository roots** already in hand, the
    current repo, and the repository named by any `Handoff origin:` line. **A candidate
    transcript's `cwd` earns a place in that set only once it is confirmed to BE a repository
    root**. `git -C <cwd> rev-parse --show-toplevel`, and glob under the top level it prints
    rather than `cwd` itself. A session launched from a home directory records that home
    directory as its `cwd`, so globbing under an unverified `cwd` is a recursive sweep of most
    of the user's files: the machine-wide scan this rule forbids, reached by accident rather
    than by intent, and slow enough to time the recovery out. A `cwd` with no git top level
    contributes no root, the candidate stays UNRESOLVED and step 4 asks the operator which
    checkout to look in, which is the honest answer when nothing in hand can name one. Promote a
    single unambiguous hit to a resolved candidate. Two or more hits stay UNRESOLVED with the
    matches listed; the operator picks. Never widen into a machine-wide filesystem sweep.

  **Apply step 1's background-delivery screening to these candidates too**, the launch
  signature, if any, sits in this same transcript: a file whose exact directive a verifiably
  successful `claude --bg` launch (step 1's definition) delivered is not a lost handoff, wherever
  it was discovered.
- **Prompt-only mode**, no file, no directive. Detect off the `─` rails and the instruction
  line; the resume content is the block inline between the rails. `Prior session:` is
  **optional corroboration, never a required key**, the producer's prompt-only checklist
  requires only a self-contained prompt between the rails plus the copy instruction, so
  requiring it would skip valid handoffs. **Apply the same placeholder filter as file mode:** a
  block still carrying the template's own placeholder tokens (`<handoffs-dir>`,
  `<TS>-handoff-<topic>`, a literal `Prior session: <UUID>`) is the `save-point.md` template
  read into some session's context, not a real handoff. Match those **specific tokens only**,
  never a blanket no-angle-brackets rule: a valid prompt legitimately contains other
  angle-bracket text, notably the redaction shape markers the producer deliberately emits
  (`<REDACTED: API key>`) and generic code syntax (`<T>`). When a `Prior session:` line is
  present, its value must be a concrete session UUID. **Screen delivered continuations here
  too:** `continue-in-background prompt` emits this same rails block as assistant text and then
  delivers the inline prompt to the agent it launches. Check the same transcript after the
  block for a verifiably successful `claude --bg --name "continue-…"` launch (step 1's
  definition: transcript evidence the agent appeared, not exit-0 alone). **Bind the launch to the
  block by content, never by ordering alone:** the producer writes the exact launched prompt to
  a temp file (visible in the same transcript as the Write preceding the launch), a launch
  excludes only the block whose content it delivered; a later launch of a *different* prompt
  never disqualifies an earlier manual block in the same transcript. A delivered block is not a
  lost handoff; exclude it and keep scanning. **Resolve the continuation's current state through
  step 1's four-way rule before excluding** (`claude agents --json --all`, keyed on the
  launched `sessionId` where the transcript recorded one): live and completed both exclude,
  the first because the work is running, the second because it is already done, while a
  non-completion terminal state, or absence even from `--all`, keeps the block. Absent from the
  bare active list is never on its own a failed continuation.
- **Capture the below-rail `/loop` re-arm entries, every mode, every discovery path, every
  loop.** Once a candidate qualifies on the signals above, also take the re-arm instructions the
  producer emits below the bottom rail. **Read the `Re-arm <i> of <n> — <L> lines:` headers and
  take the next `<L>` lines verbatim** (save-point.md "Loop-aware re-arm"). The next header
  begins where the previous entry's `<L>` lines end; repeat until `n` entries are held. Anchor
  the search to the bottom rail, never "the lines after the rail" unbounded, which would widen
  this skill into the raw-transcript dump it forbids.

  **Match on the length, never on the content.** The three ways this capture has been got wrong
  are all the same mistake. Bounding a verbatim region with a content test:

  - **Command wording** ends the entry at the first continuation line of a multi-line prompt,
    cutting it in half and losing every entry behind it.
  - **The next header** looks safe until a prompt quotes one. The prompt is reproduced exactly as
    the operator typed it, so a prompt containing the literal text `Re-arm 2 of 3` would split
    its own command. Any sentinel has this flaw; a line count does not.
  - **Stopping at the first hit** recovers one of three re-arms and drops two schedules while
    looking like it worked.

  Read `<L>` as a literal count. `lines` never inflects, so `1 lines` is a well-formed header
  and not a shape drift.

  `<n>` is the self-check, not the scanner: recover all `n`. Finding fewer, or an `<L>` that runs
  past the end of the message, means the transcript is truncated or the shape drifted. Surface
  what was found and say `n` were expected, rather than presenting a subset as the whole.

  **This is a capture, never a detection
  key:** it is taken only from an already-qualified candidate, so it cannot admit a candidate
  the rails markers rejected. No header at all → the session was not looping; surface nothing extra.
  **Do not add the note's placeholder tokens to the template-rejection list.** Unlike the rails
  template, the producer *really does* emit `<interval>` and `<the prompt you originally
  launched it with>` verbatim on its no-launch-signal branch, under a `Re-arm <i> of <n> — <L>
  lines:` header like any other entry (save-point.md "Loop-aware re-arm"), so rejecting on them would discard a
  genuine note; a transcript that merely read
  `save-point.md` is already rejected by the existing rails-template filter.
- **Un-escape before surfacing.** Each transcript message is ONE physical JSONL line with its
  text JSON-string-escaped (`\n` for newlines, `\"` for quotes, `\\` for backslashes). A raw grep
  hit is that escaped blob. Decode it back to plain text (JSON-unescape the matched string)
  before surfacing, or the user sees a wall of `\n`/`\"` instead of the prompt. This matters most
  in prompt-only mode, where the whole inline block is what gets surfaced.
- mtime alone can never pick the winner (multiple sessions land within seconds of each other),
  the markers do.
