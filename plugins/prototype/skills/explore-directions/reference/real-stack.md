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
| URL | Each step rewrites `?variant=`, so a reload or a link shared with a teammate opens the same variant |
| Keyboard | Left and right arrow keys step through the variants, except while a text input or textarea has focus |
| States | When the plan lists states, a second control and the up and down arrow keys (except while a field has focus) step through them, rewriting `?state=`, with the current state in the control's label |
| Buttons | Previous and next; both ends wrap around, so after the last variant comes the first and before the first comes the last |
| Label | The current key, plus a descriptive name if exported (`B · parcel cards`); export each variant component under a name built from its key (`VariantB` for key B) |
| Reuse | One shared component that sub-shape A and sub-shape B both mount |
| Production | Never rendered in a production build; an environment check gates it |
| Look | Built from none of the app's own colors or components (black on yellow over a blue-and-white `/shipments`), so no reviewer judges it as part of a variant |
