# pixel-art unpaid expansions

Recorded decline for
[#4399](https://github.com/melodic-software/claude-code-plugins/issues/4399),
[#4400](https://github.com/melodic-software/claude-code-plugins/issues/4400),
[#4401](https://github.com/melodic-software/claude-code-plugins/issues/4401),
[#4402](https://github.com/melodic-software/claude-code-plugins/issues/4402),
[#4403](https://github.com/melodic-software/claude-code-plugins/issues/4403),
[#4405](https://github.com/melodic-software/claude-code-plugins/issues/4405),
and
[#4406](https://github.com/melodic-software/claude-code-plugins/issues/4406):
proposed expansions beyond the shipped `sprite` / `animate` / `scene` skills.

## Decision

**Park. Do not build.** No structured brief interview skill, tileset/ui/vfx
skills, palette-preset machinery, third-party backend adapters, scene capture /
video export, procedural character kit, or skill-eval / reference review pass
ships until a maintainer funds the work.

- **Option A (taken):** keep `plugins/pixel-art` at the three shipped skills and
  the documented `native` backend. Unpaid expansions stay out of scope.
- **Option B (declined):** implement the #4399-#4406 family in this drain pass.

**Claim:** the pixel-art expansion family is unpaid product work; this marketplace
does not add those skills, adapters, or eval suites until a maintainer funds them.
**Basis:** origin/main `plugins/pixel-art` ships `sprite`, `animate`, and `scene`
only (`README.md` skill table). `backend` defaults to `native`; `reference/backends.md`
documents aseprite / pixellab / retrodiffusion as optional and "not yet exercised"
with no adapter code in this version. Official Aseprite CLI
(https://www.aseprite.org/docs/cli) is a host tool this plugin may call later; it
does not obligate marketplace adapters. Claude Code plugins are skills/agents/hooks
extensions (https://code.claude.com/docs/en/plugins); adding generators and paid
API adapters is product scope, not a drain settle. Hard floor from the drain lane:
no pixel-art/audio generators unpaid.
**As of:** 2026-09-28.
**Recheck:** a maintainer funds one or more of #4399-#4406 with acceptance criteria
and unparks that issue.

## Children

| Issue | Ask |
|---|---|
| #4399 | structured brief interview before authoring |
| #4400 | tileset, ui, and vfx skills |
| #4401 | palette presets and palette snapping |
| #4402 | Aseprite CLI / PixelLab / Retro Diffusion adapters |
| #4403 | scene capture and video export |
| #4405 | reusable procedural character kit |
| #4406 | skill evals and reference-file review pass |

#4404 (retro audio companion) and #4507 (woodcut-ink residuals) are separate
ledgers.

## Rationale

- Seven features spanning interview UX, new skills, palette tooling, three
  external backends, video export, a procedural kit, and an eval suite is a
  plugin vertical, not a drain-shipper slice.
- The README already states non-native backends are documented and unexercised.
  Shipping adapters without funded design invents contracts against host CLIs
  and third-party APIs.
- Skill evals (#4406) need a funded corpus and review bar; they are not a
  free documentation park of the expansion work itself.

## Revisit when

- A maintainer funds one named child with acceptance criteria, or
- Unparks the family epic-style after choosing build order.

## Prior requests

- #4399, #4400, #4401, #4402, #4403, #4405, #4406 (2026-09-28): Option A park.
