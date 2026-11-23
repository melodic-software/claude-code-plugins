---
bump: patch
---

### Fixed

- keep every registry and docs fetch under the 30,000 characters of Bash output Claude Code reads back

  `docs-raw.sh` returns a section map for a page over 28,000 bytes and caps every body there, and
  registry-audit reads sections in calls under that cap. A fetch Claude Code saved to a file is
  reported as `output-over-readback-limit`, not as a missing header.

- read script-drawn and bot-blocked benchmark boards

  The registry fetcher may pass `--render`: `docs-raw.sh` checks the row's `expect` marker and,
  with the docs-cache `renderer` set to `firecrawl`, renders the page through the Firecrawl CLI.
  The Terminal-Bench row now points at the site root, where its current leaderboard moved.

- demote a benchmark row only on definitive evidence

  A registry recheck proposes a status change for an unread page only when the host reports it
  gone (404 or 410). Every other unread reason (a missing expect marker, a block, a rate limit,
  a moved page, a failed fetch) leaves the row partial with the fix to try and no proposal, so a
  page-format change or a transient fault never demotes a board.
