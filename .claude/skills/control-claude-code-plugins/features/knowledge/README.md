# knowledge

The skills of `plugins/knowledge`. Each one is driven with `<plugin-dir>` set to `plugins/knowledge`.

## Parts

- `absorb-upstream`: An outside source (a GitHub repository or one web page or post) absorbed into a tracked docs/upstream record: per idea ...
- `book-distill`: Technical book (PDF or EPUB file) distilled into concept-organized reference files for a named target skill, a few ...
- `check`: Read-only check that the external tools the knowledge plugin declares (node, python, yt-dlp, ffmpeg, ImageMagick and ...
- `course-digest`: Online video course (Dometrain, Teachable) extracted lesson by lesson and synthesized into recommendations for the ...
- `docpage-digest`: One online documentation page turned into a verified knowledge slice: the original, section digests, independent ...
- `map-corpus`: Verified, classified map of a multi-resource documentation corpus (a docs site, several URLs, a spec repository) ...
- `setup`: Report (check, the default) or resolve (apply) the knowledge plugin's library_dir against the repository's artifact ... No plain-words entry.
- `video-digest`: Transcript, links and repository-applicability recommendations from one public YouTube or X (Twitter) video.

## Sub-features

none

## Entry points

- `/knowledge:<skill> <args>` as the `logs` prompt, in print mode | driven
- `/knowledge:<skill> <args>`, typed at the prompt of the terminal session | driven
- A request in plain words that names the skill's job, typed at the prompt | driven
- The same skill in Claude Desktop | not driven: terms

## Reset

The `## Reset` of the driving tool's `skills/invoke` feature.

## Drive

Drive the skill as the driving tool's `skills/invoke` feature, with `<plugin>` set to `knowledge` and
`<skill>` from Parts. The skill's own `plugins/knowledge/skills/<skill>/SKILL.md` gives its arguments.

## Gotchas

- A skill marked `No slash command.` runs only from its plain-words entry point; one marked `No plain-words entry.` runs only from its slash command.
