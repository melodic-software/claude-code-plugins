# ui-defects layer harness

`measure-layers.mjs` rebuilds the variants with `../build-variants.py`, loads each over `file://` at
widths 375 and 1280 with every non-`file:` request aborted, and records which check layer flags it:
axe (WCAG 2.x A and AA rules), geometry (box overlap, clipped content, page wider than the viewport,
same-row siblings off a shared top edge, boxes moved between load and 1 s), the CLS observer, pixel
diff against C0, console errors and failed requests, undecoded images, and the aria snapshot diff
against C0. It makes no model calls. `harness.test.sh` compares the result with
`expected-matrix.json` cell by cell.

## Setup (once)

```bash
npm --prefix plugins/testing/evals/fixtures/ui-defects/harness ci --omit=peer --ignore-scripts
```

This installs the pinned `@axe-core/playwright` 4.13.0 (with `axe-core` 4.13.0) from
`package-lock.json` into the gitignored `node_modules/` here. `--omit=peer` skips its
`playwright-core` peer: the harness loads `playwright-core` from the `playwright-cli` install on
`PATH` and uses that install's Chromium, so nothing else downloads. Pass
`--playwright-core DIR` to `measure-layers.mjs` to use another copy. Runs never fetch.

Measured with playwright-core 1.64.0-alpha-1789764292000 (from playwright-cli 0.1.21) and
Chromium 154.0.8037.0.

## Run

```bash
bash plugins/testing/evals/fixtures/ui-defects/harness/harness.test.sh
```

It prints `PASS` with the versions used, or `SKIP` when the setup above has not run. The full
table, with what each layer found per width, goes to `results/measured.json` (gitignored) when
`measure-layers.mjs` runs on its own.
