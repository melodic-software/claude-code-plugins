# Replay script API

`record.mjs` imports the replay script and calls its default export with a `demo` object. The
script drives a real Playwright page; `demo` records what the edit needs (action times, target
boxes, settled frames) while a background loop captures device-pixel frames.

```js
export default async (demo) => {
  await demo.goto('http://localhost:3000/');               // first goto starts the capture
  const hero = demo.union(await demo.boxOf('h1'), await demo.boxOf('#cta'));
  await demo.click('open-cta', '#cta', { block: hero });   // step id keys script.json
  await demo.page.waitForURL(/signup/);
  await demo.settle('open-cta');                           // the step ends when the pixels stop changing
};
```

| Call | Records | Notes |
|---|---|---|
| `demo.goto(url)` | `start` (first call) | Waits for network idle, then starts capture |
| `demo.click(step, target, { block })` | `move`, `click` | `target`: CSS selector, Playwright locator or `[x, y, w, h]`. `block` is what the shot frames; default is the target plus padding |
| `demo.type(step, target, text, { modal })` | `type`, `key`, `typed` | One key at a time, two captures per key. `modal`: the panel the shot frames while typing |
| `demo.settle(step, { box, modal })` | `settled` | Waits for network idle and four identical captures. `box`/`modal`: the results area the typing shot frames; a typing step behind a modal on the same page needs `modal` |
| `demo.style(css)` | | Injects CSS for the rest of the run; returns a remover. Hide flashing partial states with it |
| `demo.moveTo(step, target)` | `move` | Cursor travel without a click. An id used only by `moveTo` is not a step: its travel plays inside the hold around it |
| `demo.wait(ms)`, `demo.page` | | The Playwright page for anything else (`waitForURL`, `keyboard`) |

Rules the edit relies on:

- Every step is one `click` followed by one `settle` with the same step id; a typing step adds a
  `type` between them. A step whose URL changes by `settle` is a navigation: the camera eases to
  1.0x and cuts. In a typing step the cut starts when `type` returns, so submit after it (for
  example `demo.page.keyboard.press('Enter')`), not with a newline inside the typed text.
- A typing step that stays on the same page behind a modal settles with
  `demo.settle(step, { modal })` (and `box` for the results area). Without `modal` the edit treats
  the dimmed page behind it as content: the typing shot, its edges and the caption anchor are
  judged against text the viewer cannot read, and the plan can be refused.
- A `block` must hug visible content. A block-level element's box spans its container, so build
  it with `demo.union` from elements that hug their text, or pass explicit coordinates.
- Settle after every state change you want shown; anything between a navigating click (or the
  end of a navigating step's typing) and its settled frame never reaches the video.
- Keep holds short with `demo.wait`: the edit sets output pacing, the replay only needs the page
  to have reached each state.

Environment knobs: `DEMO_WIDTH`/`DEMO_HEIGHT` (viewport, default 1920x1080), `DEMO_DSF` (device
scale, default 2), `DEMO_SLOW` (real-time stretch of cursor travel, default 3).
