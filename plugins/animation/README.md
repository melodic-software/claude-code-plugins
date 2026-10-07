# animation

A Claude Code plugin for hand-drawn-style 2D animation made as code. Scenes are deterministic
Canvas 2D modules (`renderFrame(t)`), headless Chromium draws the frames, and ffmpeg encodes them.

## Skills

| Skill | What it does |
|---|---|
| `/animation:rotoscope <clip> <work dir>` | Copies a reference clip drawing by drawing: traces each distinct drawing to vector paths, renders them through the ink.js brush engine, measures every drawing against its source (XOR against a codec-noise floor, SSIM, edge-band SSIM, paper color), fits per-shot brush overrides, and reviews 1:1 crops. Each run appends to a learnings file, and a retro step promotes recurring findings into the defaults. |
| `/animation:check-prerequisites` | Read-only report of whether the tools the plugin declares in `prerequisites.json` resolve; installs nothing. |
| `/animation:setup` | Checks the prerequisites (ffmpeg with libx264, ffprobe, Node, playwright-core with Chromium, the pinned numpy and opencv, and the `playwright_core` option when set) and prints a PASS/FAIL/INFO table with one remedy line per failure. Check-only: it installs nothing (the SessionStart hook installs the Python packages). |
| `/animation:learn-style <work dir> <pack dir>` | Measures a rotoscope work directory into a style pack: palette and tone ramp, the seven style knobs, and statistic bands (edge softness, stroke and gap widths, edge roughness, gray inside the ink, boil of the frame and caption, holds on 1s/2s/3s). Then proves the pack by authoring a new scene with ink.js and checking its render against the bands. |
| `/animation:produce <production dir>` | From a brief and one or more style packs, writes pre-production boards and stops for approval. After that, a shot list, scenes, rendered frames, a delivered file, and a review against the pack. `shots.json` is the cut list `inkstats.py --cuts` reads. |

## Style packs

`styles/<name>/` holds one style: `style.json` (measured statistics, bands, knobs, brush defaults)
and `STYLE.md` (the style in words, with its credit and validation). Packs hold statistics only,
never a source's frames or traces.

| Pack | Style |
|---|---|
| `woodcut-ink` | Two-tone brushed ink on cream with carved gouges, a soft edge and boil on 3s. A study of @shfred0's clip; no untraced scene has passed its current check yet. |

## Shared scripts

`scripts/` holds what every skill renders with: `ink.js` (the deterministic brush engine: capsule
dabs, ink fills, strokes, splatter, dashed lines, paper grain), `render.html` (loads a scene module
named by `?scene=`), `render.py` (the one render entry point: serves a scene, captures each drawing
or every frame at a given fps through `capture.mjs`, writes `render.json`, and encodes), `decode.py`
(reads a video, a frame folder or a work dir back into frames), `prereq.py` (the prerequisite
probe), and `inkstats.py` (style statistics of any film, a video, a frame folder or a rotoscope work
dir, with `--pack` to check it against a style pack; `--cuts` takes a comma list or a produce `shots.json`), `produce.py` (the production directory: boards, the approval digest, `shots.json`, and the review command), and `woodcut_marks.py` (a test helper for the woodcut-ink authoring residuals: synthetic caption and frame drawings inside the frozen bands, not a render or measuring entry point).

## Requirements

`/animation:setup` checks each of these and prints one remedy line per missing one. Verified on
Linux only; Windows and macOS are untested by hand (the scripts use no shell and open text as
UTF-8, but no run there has been recorded).

- Python 3.12 or later (numpy 2.5 requires it) with pip. numpy and opencv are not vendored and
  never fetched while a skill runs: a SessionStart hook installs the hash-locked set in
  `requirements.txt` into the plugin data directory (`pip install --require-hashes`, wheels only),
  and does nothing once it loads. A failed install is reported as a notice with the repair line.
  Run every script through
  `python3 ${CLAUDE_PLUGIN_ROOT}/scripts/pydeps.py run --data-dir "${CLAUDE_PLUGIN_DATA}" -- <script> ...`.
  The pins keep the statistics and the shipped regression reproducible byte for byte. To change
  one, edit `requirements.in` and regenerate the lock from this directory:
  `uv pip compile requirements.in --universal --generate-hashes --python-version 3.12 --only-binary :all: -o requirements.txt`.
- `ffmpeg` at or above `scripts/prereq.py`'s `FFMPEG_MIN` (the first release with `-fps_mode`), with
  the `libx264` encoder, and `ffprobe`, on PATH.
- Node and playwright-core with Chromium. `capture.mjs` looks in the `playwright_core` plugin option
  (passed as `render.py --playwright-core`), then the working directory, then a playwright-cli
  install on PATH, and prints the remedy when none is found.

## Regression

The shfred0 study is the calibration target: every drawing within the `measure.py` target (rotoscope
[`reference/method.md`](skills/rotoscope/reference/method.md), Target). Its per-shot override file ships as a fixture (parameters only; the
clip and traces are not shipped). With the clip and an empty directory:

```bash
python3 plugins/animation/scripts/pydeps.py run --data-dir <plugin data dir> -- \
  plugins/animation/skills/rotoscope/scripts/regress.py <shfred0.mp4> <empty work dir>
```

It exits 0 only when every drawing passes and the encoded replica passes the woodcut-ink pack.
`regress.py --synthetic <empty dir>` needs no unshipped input: it renders, encodes and re-traces the
committed `fixtures/synthetic.js`.

<!-- BEGIN GENERATED: plugin options. Edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. Every option Claude Code
will prompt for when the plugin is enabled, with the environment variable each hook
reads it from.

| Option | Type | Default | Environment variable | Description |
| --- | --- | --- | --- | --- |
| `playwright_core` | directory | *(none)* | `CLAUDE_PLUGIN_OPTION_PLAYWRIGHT_CORE` | The playwright-core package directory, or a folder holding node_modules/playwright-core, to render with. Leave unset to use the working directory's install or a playwright-cli install on PATH. |

### How to set these

Three supported routes, in the order most people want them:

1. **Interactively.** Claude Code prompts for declared options when you enable the
   plugin. To change them later: `/plugin configure animation@<marketplace>`.
2. **Headless.** Repeat `--config` for each option. Replace
   `<marketplace>` with the marketplace you installed this plugin from:

   ```shell
   claude plugin install animation@<marketplace> -s <scope> --config playwright_core=<value>
   ```

   The same command reconfigures a plugin that is **already installed**: it prints
   `already installed` and still writes the value. The short-circuit message is
   about the install, not the config write. Do **not** `claude plugin uninstall` to
   reconfigure: uninstalling drops this plugin's whole stored `pluginConfigs` entry,
   resetting every option in the table above to its default. `-s` defaults to `user`,
   so pass the scope `claude plugin list` reports for this plugin. The verified-version
   record lives in the [plugin-reconfiguration convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/plugin-reconfiguration/README.md).

   The value is stored immediately; the session you are in does not change. Hooks are
   handed their `CLAUDE_PLUGIN_OPTION_*` when the session starts, so start a fresh
   Claude Code session before expecting new behavior. A check run in the old session
   still reports the old value, and that is not a failed write.

3. **By hand, in settings.** Add the value under `pluginConfigs` in your **user**
   settings (`~/.claude/settings.json`):

   ```json
   {
     "pluginConfigs": {
       "animation@<marketplace>": {
         "options": {
           "playwright_core": <value>
         }
       }
     }
   }
   ```

   Plugin option values are read from **user** and managed settings only, **not**
   from a project's `.claude/settings.json`. To vary behavior per repository,
   enable or disable the plugin in that project's `enabledPlugins` instead of
   setting an option there.

Do not set the `CLAUDE_PLUGIN_OPTION_*` variables yourself. They are how Claude Code
hands a configured value to a hook process; the value comes from the routes above.

### Upstream documentation

- [User configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration): the `userConfig` schema and the `CLAUDE_PLUGIN_OPTION_<KEY>` export
- [Plugin install options](https://code.claude.com/docs/en/plugins/cli-reference#plugin-install): the `--config` flag's reference entry
- [Plugins and skills settings](https://code.claude.com/docs/en/settings-reference#plugins-and-skills): `enabledPlugins`, `extraKnownMarketplaces`, `pluginConfigs`
- [Settings files and who they affect](https://code.claude.com/docs/en/settings#settings-files-and-who-they-affect): user vs project vs local precedence
- [Manage installed plugins](https://code.claude.com/docs/en/plugins/install#manage-installed-plugins): enabling, disabling, `/plugin list`

<!-- END GENERATED: plugin options -->
