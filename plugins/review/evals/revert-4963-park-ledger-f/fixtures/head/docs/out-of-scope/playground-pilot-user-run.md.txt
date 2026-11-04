# Playground pilot (user-run): operator checklist

## Decision

**Parked — operator-run; autonomous mandate declined.** This repository does not run the
playground document-critique plus Artifact clipboard smoke
([#3617](https://github.com/melodic-software/claude-code-plugins/issues/3617)). The item stays
user-reserved. An operator who unparks it runs the checklist below on a local desktop.

**Claim:** the pilot needs a local desktop, the upstream `playground` plugin as-is, human
judgment of the approve/reject/comment loop, and an Artifact clipboard press; a headless lane
cannot observe those, and the originating plan marked the question user-reserved (Q9).
**Basis:** #3617 protocol; ADR 0026 (wrapper ships without this evidence by design; learnings
feed wrapper content, never generation); triage 2026-09-06. **As of:** 2026-09-28. **Recheck:**
an operator runs this checklist on a local desktop and records learnings in
`plugins/playgrounds/skills/use/` (recipes, delivery-tier order, `context/consumer-notes.md`),
or unparks #3617.

## Operator-run checklist

Run on a local desktop with `playground@claude-plugins-official` installed. Judge the *loop*,
not template polish. Known at pinned upstream commit `ed404106`: the critique template's
Markdown renderer misses H3s, links, and lists; two of three prompt-output groups are
placeholders.

1. **Document-critique round trip.** Recipe: "Use the playground skill to review
   `plugins/<name>/skills/<skill>/SKILL.md` and give me inline suggestions I can approve, reject
   or comment." Record whether approve/reject/comment beats reading a review in the terminal.
2. **Cloud Artifact smoke.** Publish one generated playground as an Artifact and press its
   copy-prompt button. Record whether clipboard access works inside the artifact sandbox. If it
   does not, consider reordering delivery tiers in
   `plugins/playgrounds/skills/use/SKILL.md` (file-send ahead of Artifact).
3. **Intake.** Fold learnings into the wrapper's recipes, delivery-tier ordering, and
   `plugins/playgrounds/skills/use/context/consumer-notes.md`. Never into generation.
4. **Close.** Record the result even when the verdict is "no changes warranted". A recorded
   negative is the deliverable.

## Rationale

- The body marks the work user-reserved. An agent lane cannot substitute for that arbiter.
- Step 1 is a human comparison of two review experiences. Step 2 needs a published Artifact and
  a button press inside its sandbox. Neither is observable headless.
- Declining the autonomous mandate keeps the wrapper observation-only, which is ADR 0026.

## Revisit when

- An operator runs the checklist and files learnings against the wrapper surfaces above, or
- A maintainer unparks #3617 as an attended desktop session.

## Prior requests

- #3617 (2026-09-28): user-run playground pilot (deferred Q9); drain shipper parks as this
  operator-run checklist and declines an autonomous mandate (pilot not executed).
