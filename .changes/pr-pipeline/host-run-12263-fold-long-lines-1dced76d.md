---
bump: minor
---

### Changed

- The main-run review (`pr-review-main.yml`) folds a diff line over 1800 bytes onto lines that start `\ continued:`, never inside a UTF-8 character, so every byte reaches a whole Read and the lane gives a verdict. It no longer stops as `verdict=none reason=long-line`. The prompt says a continuation line is the rest of the line before it and adds no line to the file's numbering, so a finding's line number holds, and the verdict's credential scan also reads model text with its folds joined.
