# Authoring brief

One brief for every pixel-art skill. Skills point here; they do not keep a second copy of the field list.

## Fields

Ask only for a field that would change the pixels. Anything the request leaves out is a default, stated in one line, not a question.

| Field | What to capture | Default when the request is silent |
|---|---|---|
| Subject | What it is, and the features that must be visible | No default: this is the one field that is asked when missing |
| Style references | Games, artists, or images to aim at | "No reference; follow `craft-static.md`" |
| Proportions | Chibi, realistic, tall, or another named proportion | "Readable game-sprite proportions" |
| Size | Frame grid, or the engine cell when a target is named | 32x32, unless `engine-layouts.md` fixes the cell |
| Palette | A preset name, a project palette file, or a color count | 16 colors, locked |
| View | Front, side, three-quarter, top-down, isometric | Three-quarter |
| Mood | The feeling the lighting and shape should carry | Neutral |
| Target | Engine or format from `engine-layouts.md` | Plain PNG |
| Done criteria | 2 to 6 concrete checks a review round can mark pass or fail | Two checks: the silhouette reads at 1x, and the palette stays inside the locked set |

`animate` adds cycles, directions, and the target layout. `scene` adds beats, cast and set, resolution, and audio. Those extensions live in the skill, not in this table.

A done criterion names something a picture can fail. "Looks good" is not a criterion. "The lantern is the brightest cluster" is.

When the user states fewer than 2 criteria, add from the default pair until there are 2, and say so in the defaults line. When they state more than 6, keep the 6 that change the output and name the ones left out.

## File

Write `brief.md` beside the spec (or beside the scene template) before the first render. Shape:

```markdown
# Brief

- Subject: ...
- Style references: ...
- Proportions: ...
- Size: ...
- Palette: ...
- View: ...
- Mood: ...
- Target: ...
- Defaults: <one line covering every field that was not asked>

## Done

- [ ] <criterion>
```

`animate` and `scene` append their extra fields under the same list.

A later run that finds `brief.md` beside the spec reads it and does not ask again. When `animate` or `scene` reuses a sprite spec that already has a brief beside it, that file is the start: extend it, do not re-interview it.

## Review

Every review round lists each done criterion as pass or fail with a one-line reason. Stop when every criterion passes, or when the round budget (typically 2 to 4) is spent, with the failing criteria named. A round does not stop on "reads well" while a criterion still fails, and it does not continue past the budget to chase a taste the brief does not name.

## Interview hand-off

The in-skill brief above is the default path and works with nothing else installed.

When the request is vague (no subject, or no checkable done criterion) or high-stakes (a shipped game asset, or a large variant family), offer `/planning:interview` (if the planning plugin is installed). Planning owns a numbered-question brief. If planning is not installed, or the user does not accept the offer, continue with this brief and say which path was taken. Do not start the interview unless the user accepts.

## Recorded decisions

- **Claim.** An enabled Claude Code plugin contributes its skills to the session; a skill from another plugin is not available unless that plugin is installed. The full skill text loads when the skill is used.
- **Basis.** [Plugins overview](https://code.claude.com/docs/en/plugins), sections "Decide whether you need a plugin" and "What an enabled plugin adds to your sessions", read 2026-09-28.
- **As of.** 2026-09-28.
- **Recheck.** That page no longer stating that plugins are installed as units, or that a plugin's skills are present only when the plugin is enabled.

`craft-static.md` is in-repo. Re-read it when its silhouette, palette, or grid sections change; those sections are why proportions, style references, and palette are fields and why the rest default.
