---
bump: patch
---

### Fixed

- `/playwright:demo-video`: a click that opens a modal no longer yields a plan QC fails. `build_edl.py` holds the camera until the modal's first settled capture, never moves it across an in-page change QC counts as a page cut, and refuses a plan that would.
- `/playwright:demo-video`: the caption anchor applies the modal mask from the click that opens it, and a click shot held over from a typing shot is edge-checked with that shot's modal mask.
- `/playwright:demo-video`: a slow push-in on a long still stretch is checked against every caption sample and click target in its span, falls back to a push-in and ease-back when no target can hold, and a target at the page edge returns the camera to the full page.
- `/playwright:demo-video`: a refused plan removes the earlier `edl.json`, so `produce.py` cannot render a stale plan.
- `/playwright:demo-video`: `qc.py` prints the stillness limit it applies and writes a contact sheet for each failing check; `record.mjs` says no capture was written when the replay fails; the Settings table states each option's default; the capture rate and the modal `settle` requirement are documented.
