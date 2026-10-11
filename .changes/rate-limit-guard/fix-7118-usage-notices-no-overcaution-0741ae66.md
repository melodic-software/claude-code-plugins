---
bump: major
---

### Changed

- Each approach or threshold line Claude reads is now followed by one options line: continue at the same model, effort and review depth; the user can switch accounts (claude-code-account-rotation); or schedule work for after the reset. The line also says usage never calls for lowering model, effort or review depth, and that stopping or pausing is the user's call or an opted-in loop lane's (#7118).
- The default threshold now reads as the "95% line threshold" in toasts and transcript lines, not the "95% pause edge".
- **Breaking:** the reader contract's operable floor makes pausing opt-in. Only a lane whose session environment sets `LOOP_LANE_RATE_LIMIT_PAUSE=1` pauses at 95%. Without it, a lane keeps working and reports the window and the options.
