# Gotchas — proposals that read as correct and are not

Observed failure modes for the placement audit. Every one of these produces a finding that survives
review by eye, which is why they are written down rather than left to judgment.

## The saving that is not a saving

- **"Move it to `.claude/rules/`" is not a saving on its own.** An unscoped rule loads at launch
  with the same priority as `.claude/CLAUDE.md`. The reflex to propose a file move because a file
  is long produces a reorganization billed as a context win. Only `paths:` changes the cost.
- **A rule whose body is just `@import` defeats its own scoping.** The import inlines at session
  start while the rule body defers, so the move reads as a saving and is not one. This is the
  opposite of a nested `CLAUDE.md`'s import, which *does* defer — the two must not be generalized
  from each other, because measurement says they behave differently.

## Globs

- **A glob that looks obviously right can match zero files.** `**/*.ts` in a repo that vendors its
  TypeScript, `src/**` in a repo whose source lives in `lib/`. Always run the validator; never
  reason about match counts from the directory listing in your head.
- **`over-broad` is not a validation failure, and `zero-match` is not a style nit.** They land in
  the same output column and mean opposite things: one is a judgment call the operator may
  legitimately overrule, the other is a rule that can never fire.
- **A `HINT` is what the prose literally said, not what the scope is.** The detector reports tokens;
  it does not know whether `.ts` is this candidate's real coverage. Derive, then validate.

## Classification

- **A section can be path-local and still be a safety rail.** "Never force-push a shared branch"
  names a git command and looks like it belongs with the git conventions. Gate 0 keys on
  consequence, not on subject matter. Ask what breaks when the line is absent at the moment it was
  needed.
- **Content about creating files fails path scoping even with a perfect glob.** The trigger is a
  read. Re-deriving the glob does not help, and the resulting rule looks healthy in every check.
- **The expanded corpus tier is mostly noise.** Design rationale, tutorials, and ADR narrative all
  mention conventions without being one. The normative-signal bar exists because promoting an
  explanation into a rule adds always-loaded cost and teaches nothing.
- **A promote candidate that duplicates a live human document is a drift seed.** The pointer variant
  exists for exactly this; reflexively copying the section is the easy wrong answer.

## Evidence

- **A line range you read rather than took from a `SECTION` record is a guess.** It will look right
  and excise the wrong text, and the diff lands in a file that steers the agent's behavior.
- **An empty detector result means "no sections found", which is itself suspicious.** A markdown
  file with headings that reports none is a detector problem, not a clean file — say so instead of
  reporting the file as having nothing to move. This exact shape shipped once: an awk regex the
  engine could not compile printed a panic to stderr and an empty fact set to stdout.
