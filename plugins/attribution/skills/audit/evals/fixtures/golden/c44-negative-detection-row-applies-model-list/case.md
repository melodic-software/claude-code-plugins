# Instruction criteria

## L12. Reasoning-off requests the model refuses

A surface that tells the reader to switch reasoning off fails on the models below. The row has
three arms.

- **First arm: Lumen Atlas 3 above `low` effort.** Turning reasoning off is refused only when effort
  is set higher than `low`; at `low` the request goes through.
  Pointer: the effort forms that count are in
  [model configuration: effort](https://example.invalid/lumen/docs/model-config#effort). Checked
  2026-10-01; revisit if that section changes which forms set effort.
- **Second arm: models that refuse the switch at any effort.** This catalog counts the switch as
  a failure at every effort for the whole set: Lumen Atlas 4.5, Lumen Atlas 4.1, Lumen Atlas 4,
  Lumen Brook 4.1, Lumen Brook 4 and Lumen Brook Preview. Here the switch by itself is the finding, and the
  request fails with or without an effort value. The effort condition belongs to the Atlas 3 arm
  only; it does not carry over to the row as a whole. Applied here, it would let a surface that
  asks for reasoning-off at `high` on Brook 4.1 pass. For Atlas 4.5 the fix also names the guide's
  `minimal` setting, which the third arm limits.
- **Third arm: the `minimal` setting.** A surface that swaps the switch for `minimal` effort passes
  on Atlas 4.5 and fails nowhere else in this row.
