---
bump: minor
---

### Added

- The setup apply writer writes the settings file into the repository's convention home, read from the pointer region in AGENTS.md or CLAUDE.md, instead of the fixed docs/conventions. A repository with no region is offered one: with --yes the writer adds the region where the repository already keeps instructions (a new AGENTS.md only when neither file exists) and the overlay ignore line to .gitignore in the same step, and announces both. Without --yes it prints the offer and still creates a missing settings file in docs/conventions; changing an existing file, the region and the ignore line wait for --yes. --home names the home to offer, and --decline records a declined line so the offer is not made again. A home the repository already had lists the settings file in conventions-index.md. --home refuses a value holding a backtick or line break.
