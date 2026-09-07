# interview-async-round-restate

Issue: [#3923](https://github.com/melodic-software/claude-code-plugins/issues/3923)

## Brief

### TLDR

`/planning:interview` dispatches slow lookups without blocking the round, then prints a numbered
round and waits. Its only re-surfacing rule fires on a user reply, so an agent return, background
task notification, or team report landing before the user replies neither restores the displaced
round nor withdraws a recommendation it has just contradicted. Add one rule that fires on a
non-user event, keyed on relevance rather than arrival.

### Goal

A round that is still open stays trustworthy while out-of-band output arrives: the user can always
tell which questions remain, and never answers against a recommendation the session has already
disproved.

### Constraints

- Must not weaken the non-blocking dispatch rule (`SKILL.md:135`, `context/loop.md:66`, `:174`).
  The scoped barrier that already exists — only questions downstream of a running lookup wait — is
  the part that works and stays exactly as it is.
- Correctness may not depend on the model being woken by the async delivery. Upstream
  anthropics/claude-code#21048 documents that wake path failing and regressing across releases, so
  a restate on the user's next reply is the floor and a wake-triggered restate is the improvement.
- No new register status. `check-open-questions.sh`, its test, the digest-pinned status table, and
  `templates/checklist.md` stay untouched.
- `SKILL.md` is at 405 lines against a 500-line hard cap and an already-exceeded 200-line soft
  target, so the SKILL.md footprint is one sentence plus a pointer; mechanics live in `loop.md`.
- Every `pin_section` digest covering an edited section must be recomputed. `pin()` is `grep -qF`,
  so pinned *phrases* must survive verbatim; surrounding lines need not be byte-identical.
- Markdown only. No script, no schema, no behavior outside the skill's prose contract.

### Acceptance criteria

- [ ] A rule in `context/loop.md` fires on a **non-user event** — a subagent return, background task
      notification, agent-team report, Monitor firing, or subagent permission prompt reaching the
      transcript while a round is open.
- [ ] The rule names two outcomes. A return touching no asked question is announced in one line and
      the round stands. A return that contradicts a recommendation under an already-asked question
      forces an explicit restate of that question naming the superseded recommendation as
      superseded.
- [ ] A question the return now answers from the environment is resolved and stated, not left
      standing, consistent with "Facts are yours; decisions are the user's".
- [ ] Re-presentation shape is a compact pointer for untouched questions plus a full restate only
      for the changed one — never a full re-print of the whole round.
- [ ] The rule is surface-agnostic: no `AskUserQuestion` branch.
- [ ] `SKILL.md` carries one sentence plus a pointer beside the register rule, and stays under 500
      lines.
- [ ] `plugins/planning/tests/interview-defenses.test.sh` passes with recomputed digests for every
      edited section, plus one new `pin()` phrase pin defending the new rule.
- [ ] One new eval case, the async twin of the drift-check case, with the `pin_case_set` roster
      digest recomputed.
- [ ] `plugins/skill-quality` check passes on the edited `SKILL.md`.
- [ ] `planning` patch-bumped from 0.39.0 with a matching `CHANGELOG.md` section.

### Captured assumptions

- The relevance judgment ("does this return touch an asked question?") is a model judgment, not a
  mechanical one. This is deliberate: the alternative — firing on every arrival — is the
  unconditional re-presentation the evidence rejected.
- A displaced-but-valid round's rows remain correctly `open`, so the existing gate already refuses
  to lock a contract over them. The new rule addresses visibility, which the gate cannot grade.

### Out-of-scope

- A `finalize` action (Q&A recap plus procedure-walked validation). Net-new invention; its own
  issue and PR. See deferred question Q8.
- Adopting upstream's cosmetic `---` question separator (`85f83d3f`), and recording this session's
  re-fetch as-of line in `docs/upstream/aihero-course.md`. Both ride with the finalize PR.
- Confirming empirically whether a parked `AskUserQuestion` absorbs an arriving return into the
  same turn. Recorded as a gap in #3923; the surface-agnostic rule is correct either way.

### Deferred questions

None. Q8 (whether the `finalize` action ships here) was settled by the user: its own issue and its
own PR, sequenced after this one. It is recorded under Out-of-scope above rather than deferred.

## Plan

<!-- /planning:plan fills this section. -->
