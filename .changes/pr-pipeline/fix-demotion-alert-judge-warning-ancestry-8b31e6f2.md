---
bump: patch
---

### Fixed

- post-merge-demotion-alert.yml warns when the suite judge (`babysit_postmerge.py --judge-run`) exits 2 to 4, with the judge's `error` from its JSON output, and still files the demotion as before. Before, the record was filed with nothing saying the judge had failed.
- A dispatched red run is treated as recovered, and files nothing, only when the newer green run's head descends from the red SHA: `compare <red SHA>...<newer SHA>` must read `ahead` or `identical`. Any other status, or a failed compare, files as if no newer run had passed. A green run on a ref named `main` that is not the branch, such as a tag, no longer suppresses the alert.
- `scripts/run-plugin-tests.sh` prints `Advisory nonce: <16 hex>` before any suite block when advisory suites are on, and repeats the nonce in each advisory warning. The nonce is never exported to suites.
