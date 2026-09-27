# Split the animation render boundary into a scene module and a frame folder

- Status: accepted
- Date: 2026-09-27

## Context

The `animation` plugin needs a contract between craft (authoring a scene) and rendering, and one
between rendering and delivery (encoding, style statistics, a later `post` plugin). Three shapes
were weighed: a seekable scene module only, a frame folder only, or both at different boundaries.
A scene module lets any frame render on its own, so capture parallelizes and review can re-render
one drawing, but it has nothing to offer a producer with no scene, such as a generative video
model. A frame folder fits any producer but loses per-drawing re-render and gives a HyperFrames or
Remotion adapter nothing to consume.

## Decision

Both, at different boundaries. Craft hands rendering a seekable scene module (`canvas#c`,
`window.DURATION`, `window.renderFrame(t)`), and the frame rate is not part of it. Rendering hands
delivery a frame folder plus `render.json`, which records the fps, size, adapter and browser build.
`scripts/render.py` is the one composition root that turns the first into the second: every skill
renders through it, and it alone chooses the backend, encodes, and writes `render.json`. Render is
the only port with an interface, because it is the only one with a second adapter named.

## Why

Each boundary gets the shape its consumers need. Keeping fps out of the scene lets one scene render
at any rate, and `post` never sees a scene, so extracting delivery later is a move rather than a
rewrite. Both contracts are file formats that external adapters and other plugins write or read,
so changing either later means changing every producer and consumer at once. The full contract
text is sections 2 to 4 of
[contracts.md](https://github.com/melodic-software/claude-code-plugins/blob/3c08857ad/docs/topics/animation-ports/design/contracts.md);
the options table is thread T1 of
[design-threads.md](https://github.com/melodic-software/claude-code-plugins/blob/3c08857ad/docs/topics/animation-ports/design/design-threads.md).
