---
bump: minor
---

### Changed

- The `address-feedback` select job offers for a body refresh the sections the base's `pr_body_required_sections` lists, else the `##` headings of the base's pull request template, else those of the owner's `.github` repository template, and offers none when that template cannot be read.
- The merge-risk workflow's header says a session merge of a lanes App pull request holds without a rating for the head.
