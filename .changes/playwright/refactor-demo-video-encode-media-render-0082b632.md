---
bump: patch
---

### Changed

- `demo-video` encodes through the shared media-render library's `demo-video` profile, and mixes narration
  through its `mix` call; the rendered video is unchanged. The edit plan no longer carries an `encode` block.
- `demo-video` names its related skills under Related and Next.
