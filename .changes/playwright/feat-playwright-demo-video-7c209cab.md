---
bump: minor
---

### Added

- **`/playwright:demo-video`: produced demo videos for pull requests, gated by frame-measured QC.** Explore a flow unrecorded, write a replay script, replay it with 4K device-pixel capture, build an edit plan (eased zoom onto each action within motion limits, drawn cursor, click ripple, captions on a primary or one fallback anchor, hard cuts at 1.0x on navigation), render an H.264 MP4, then `qc.py` measures zoom share, edge clipping, stillness, camera motion, cuts, crossfades and blank frames from the rendered frames and exits nonzero on a failure. A cut that changes the URL passes only when the frames measure it at 1.0x with the camera still; an in-page state cut may instead stay zoomed if its frame edges cut no text. An independent fresh-context frame review comes before posting with `gh --attach` locally or a non-zipped Actions artifact in CI. Options: `demo_style` (`produced` default, `plain`) and per-layer toggles for title, camera, cursor, ripple, captions and narration (off by default, through `/speech:narrate`). numpy and Pillow are hash-locked in the skill's `requirements.txt` and run through its `pydeps.py` launcher.
- **SessionStart hook `hooks/install-python-deps.sh` installs the demo-video packages.** It installs the hash-locked numpy and Pillow into the plugin data directory, is a no-op once they load, and reports a failed install with the repair line. A mid-session enable still gets the launcher's install line. Dependabot watches the lock.
- **`prerequisites.json` declares Python 3.12+, `ffmpeg` and `ffprobe`** for the demo-video skill and its hook.
- **`/playwright:playwright` names `/playwright:demo-video` in its `## Next` section.**
- **Demo-video safety.** `pydeps.py` runs its import probe and `pip` with `python -P`, so a
  `numpy.py` or `pip/` in the working directory cannot run or replace the locked set; `record.mjs`
  records into a staging directory and replaces an earlier capture only once the new one
  succeeds, and refuses a non-empty directory that is not exactly an earlier capture; the
  independent review now fails a video showing secrets, personal data or internal hosts.
