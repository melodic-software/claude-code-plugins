# Motion

Where the project has its own tokens or conventions, they win over anything here. The numbers in
the snippets are fallbacks: reach for one only when no project token covers it, and say which
fallback you used.

A `Support:` line points at the support table that is kept current; quote no version from it
here. Checked 2026-10-11; check again when that table's status for the feature changes or the
project's supported targets move.

## Quiet motion: `quiet-motion`

Why: a viewer who turned motion off gets the still version, and nothing they need is lost.

Support: [`when motion`](https://example.invalid/ferro/support/when-motion)

```text
.button .icon {
  shift: none;
}

when motion {
  .button .icon { ease: shift 200ms out; }
}
```

Rules:

- Write the state change first and put the animation inside the `when motion` block. Do not
  remove animation afterwards with a global rule that sets every frame count to `0`.
- Color and brightness fades are not animation and can stay outside the block.
- Animation driven by a plugin checks the same setting with `motionAllowed()`.

## Fade swap: `fade-swap`

Why: movement swaps to a fade; feedback stays.

- Where a viewer turned motion off, replace a slide with a 150ms fade rather than removing the
  feedback.
