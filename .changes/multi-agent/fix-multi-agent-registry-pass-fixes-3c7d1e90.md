---
bump: patch
---

### Fixed

- `/multi-agent:route vendors` no longer loses board-reader records to a display name: the
  VerdictRecord schema and the `board-reader` rules now require `model` to be a current model id
  copied verbatim and `version` and `effort` to be id tokens or null, the shape `vendor-decide`
  already accepts. Before, a reader wrote names such as `GPT-6.2 Astra` into `version` and the
  decider dropped the record.
- `fetch-boards` no longer dates a page from a model snapshot suffix such as
  `Qwen Image 2.0 Pro (2026-04-22)` or a model id such as `gpt-5.4-mini-2026-03-17`.
- The `vals-vibe-code` registry row also counts for `coding`: the board scores agents building
  complete applications with file-editing and shell tools.
