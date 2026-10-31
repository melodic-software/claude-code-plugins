---
bump: minor
---

### Changed

- `/testing:run-e2e` takes `--unattended` in place of a leading bare `unattended`, accepted anywhere in its arguments; the bare word is scenario text and the run is attended. The run still passes `--unattended` on to `/app-control:drive` and `/app-control:map refresh`. The argument hint lists the action first, shortened to `[worst-case…]` to stay within the 100-character budget, then `--unattended`; the Arguments section gives the full form. `worst-case` is also accepted as the first token, ahead of `app=`, `base=` and `trusted-root=`. The evals pass the flag.
