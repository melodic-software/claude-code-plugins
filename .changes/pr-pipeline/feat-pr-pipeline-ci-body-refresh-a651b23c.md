---
bump: minor
---

### Added

- An `address-feedback` round whose fix lands brings the stale PR body sections up to date through `publish-feedback`, unless the base's `pr_body_refresh` is `false`. The select job offers the `##` sections `pr_body_required_sections` lists whose text holds no gate-read line, never `## Follow-ups` or the body's last section, and pins each in `run.json` by SHA-256. The model job records new text with the review-thread tool's `record-body`. `publish-feedback` replaces only an offered section that is still unchanged and leaves every other byte. It drops the refresh alone, naming why in its log and the round marker, when the text holds a gate-read line (holds, `Draft:`, closing keywords by number or URL, `Refs:`, `Relates to:`, `Siblings:`, `Merge-Risk:`, `No related issue`), a heading, a code fence, the follow-up sweep's marker, the word `committer`, an @-mention, an HTML comment or a token, or when the body's gate-read lines would change. `fix-ci` rewrites no body section.
