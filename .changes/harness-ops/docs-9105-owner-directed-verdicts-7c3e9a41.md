---
bump: patch
---

### Changed

- `audit-native-overlap` now says who writes a native-overlap verdict or dismissal: a person, or a session acting on the owner's recorded direction, and never an unattended run ([#9105](https://github.com/melodic-software/claude-code-plugins/issues/9105)). It used to say a person and never a run. The new wording is in the skill's statements of the rule, its `summary`, the `canonical-pairs.json` note, and these `overlap.py` texts: the view header, the generated Dismissed section's lead sentence, the `detect` report note and the `dismiss` help. A run of the skill still only recommends a verdict and never records one. The skill's evals are unchanged.
