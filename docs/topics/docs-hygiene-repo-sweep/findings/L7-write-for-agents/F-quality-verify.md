# L7 findings: `F-quality-verify`

Slice audited: 103 `AGENT` rows (31 `T2`). Predicates emitted here: P3.

## P3 · pointer does not front-load the leading word

### F-1 · `plugins/mutation-testing/skills/principles/SKILL.md:48` (T2, S2)

Verbatim:

> See [scaling-and-suppression.md](reference/scaling-and-suppression.md).

It closes the FAQ answer "Should we fail the build on a mutation score?", whose conclusion is
"Report it; do not gate on it." The pointer opens on the routing verb, so the reader matching on
"suppression" or "scaling" has to read the filename to find out the pointer is for them.

Replacement:

> Scaling and suppression mechanics: see [scaling-and-suppression.md](reference/scaling-and-suppression.md).

Predicate: P3. Severity S2, `T2` surface, routing only.

### F-2 · `plugins/testing/skills/run-e2e/context/e2e.md:35` (T3, S3)

Verbatim:

> **See `/playwright:playwright`** (when the playwright plugin is installed) for CLI mechanics — commands, sessions, snapshots, storage, tracing, network mocking, Windows quirks. This skill (`/testing:run-e2e`) owns the broader orchestrator + API + UI story.

This pointer covers its branches well (it names the condition, the payload, and the complement), so
it passes P4. It fails P3 only: the bolded leading token is the routing verb rather than the term.
Moving the emphasis fixes it without touching the content.

Replacement:

> **CLI mechanics** (commands, sessions, snapshots, storage, tracing, network mocking, Windows quirks): see `/playwright:playwright`, when the playwright plugin is installed. This skill (`/testing:run-e2e`) owns the broader orchestrator + API + UI story.

Note for the wave 3 editor: the em dash in the current line is inside this repo's own prose surface
and is separately in scope for `L5`/`ai-slop`. The replacement above removes it as a side effect.
Severity S3.
