---
bump: patch
---

### Changed

- The animation references, the web performance reference, the audit frame-capture loop and the `write-css` motion, interaction and show-and-hide recipes name their config keys instead of stating durations, scales, travel, blur, springs, gesture constants, stagger, focus ring and performance thresholds. Recipes carry `{{key}}` placeholders filled from the resolved config, so a team's value or a project token reaches every recipe; where a reference stated a number that differed from its key's default (a 125ms tooltip, a 0.25x inspection speed), the key's default now applies. Hover recipes take `animation.duration_ms.hover`, and the focus ring recipe keeps its 2px floor, sourced to WCAG 2.4.13, whatever `css.focus_ring.width` resolves to. The spring damping column stays as examples.
