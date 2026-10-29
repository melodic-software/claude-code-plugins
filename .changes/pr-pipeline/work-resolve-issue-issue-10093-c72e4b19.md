---
bump: minor
---

### Changed

- pr-unblock settles a security-review `manifest dependencies: flag` rated below `CRITICAL` without a person when the lane's `INCORRECT` reply holds up. `hardRequire` in `adjudicate-feedback.mjs` reads the flagged `plugins/<p>/.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` at the PR head. It checks that the plugin is a marketplace entry, that each `dependencies` entry is a bare name of another entry with a `./` source in this repository, and that the lane cited a line of the plugin's skills, agents or commands invoking each one with no gate, fallback or negation word within two lines, in a file that already holds such an unguarded call at the PR's base, so the call-site evidence is read at both the base and the head. The reply job then posts a fixed reply naming those lines and resolves the thread. Such a flag takes no adjudicator slot, and one the check does not settle escalates `feedback-disputed`: a cross-marketplace, object-form (versioned) or externally sourced entry, an optional collaborator or a failed read. A `CRITICAL` or unrated flag, an `UNCERTAIN` or `VALID-defer` reply and every other security-review finding route as before.
