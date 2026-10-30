---
bump: patch
---

### Fixed

- enable-auto-merge's refusal comment wraps each reason line to 100 columns at a space, its
  continuations indented two spaces, and folds more than 20 lines into a `<details>` block, so
  GitHub no longer scrolls a long reason sideways. The marker lines and the line naming the head
  are unchanged. Every reader joins a wrapped reason back into one line and still reads a comment
  posted before the change, and a refusal whose reason is unchanged writes nothing new, so a
  person-removed label stays off. clear-escalations reads the whole reason, so a person's code
  after a wrapped "; " still keeps the label.
- `quote` and `wrapLine` move from verify-notes.mjs into address-feedback.mjs; verify-notes'
  comments are unchanged.
