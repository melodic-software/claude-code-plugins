---
bump: patch
---

### Fixed

- continue long lists onto new frames and fail frames that overflow

  A stills moment whose list does not fit one frame (also-changed files,
  code-hunk lines, risk-map rows) now continues onto as many frames as it
  needs, each labeled "continued, part N of M", all held during that
  moment's narration paragraph and sharing its time by entry count. The
  storyboard contract is unchanged.

  After capture, each frame is fit-checked in the capture browser: any box
  or line of text outside the content area (cut off, in the caption band,
  or over the header) is a defect listed in manifest.json, and the render
  exits 1. The check runs on the final frames, so it catches an overflow
  even when pagination is wrong.

  The bundled frame stylesheet is scaled so the smallest text is at least
  14 px tall in an 888 px wide player, also-changed paths wrap instead of
  running off the frame, before-after lines balance their wraps, and a
  screenshot fits the area above the caption band.

- hold every stills frame long enough to read

  Each frame now has a reading minimum: its visible words at the caption
  reading rate (captions.seconds_per_word), never under the captions-only
  hold's floor (captions_only_hold.min_seconds, 3 s). When a moment's
  frames need more time than its narration paragraph, the moment holds on
  past the paragraph with silence padded into the audio, so later words,
  captions and chapters shift with it and nothing is sped up or cut. A
  frame held under its minimum is a defect in manifest.json and the render
  exits 1.
