# The real-stack switcher

Sub-shape A runs a live wire through code you ship, so it holds four rules:

1. **Variants live outside the real component.** One throwaway file per variant, beside the code
   it would replace; the real component imports none of them.
2. **One mount block, clearly marked.** The page gets a single dev-only block that swaps the real
   subtree for the switcher, fenced in comments naming the prototype so it is greppable and
   revertible in one edit. The moment you are editing the real component to accommodate a variant
   (new props, conditionals, a branch per variant), you are past what sub-shape A allows.
3. **Dev-only, and it fails closed.** Gate on the environment, not on a flag someone could ship
   enabled. If the gate is unavailable, the real subtree renders.
4. **Real neighbors, still worst content.** The real page buys true surroundings; it doesn't
   excuse pretty data. Drive it to [SKILL.md](../SKILL.md) step 2's worst content.

The real-stack switcher is a small floating bar, fixed at the bottom center of the viewport:

| Part | Requirement |
|---|---|
| URL | Each step rewrites `?variant=`, so a reload or a link shared with a teammate opens the same variant; when the switcher is mounted in a layout shared across routes, it also keeps the current variant in session storage, so app navigation that drops the query keeps the choice, and a `?variant=` in the URL wins over the stored value |
| Keyboard | Left and right arrow keys step through the variants, except while a text input or textarea has focus |
| States | When the plan lists states, a second control and the up and down arrow keys (except while a field has focus) step through them, rewriting `?state=`, with the current state in the control's label |
| Buttons | Previous and next; both ends wrap around, so after the last variant comes the first and before the first comes the last |
| Label | The current key, plus a descriptive name if exported (`B · parcel cards`); export each variant component under a name built from its key (`VariantB` for key B) |
| Reuse | One shared component that sub-shape A and sub-shape B both mount |
| Production | Never rendered in a production build; an environment check gates it |
| Look | Built from none of the app's own colors or components (black on yellow over a blue-and-white `/shipments`), so no reviewer judges it as part of a variant |

## The notes harness

When the person wants to pin notes on the real-stack route, the notes bridge frames the route
from the app's dev server. Start it as [feedback.md](feedback.md) step 1 says, with
`--dev-origin <dev origin>` in place of `--page`. Write the dev origin with no path or trailing
slash (`http://localhost:5173`, not the `http://localhost:5173/` a dev server prints), on host
`localhost` or `127.0.0.1`. Give the person the `url` it prints, unchanged. The harness is what
the route adds for this. It is part of the mount block's prototype and follows the same rules:
dev-only, failing closed, and removed in one pass.

| Part | Where it sits |
|---|---|
| Directory | One `prototype-harness/` directory at the app's root holds every harness file; each file opens with a comment naming `data-prototype-harness` |
| Helper | A copy of `<plugin-root>/notes-bridge/proto-pin.js` in that directory, loaded into the route by one script element that carries the `data-prototype-harness` attribute, behind the switcher's environment gate |
| Fence | `harnessFence(<bridge origin>)` from copies of `<plugin-root>/notes-bridge/harness-fence.mjs` and the `dev-origin.mjs` it imports, both in that directory, mounted as dev-server middleware, so only the host page on the bridge origin may frame the route. `<bridge origin>` is the `origin` that `ensure-running` printed; when a later `ensure-running` prints another, update the fence to it |
| Marker | The harness adds only whole lines to a file the app keeps (the dev-server config, the entry that loads the helper), never edits an existing one, and each line it adds carries `data-prototype-harness` in a comment or attribute |

Step 5 deletes `prototype-harness/` and every marked line in the same change that merges the
winner. Then `git grep -n data-prototype-harness` prints nothing, and neither does a grep of the
build output for it.
