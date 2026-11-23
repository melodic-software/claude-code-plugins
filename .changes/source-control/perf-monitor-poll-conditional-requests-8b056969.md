---
bump: patch
---

### Changed

- The pull-request monitor's poll script (`monitor-poll.sh`) sends every REST read as a
  conditional request and replays the cached body on a `304 Not Modified`, which GitHub does not
  count against the primary rate limit. A poll where nothing changed now costs no REST requests,
  down from seven; a read that did change costs one request per page, as before. Each page is read
  conditionally on its own, the comment reads keep `since` fixed at the watch's start so their
  ETags hold, and a surface whose pages all answered 304 is not re-reported. The event lines and
  the default 60-second interval are unchanged.
