---
bump: patch
---

### Fixed

- `/playwright:demo-video`: a click that opens a modal no longer yields a plan QC fails. `build_edl.py` holds the camera until the modal's first settled capture, never moves it across an in-page change QC counts as a page cut, and refuses a plan that would.
- `/playwright:demo-video`: the caption anchor applies the modal mask from the click that opens it, and a click shot held over from a typing shot is edge-checked with that shot's modal mask.
- `/playwright:demo-video`: a click target at the page edge gets a zoomed shot framed against that edge (with longer cursor travel when the move needs it), and its shot stays clean through a modal that opens on the click.
- `/playwright:demo-video`: a slow push-in on a long still stretch is added only when the frames are still (cursor travel already moves them), keeps the direction of the move into the hold where any shot allows, and is checked against every caption sample and click target in its span.
- `/playwright:demo-video`: `qc.py` nav-cuts judges camera stillness on the frames on each side of a page cut, not the registration jump across the two captures, which flagged a still zoomed camera as moving.
- `/playwright:demo-video`: a refused plan, or a capture that is not a demo replay, removes the earlier `edl.json`, so `produce.py` cannot render a stale plan.
- `/playwright:demo-video`: `qc.py` prints the stillness limit it applies and writes a contact sheet for each failing check; `record.mjs` says no capture was written when the replay fails; the Settings table states each option's default; the capture rate and the modal `settle` requirement are documented.
