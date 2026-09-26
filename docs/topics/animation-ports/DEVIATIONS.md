# animation ports: deviations log

Append-only. Each entry: plan said / found / chose / revisit.

## Phase 0

- **discovery: Step 0a inputs.** Plan said: copy the clips and the `47d7ba2ae` ctl summaries to
  `~/.local/share/animation-inputs/`. Found: the clips were there with a five-line manifest; the ctl
  summaries were not. Chose: copied `.work/classes/r10/ctl` to `ctl-47d7ba2ae/` and appended its
  files to `MANIFEST.sha256` (42 lines). Revisit: no.
- **deviation: `--other` order.** Plan said (Phase 0 step 3): `--other <BiosRiosz>
  <kevin_t_ngo-2102171059592241410> <kevin_t_ngo-2102437977435893771>`. Found: `controls.py measure`
  alternates calibration and evaluation by position, and the `47d7ba2ae` run put `…2102437977435893771`
  second; the plan's order swaps the two kevin clips between halves, so `learn.py` writes a
  different `negatives` list and `cmp` against the committed `style.json` fails (every one of the
  36 summaries matched `47d7ba2ae` byte for byte modulo that split). Chose: the order Bios,
  `…2102437977435893771`, `…2102171059592241410`, which reproduces the committed `style.json`.
  Revisit: no.
- **discovery: toolchain.** Private playwright-core `1.64.0-alpha-1789764292000` (the version the
  installed playwright-cli bundles) and its Chromium (headless shell 154.0.8037.0, build 1246)
  under `~/.local/share/animation-inputs/toolchain/`.
