# Self-contained HTML Canvas scenes

Rules for one-file scenes (title cards, cutscenes, loops) with no external assets. Source in
brackets; "(judgment)" marks a rule no source states.

## Resolution and scaling

- Draw at a fixed logical resolution; common choices: 128x96, 160x144, 240x160, 320x180
  (judgment; 320x180 scales by exactly 6 to 1920x1080).
- Upscale by an integer factor only: `scale = floor(min(innerWidth / W, innerHeight / H))`,
  minimum 1; letterbox the rest with a palette colour (judgment).
- Draw to a W x H canvas and scale it with CSS, or draw scaled with `drawImage` from an offscreen
  W x H canvas (judgment).
- Set `ctx.imageSmoothingEnabled = false` on every context that draws scaled images
  ([MDN](https://developer.mozilla.org/en-US/docs/Web/API/CanvasRenderingContext2D/imageSmoothingEnabled)).
- Set `imageSmoothingEnabled` again after every canvas resize, which resets context state
  (judgment).
- Set CSS `image-rendering: pixelated` on the canvas (unverified; see
  [MDN](https://developer.mozilla.org/en-US/docs/Web/CSS/image-rendering)).
- Draw at integer coordinates only: `Math.floor` every x and y before `fillRect` or `drawImage`
  (judgment; fractional coordinates blend edges).

## Colour

- Lock the palette: one `PAL` object of hex colours; every draw call uses a `PAL` entry (judgment).
- No gradients, no alpha blending, no blur, no shadowBlur, no filters: each breaks the palette
  (judgment).
- Fake gradients and fades with dithering instead (see Transitions).
- Light a tile or surface with one flat colour plus a highlight edge and a shadow edge, not
  per-pixel lighting (judgment: in a public example session, per-pixel dithered relighting of
  every tile read as washed-out noise; flat tiles with edge accents read cleanly).
- Dither only large areas (sky bands, ground glow), never small sprites
  (`craft-static.md` Dithering).

## Time and animation

- Fixed 60 Hz simulation step with an accumulator inside `requestAnimationFrame`; render the
  latest state (judgment).
- Sprite animation at 8-12 fps: advance a frame every 5-8 simulation ticks, independent of
  movement speed (judgment).
- Hold key frames longer than in-betweens; reuse the cycle timings in `craft-animation.md`.
- Clamp the frame delta (for example to 250 ms) so a background tab does not fast-forward the
  scene (judgment).

## Structure

- A state machine of beats: each beat has a duration, an enter action, an update, and a next
  beat; the scene is a list of beats, not nested timers (judgment).
- Particles: a fixed-size pool allocated once; each particle steps down a palette ramp by index as
  it ages (bright to dark), never by alpha (judgment).
- Sprites: embed frame rows as strings keyed to `PAL`, the same shape as the renderer spec, and
  blit them to offscreen canvases once at load (judgment).
- Text: a bitmap font drawn from embedded glyph rows at integer scale; no `fillText` with system
  fonts, which anti-alias (judgment).

## Transitions

- Fade by ordered dithering: a 4x4 Bayer threshold matrix; at fade level t, fill every pixel whose
  threshold is below t with the fade colour (judgment; the 4x4 Bayer matrix is the standard
  ordered-dither matrix).
- Wipes and iris transitions snap to whole pixels (judgment).

## Audio (optional)

- Accept an optional WAV (inline as a `data:audio/wav;base64,...` URL; the data-URL RFC calls the
  scheme useful only for short values, [RFC 2397](https://www.rfc-editor.org/rfc/rfc2397)) or
  synthesize with WebAudio in the page.
- WebAudio `OscillatorNode` square is fixed at 50% duty; other duties (12.5%, 25%) need a
  `PeriodicWave` or samples written into an `AudioBuffer`
  ([MDN OscillatorNode.type](https://developer.mozilla.org/en-US/docs/Web/API/OscillatorNode/type);
  [Web Audio API](https://webaudio.github.io/web-audio-api/)).
- Schedule sounds on the audio clock (`source.start(ctx.currentTime + offset)`) and drive visuals
  from `ctx.currentTime`; JS timers drift by tens of ms
  ([A Tale of Two Clocks](https://web.dev/articles/audio-scheduling)).
- A cue on frame k at F fps starts at `k / F` seconds (arithmetic).
- Browsers block audio until a user gesture; start the `AudioContext` from a click or key press
  (judgment).
- GIF, APNG and animated WebP carry no audio
  ([GIF89a](https://www.w3.org/Graphics/GIF/spec-gif89a.txt), [PNG 3](https://www.w3.org/TR/png-3/),
  [WebP container](https://developers.google.com/speed/webp/docs/riff_container)); a scene with
  sound ships as the HTML file, or is recorded in-browser to WebM/MP4 via `canvas.captureStream`
  plus `MediaRecorder` (container depends on the browser,
  [MDN MediaRecorder](https://developer.mozilla.org/en-US/docs/Web/API/MediaRecorder/isTypeSupported_static)).

## Checklist before shipping

- One file, no network requests, opens from disk.
- Crisp at 1x and at every integer scale; no blurred edges.
- Every rendered colour is in `PAL`.
- Loops seamlessly if it loops: last frame flows into the first.
