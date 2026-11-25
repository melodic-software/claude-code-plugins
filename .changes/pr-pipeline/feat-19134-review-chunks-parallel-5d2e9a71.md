---
bump: minor
---

### Changed

- PR Review Main and pr-verify review a diff of up to 75 chunks of 300000 bytes (22.5 MB, ci-workflows pr-review-cli.yml's 3000-file ceiling at 40 files a chunk), up from 4 and 12. Chunk 1 still runs on its own run-claude-cli step; every later chunk runs in one ci-workflows `run-review-chunks` step, 8 at once, on the same credential and tool rules, so N chunks take about 1 + (N - 1) / 8 legs' time instead of N. The fixed per-chunk step copies are gone, and each job's timeout is chunk 1's step, the later chunks' loop at the ceiling (3 + ceil(74 / 8) x 16 = 163 minutes) and the rest: 197 minutes for PR Review Main, 222 for pr-verify. PR Review Main's merged summary keeps each chunk's first 16000 / N characters. pr-verify packs the chunks' results for the final judge into as few files as 300000 bytes take, asks each chunk for summary and notes under 300000 / N / 3 characters, and skips the final judge when any chunk left a fail the head counts. The later chunks' sealed transcripts upload under the `-chunks` job id.
