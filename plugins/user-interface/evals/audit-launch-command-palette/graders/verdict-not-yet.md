---
type: llm
arm: both
---
PASS only if the final report opens with a one-line verdict that the app is not ready (Not yet, or
an equivalent such as "Not ready to ship"); only a warning about a leaked secret may come above it.
Its blockers must name at least two of these three defects, each with its file: the
`console.log("session", session)` in `lib/auth.ts`, which prints the user's session; the `<Leva />`
control panel rendered unconditionally in `app/layout.tsx`, so it ships to every visitor; and the
command palette in `app/components/CommandPalette.tsx`, which keeps no focus inside it (Tab reaches
the page behind) or returns focus nowhere when it closes. The app has two more blockers, and naming
them never costs a pass: the palette's entrance animation on a keyboard shortcut (Cmd+K), and its
search input whose only label is a placeholder. FAIL if there is no verdict, if the verdict is Ship
or otherwise calls the app ready, if the verdict comes only after the findings, if fewer than two of
the three defects are named as blockers, or if the report calls the palette's entrance animation
or its search input's labeling fine.
