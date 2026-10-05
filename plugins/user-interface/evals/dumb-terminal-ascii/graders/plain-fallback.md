---
type: llm
arm: both
---
PASS only if, for TERM=dumb, the output uses plain ASCII markers with no color, no box drawing and
no emoji, and, for users without a Nerd Font, the Nerd Font icons are dropped or replaced (used only
behind an option or detection). Common Unicode such as a check mark may stay for the no-Nerd-Font
group. FAIL if TERM=dumb still gets color or non-ASCII glyphs, or if Nerd Font icons stay on by
default.
