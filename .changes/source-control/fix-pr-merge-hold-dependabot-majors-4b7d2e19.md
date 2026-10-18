---
bump: minor
---

### Changed

- The pr-merge lane holds a Dependabot pull request with a major update, or an update whose version cannot be read (a SHA pin, marked `<name>(unreadable)`), or whose title and commit metadata disagree (marked `<name>(disagree)`), for a human under `merge.dependabot.majors: hold`, the default: the gate refuses it with `dependabot-major-held:<names>` even with the review activity's `verdict=merge` marker at its head, and escalates it once with a marked comment and the tracker's human-gated role label. `merge.dependabot.majors: review` keeps the verdict merge. Non-major updates are unchanged.
