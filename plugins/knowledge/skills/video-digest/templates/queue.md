# YouTube watch queue

Epic-level batch list for `/knowledge:youtube-digest queue` and `/knowledge:youtube-digest watch` (no URL). Live file: `.work/<watch-epic>/QUEUE.md`. Claim stubs: `.work/<watch-epic>/claims/<n>.json`.

**SSOT:** `context/watch-queue.md`

| # | URL | video-id | title | channel | slug | status | notes |
| --- | --- | --- | --- | --- | --- | --- | --- |

Statuses: `pending` | `in_progress` | `complete` | `failed` | `skipped`

`title` + `channel` are filled at `queue` time by the preflight probe (`acquisition/preflight-metadata.js`) so a human or agent can read what each row is without opening the URL.
