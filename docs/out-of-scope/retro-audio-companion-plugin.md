# retro audio companion plugin

Build-later park for
[#4404](https://github.com/melodic-software/claude-code-plugins/issues/4404).

## Decision

**Park. No code.** No chiptune music / sound-effects companion plugin ships
in this pass.

- **Option A (taken):** decline the unpaid retro audio plugin.
- **Option B (declined):** design and implement the companion now.

**Claim:** a retro audio companion plugin is unpaid product work outside the
shipped pixel-art and animation surfaces.
**Basis:** #4404 (`needs-triage`). `plugins/pixel-art/README.md` "Audio" section
states this plugin makes no sound and accepts an audio file a separate tool
supplies, without either plugin depending on the other. No `plugins/audio` (or
similar) tree exists on origin/main. Claude Code plugins extend via
skills/agents/hooks (https://code.claude.com/docs/en/plugins); a new audio
plugin is a greenfield vertical. Drain hard floor: no unpaid audio generators.
**As of:** 2026-09-28.
**Recheck:** a maintainer funds `/planning:design` for a retro audio companion
and unparks #4404.

## Revisit when

- A maintainer funds the companion design, or unparks #4404.

## Prior requests

- #4404 (2026-09-28): Option A park.
