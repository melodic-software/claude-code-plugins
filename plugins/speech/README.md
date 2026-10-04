# speech

Text-to-speech narration for Claude Code. `/speech:narrate` turns a script into `narration.wav`
plus `words.json`, which gives a start and end time for every word. A video, a caption track or an
interactive page can then follow the voice word by word.

## Skills

| Skill | What it does |
|---|---|
| `/speech:narrate <script>` | Writes `narration.wav` (24 kHz mono) and `words.json` (one `{word, start, end}` per script word) |
| `/speech:check` | Read-only: one PASS or FAIL row per prerequisite, each FAIL with its remedy |
| `/speech:setup [check \| apply install-model]` | `check` is the same report; `apply install-model` downloads the pinned model files |

## The kokoro backend

kokoro is the default backend. It runs [Kokoro-82M](https://huggingface.co/hexgrad/Kokoro-82M)
(Apache-2.0) on your CPU through onnxruntime and sends nothing over the network while it speaks.
It uses the
[timestamped ONNX export](https://huggingface.co/onnx-community/Kokoro-82M-v1.0-ONNX-timestamped),
which reports how long each input token lasts, so the word timings come from the model itself.
`scripts/kokoro-assets.json` pins the revision and the sha256 of every file: the fp32 model,
its tokenizer, and the 28 English voices.

espeak-ng turns each word into the phonemes Kokoro reads. **espeak-ng is GPL-3.0, so you install
it; the plugin never installs, downloads or ships it.** The plugin also avoids the Python packages
that bundle it (`espeakng-loader`) or wrap it under the GPL (`phonemizer`): it runs your
`espeak-ng` command directly.

## The elevenlabs backend (optional, third-party)

`scripts/elevenlabs.py` sends the script text to the [ElevenLabs](https://elevenlabs.io) REST API at
`api.elevenlabs.io` and writes the same two files. It is off unless you ask for it by name. The
official ElevenLabs MCP server is archived, so the plugin calls the REST API directly with the Python
standard library.

- **Key.** Set `ELEVENLABS_API_KEY` in your shell environment, or leave it unset with `vault-exec`
  on `PATH`: the script then runs itself under
  `vault-exec --env ELEVENLABS_API_KEY=elevenlabs-api-key`, so the key exists only in that one
  process. The plugin never stores, prints or logs it, never takes it as an argument, and sends it
  only in the `xi-api-key` request header.
- **Quota statement before every call.** The script prints the character count, the host, the model
  and voice, your plan's remaining character quota (from `GET /v1/user/subscription`) and a link to
  the pricing page, then stops. It states no prices. `--proceed` is required to send anything, and
  the skill passes it only after you agree.
- **Cache.** An identical request (text, voice, model, voice settings, output format) reuses the
  stored audio and timings from `<plugin data>/elevenlabs-cache/` with no call and no key. When no
  plugin data directory resolves, the cache is `$XDG_CACHE_HOME/claude-speech/elevenlabs` (default
  `~/.cache`). `--no-cache` makes a fresh call.
- **Retries.** HTTP 429 and 5xx are retried with jittered exponential backoff, honoring
  `Retry-After`; 401, 422 and other client errors fail at once with the API's error code and
  message. `words.json` records the call's `request-id` and `character-cost` headers.
- **Model.** The `elevenlabs_model` option sets the default model; the script's `MODELS` table lists
  the models it accepts and marks `eleven_v4` unverified on the timed endpoint.
  [reference/elevenlabs.md](reference/elevenlabs.md) points at the live ElevenLabs docs.
- **Organization egress floor.** Managed settings can set `SPEECH_EGRESS_FLOOR=local` in `env`.
  Managed settings outrank every other settings layer, so a user cannot unset it. The backend then
  exits 4 with the reason, before it reads the key or prints an estimate. An unrecognized value is
  treated as `local`; `any` or unset allows the backend.
- **Text to speech only.** No voice cloning, speech-to-text or other ElevenLabs endpoints.

Word times come from the API's per-character alignment: a word spans its first to its last character.

## Prerequisites

| Prerequisite | Installed by | Needed for |
|---|---|---|
| `ELEVENLABS_API_KEY` (optional) | you | the elevenlabs backend only |
| Python 3.12 or later | you | the install hook and every script |
| Node.js | you | starting the SessionStart hook |
| espeak-ng | you (`apt`/`dnf`/`pacman`/`brew install espeak-ng`, `winget install eSpeak-NG.eSpeak-NG`) | `/speech:narrate` |
| numpy, onnxruntime | the SessionStart hook | `/speech:narrate` |
| Kokoro model, tokenizer, voices (about 340 MB) | `/speech:setup apply install-model`, into the `model_dir` option's folder when set | `/speech:narrate` |

`prerequisites.json` declares the tools, with their install hints and what stops without each
one. `/speech:check` reads it.

The Python packages follow the
[on-demand dependencies convention](../../docs/conventions/on-demand-dependencies/README.md#python).
`requirements.in` pins them, `requirements.txt` hash-locks every wheel, and the SessionStart hook
installs them into `${CLAUDE_PLUGIN_DATA}/python/<lock hash>-<interpreter>/` with
`pip install --require-hashes --only-binary :all:`. Nothing else installs a package. A failed
install shows a notice at session start with the repair command.

## Output

`words.json`:

```json
{
  "audio": "narration.wav",
  "sample_rate": 24000,
  "duration": 13.625,
  "backend": "kokoro",
  "voice": "af_heart",
  "speed": 1.0,
  "words": [
    { "word": "Hello,", "start": 0.352, "end": 0.823 },
    { "word": "world.", "start": 0.939, "end": 1.62 }
  ]
}
```

Each whitespace-separated token of the script is one entry, in script order. A word's span covers
its own sounds, not the pause after its punctuation. A token that is only punctuation, such as a
dash, spans its pause.

## Tests

```bash
bash plugins/speech/scripts/speech.test.sh
bash plugins/speech/hooks/install-python-deps.test.sh
```

Set `SPEECH_E2E_DATA_DIR` to a data directory that holds the installed packages and the model, with
espeak-ng on `PATH`, to also run a real narration.

<!-- BEGIN GENERATED: plugin options. Edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. Every option Claude Code
will prompt for when the plugin is enabled, with the environment variable each hook
reads it from.

| Option | Type | Default | Environment variable | Description |
| --- | --- | --- | --- | --- |
| `elevenlabs_model` | string | *(none)* | `CLAUDE_PLUGIN_OPTION_ELEVENLABS_MODEL` | Model id the elevenlabs backend uses when a run names none, one of the ids in the MODELS table of scripts/elevenlabs.py. Unset keeps the script's default. |
| `model_dir` | directory | *(none)* | `CLAUDE_PLUGIN_OPTION_MODEL_DIR` | Folder that holds the downloaded Kokoro model set (a kokoro-<revision> subfolder per pin), for a larger disk or one cache shared across worktrees and plugins. Unset keeps it under the plugin data directory's models folder. |

### How to set these

Three supported routes, in the order most people want them:

1. **Interactively.** Claude Code prompts for declared options when you enable the
   plugin. To change them later: `/plugin configure speech@<marketplace>`.
2. **Headless.** Repeat `--config` for each option. Replace
   `<marketplace>` with the marketplace you installed this plugin from:

   ```shell
   claude plugin install speech@<marketplace> -s <scope> --config elevenlabs_model=<value>
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
       "speech@<marketplace>": {
         "options": {
           "elevenlabs_model": <value>
         }
       }
     }
   }
   ```

   Plugin option values are read from **user**, `--settings`, and managed settings
   only, **not** from a project's `.claude/settings.json`. To vary behavior per
   repository, enable or disable the plugin in that project's `enabledPlugins`
   instead of setting an option there.

Do not set the `CLAUDE_PLUGIN_OPTION_*` variables yourself. They are how Claude Code
hands a configured value to a hook process; the value comes from the routes above.

### Upstream documentation

- [User configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration): the `userConfig` schema and the `CLAUDE_PLUGIN_OPTION_<KEY>` export
- [Plugin install options](https://code.claude.com/docs/en/plugins/cli-reference#plugin-install): the `--config` flag's reference entry
- [Plugins and skills settings](https://code.claude.com/docs/en/settings-reference#plugins-and-skills): `enabledPlugins`, `extraKnownMarketplaces`, `pluginConfigs`
- [Settings files and who they affect](https://code.claude.com/docs/en/settings#settings-files-and-who-they-affect): user vs project vs local precedence
- [Manage installed plugins](https://code.claude.com/docs/en/discover-plugins#manage-installed-plugins): enabling, disabling, `/plugin list`

<!-- END GENERATED: plugin options -->
