---
bump: patch
---

### Fixed

- The interview page's question pane fixes several layout and accessibility papercuts ([#7970](https://github.com/melodic-software/claude-code-plugins/issues/7970)). The recommendation's full text shows once, in the Decide list's Rec row, which now keeps its code, links and emphasis, and the Thread no longer opens with a `Claude asked` line that repeated the question. The header names a group only when it differs from the stage. Why and Details toggle side by side, so opening one never moves the other. The side panels open pinned beside the question on a screen 1200 px or wider until you choose, a stored Pin choice still wins, and Esc still closes a panel only that default pinned. The Pin control reads `Pin beside`. `Finish: export and end the session` is a secondary control while anything is outstanding and the primary one at zero, enabled either way. The dialog's second button has a name before it shows. The light theme's faint label color is darker (`#5f6a7c`, at least 4.57:1 on every light background). A wide Decide pane shows its rows in two columns, and on a short screen the question gives the answer area more room, down to 41% of the pane, so the whole list fits unscrolled at 1568x744.
