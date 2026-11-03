---
bump: patch
---

### Fixed

- `/wizard:generate` library: on a re-run, `_existing` offers no default for a hand-written double-quoted `.env` value holding a backslash, `$` or `"`, so pressing Enter cannot store the raw escapes as the value; the prompt asks again.
- `/wizard:generate` library: `open_url` tells the person to open the address themselves when no browser opener exists. The warning was printed into a redirect and never shown.
