# animation

A Claude Code plugin for hand-drawn-style 2D animation made as code. The model writes a
deterministic `renderFrame(t)` scene, headless Chromium draws every frame, and ffmpeg encodes the
film.

Skills arrive in this order: `rotoscope` (copy a reference clip drawing by drawing, measured),
`learn-style` (turn traces into a reusable style pack), and `film` (brief, boards for approval,
shots, render, review).
