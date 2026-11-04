---
bump: patch
---

### Fixed

- `fetch-docs.sh --profile generic`: a `text/plain` answer to a URL whose path ends in `.md` is
  read as markdown on the first request, so a host that serves `.md` files as `text/plain` no
  longer leaves the page unread `unexpected-content-type`
  ([#13354](https://github.com/melodic-software/claude-code-plugins/issues/13354)). A `text/plain`
  answer for any other path is still refused.
