---
bump: none
---

Moves the shared page's two SERIAL browser suites, `ui_snappy.js` and `ui_telemetry.js`, from part c into
a new part d (`ui-d.test.sh`), so part c no longer adds their run, one after the other, to its own wall.
Every check still runs. No plugin behavior changes.
