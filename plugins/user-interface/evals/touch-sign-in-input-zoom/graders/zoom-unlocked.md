---
type: llm
arm: both
---
PASS only if the reply's corrected viewport meta tag (or framework viewport setting) carries
neither `maximum-scale` nor `user-scalable`, or the reply states plainly that `maximum-scale=1` is
removed, so people can pinch to zoom on every browser. A tag that keeps `width=device-width,
initial-scale=1` and adds other keys such as `viewport-fit=cover` passes. FAIL if the proposed tag
keeps `maximum-scale=1`, sets any `maximum-scale` at or below 1, adds `user-scalable=no` or
`user-scalable=0`, sets a framework's `maximumScale: 1` or `userScalable: false`, or prevents
zoom from script (a `gesturestart` or `touchmove` handler that calls `preventDefault()` to stop
zooming). A reply that quotes the old tag only to say it is wrong does not fail for that quote.
