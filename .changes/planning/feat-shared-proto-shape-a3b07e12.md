---
bump: minor
---

### Added

- A shared interview prototype variant can show up to four screenshots (`shots`) and an HTML snapshot (`snapshot`). The prototype page stacks the screenshots in order, each with a caption and its own pins, and switches between the snapshot and the screenshots when a variant has both. A variant with one view is still written as `{id, label, asset}`, and `asset` is still accepted. Every new prototype question carries a required `format.lookAt` line naming the area that changes and the step that shows it, and a variant may add its own. The line shows on the question card beside "Open prototype" and above the variant tabs. A question from before it loads and shows no line. A session holding a `lookAt` or a variant with more than one view does not load in an earlier build.
