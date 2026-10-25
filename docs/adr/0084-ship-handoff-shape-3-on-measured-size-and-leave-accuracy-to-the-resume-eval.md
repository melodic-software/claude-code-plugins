# Ship handoff shape 3 on measured size and leave accuracy to the resume eval

- Status: accepted
- Date: 2026-10-24
- Related: [#9238](https://github.com/melodic-software/claude-code-plugins/issues/9238) (the
  hot-file and archive redesign). The harness and its cases are described in
  `plugins/session-flow/evals/resume-eval.md`; the shape-3 contract is in
  `plugins/session-flow/reference/structure.md`.

## Context

Session-flow handoffs only grow. An audit of 274 handoff files and 2,253 transcripts measured a
median growth of 6.4 to 7.0 KB per hop, and 0 of 108 lane hops shrank. Resumed sessions read only
part of a large handoff (a median of 22% of files above 256 KB), then miss rules, follow
superseded ones, or act on stale GitHub facts. Issue #9238 proposed a small hot file plus a
per-chain archive. The owner required that any change ship only as a measured improvement in
continuation accuracy at fewer tokens, against both today's skills and running without them.

No instrument existed to measure that. Plugin eval runs a bare session, but the audited failures
happened in full interactive sessions with the owner's instructions, hooks and plugins loaded, and
plugin eval cannot read a Codex session or a native `/compact`.

## Decision

1. **Measure resume accuracy with a committed harness.** `scripts/harness/resume_eval.py` seeds a
   synthetic session, has it write a handoff, a free-hand summary or a native `/compact`, and
   resumes it in a fresh Claude Code reader (the real setup, with the plugin copy under test) or a
   Codex reader. Action probes are graded from the reader's event log and text probes by a
   three-vote judge. Results are written in plugin eval's schema, so `noise-report.py --baseline`
   compares any two arms.
2. **Seven synthetic cases** cover the four audited drift patterns (skipped rule, superseded
   rule, stale GitHub fact, restated preference) and three design properties (archive-only answer,
   first split hop from a large predecessor, a five-hop chain). No case holds a real transcript.
3. **Ship shape 3 on its measured size.** `save_point.py new` writes a hot file in one fixed
   section order plus one immutable archive file per hop, holding every predecessor section
   verbatim. `validate` enforces the order, a byte cap and the lossless carry-over. Over the 17
   audited chains with three or more hops, the next hop's file falls from a median of 89,313 bytes
   to 9,377. The cap is provisional (10,000 tokens' worth), because the eval that would set it did
   not run.
4. **Leave continuation accuracy to the committed eval.** On 2026-10-24 the owner stopped the
   deciding runs to keep plan usage for higher-priority sessions. Shape 3 therefore ships without
   an accuracy comparison against today's handoff. Shape-1 and shape-2 files still read and
   validate, so a revert restores the old writer without touching existing chains. The instruction
   trims and the interview emoji fix stay deferred.
5. **Commit the harness as an owner exception.** AGENTS.md says to commit a harness only when
   something re-runs it (a CI lane, a schedule, a skill action), and nothing automated runs
   `resume_eval.py`. The owner decided on 2026-10-24 to commit it anyway, because it is re-run
   by hand: on the re-run trigger under Consequences, and for the owner-approved accuracy check.
6. **Leave the core's growth unbounded for now.** Original goal and Direction changes carry forward
   verbatim and never move to the archive, so the hot file grows by one trail line per change of
   direction. A hot file over the Read page cap (25,000 tokens' worth) fails `validate` whatever
   its core holds, so a long enough chain would fail with nothing the writer may move out. The
   56-hop `hop_chain.py --budget` projection stays at 16.4 KB, under the 24.6 KB hot-file cap. The
   owner decided on 2026-10-24 to defer a bound, such as keeping only the last trail lines in the
   hot file, to the pending accuracy runs.

## Alternatives considered

- **Hold shape 3 until the accuracy runs finish.** Rejected by the owner: the size gain is
  measured and the change is reversible, while the runs compete with the automation lanes for
  usage. The cost is an open question: the audit shows the failure, not that a hot file fixes it
  without losing accuracy.
- **Measure with bare plugin eval only.** Rejected for the decision: no reader sees the owner's
  instructions, and Codex and `/compact` cannot run in it. Bare plugin eval stays the regression
  instrument.
- **Run the full comparison now.** Stopped: the plan called for about 2,250 agent runs with every
  conditional step. Each real-setup run resends the owner's full startup context and the seeded
  session history on every turn
  ([what drives usage](https://code.claude.com/docs/en/costs#track-your-costs)), so the full
  comparison would have taken days of the plan's usage away from the lanes.

## Consequences

- The accuracy comparison is still to run. The owner-approved first step is 12 writer runs: three
  drift cases, two runs each, before against after at the 10,000-token cap, with both readers.
  `noise-report.py` needs at least three cases to give a verdict. Claude Code must read
  non-inferior at a 0.05 margin with no case drop, and Codex is reported as the improvement
  signal. The full plan's rule (10 runs per case, against each without-skills arm too) applies if
  the comparison is extended.
- Measured so far, from the before copy: the 25 existing session-flow plugin-eval cases pass 58 of
  75 runs with the plugin and 29 of 75 without (mean scores 0.89 and 0.67). The six session-flow
  skill-eval suites, converted into plugin-eval cases, pass at mean scores from 0.48
  (continue-in-background) to 0.89 (workflow). Five cases score 0 because the sandbox lacks the
  conversation or repository the prompt assumes, so they gate nothing.
- The judge agrees with every pass and fail sample of all 14 text graders (94 of 94). A first pass
  disagreed on 6 terse pass samples that omitted part of their criterion; those were relabeled and
  the criteria left unchanged. A fresh-context validity review mapped each drift case to its
  audited failure, after 4 blocking and 11 should-fix grading errors were fixed.
- The reproduction pilot ran too few runs to decide anything (2 to 9 runs per cell). In it, Codex
  failed the skipped-rule continuation probes in 3 of 3 runs while the Claude Code reader passed 20
  of 21 probes. That suggests the owner's own instructions, loaded in every real-setup run, carry
  part of the rule the handoff drops.
- Results are tied to the instrument: the plugin-eval sandbox denies writes above the case
  directory and reads of the plugin copy, and the same fence applies to every arm. The before
  handoff skill tried to write `.work/.gitignore` one directory above its working directory in 12
  skill-eval runs, a candidate memory-directory defect for the redesign to check.
- Open follow-up: decide the core-growth bound (decision 6) with the accuracy runs.
- Re-run the eval on any change to how session-flow writes or reads a handoff, and on a Claude
  Code release that changes compaction, Read or context behavior.
