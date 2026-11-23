---
bump: patch
---

### Changed

- The pull-request monitor's poll script (`monitor-poll.sh`) sends every REST read as a
  conditional request and replays the cached body on a `304 Not Modified`, which GitHub does not
  count against the primary rate limit. A poll where nothing changed now costs no REST requests,
  down from seven; a read that did change costs one request per page, as before. Each page is read
  conditionally on its own, a full page with no next link still reads the page after it, the
  comment reads keep `since` fixed at the watch's start so their ETags hold, a read's answers are
  cached only once the whole read succeeded, and a surface whose pages all answered 304 is not
  re-reported. The cache needs no Bash 4 feature, so the script still runs on macOS Bash 3.2. The
  event lines are unchanged.
- The floor for any GitHub watch or poll is 90 seconds, up from 60: the monitor's default
  interval, the API budget, and the merge, merge-queue, async-merge and babysit docs that gave a
  60-second GitHub poll cadence now state 90, and the babysit merge gate polls an async merge
  every 90 seconds for up to 90.
- The pull-request skill and its monitor reference no longer restate how GitHub counts a
  conditional request against the rate limit: they link GitHub's guidance on conditional requests.
