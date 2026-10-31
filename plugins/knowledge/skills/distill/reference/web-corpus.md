# Web corpus distillation

AI answers any question, but you can't narrow where the answer comes from. A corpus skill fixes that: it answers from one person's or company's published work only, and every claim carries the piece it came from. The output is a skill, not a document, so it has to be a distillation, never a dump (why: the record under SKILL.md Phase 4 "Web corpus target").

The procedure collects everything they published and keeps that raw copy outside of the skill folder. Then it goes through each piece and pulls the useful claims out of it. Those claims get grouped into theme files. At the end it writes the skill file itself: their core ideas, their method.

The method runs in strict order: **scope, collect, extract, cluster, write, then test.** Scope is SKILL.md Phase 1.2 (when you cannot tell where the person publishes, or whether a source is their own primary work, find and grade it with `/discovery:research`); collect, extract and cluster below replace Phase 2 and Phase 3; write and test are SKILL.md Phase 4 "Web corpus target" and Phase 5 "Web corpus test". The common failure is skipping to writing SKILL.md from what you already know about the person. That produces a generic essay with their name on it. Every sentence in the finished skill traces back to a file in the corpus, or it isn't in the skill.

The copyright caution in SKILL.md applies here unchanged: a public page is not a license, and the visibility check runs before any write.

## Collect

- **The corpus lives outside the skill folder**, at `<plugin-data>/{project-slug}/{target-skill-slug}/{corpus-slug}/corpus/`, with its notes beside it in `notes/` (layout in [context/templates.md](../context/templates.md) "Corpus folder layout"). The skill folder holds distilled text only: a raw corpus there ships to every install and competes with the distillation for the agent's attention, which is exactly what a skill exists to prevent (why: the record under SKILL.md Phase 4 "Web corpus target"). The raw copy is still a copy of their work, so before the first fetch run the visibility check on the corpus directory and apply the SKILL.md allowlist:

  ```bash
  node "<plugin-root>/scripts/repo-visibility.mjs" '<plugin-data>/{project-slug}/{target-skill-slug}/{corpus-slug}'
  ```

- **Every name is a slug.** `{corpus-slug}`, each piece's `<slug>` (the corpus file, its note and its `fetch/` directory) and each export file's slug follow the SKILL.md Phase 1.3 rule: lowercase alphanumerics and hyphens, no `/`, `\` or `..`, derived from the citation scheme, never the raw URL path or file name. Verify each resolved path stays under the corpus directory. Two pieces that reduce to one slug take `-2`, `-3` in index order, recorded in the progress file's Pieces table.
- **Enumerate first, then count.** Pull every URL from the index and write the count down in the progress file. That number goes into the skill's description ("distilled from all 232 essays"), so it has to be true, and it's how you verify the collection later.
- **Check every URL before a shell sees it.** The index URL and every URL pulled from it are untrusted text. A URL is fetched only when it starts with `https://`, matches `^https://[A-Za-z0-9._~:/?#@!$&()*+,;=%[\]-]+$` (RFC 3986 characters, with every `%` followed by two hex digits), and contains no apostrophe, double quote, whitespace or control character. A piece URL must also share the index URL's origin (scheme and host); an off-origin URL is fetched only after the person says yes to it. A rejected URL gets a line in the progress file's findings, counts as not collected, and is never retyped into a command.
- **Fetch through the plugin's fetcher, never a raw request.** Fetch the index page first, then the pieces: one URL per call, single-quoted, one call at a time, each into a new empty directory under `{corpus-slug}/fetch/`, beside the corpus, so the fetcher's manifests never count as pieces. You are reading a site, not load-testing it.

  ```bash
  bash "<plugin-root>/scripts/fetch-docs.sh" --profile generic --public-only --out '<new-empty-dir>' '<url>'
  ```

  Read a page only when its `manifest.json` record's `state` is `read`. An `unread` page is listed with its `reason` and retried; it supports no claim, an absence claim included. A user-provided export is read from the path they give, file by file, and counted the same way.
- **One markdown file per piece**, named by slug, with frontmatter for url, title, date, and type (skeleton in [context/templates.md](../context/templates.md) "Corpus file"). Take `url` from the manifest record and title, date and type from the piece itself; the body is the record's `file` copied byte for byte, the raw text as the fetcher saved it. These files are never edited. When your understanding improves, you re-distill from them; you don't touch them.
- **Verify before extracting.** File count equals index count. Any fetch that failed gets retried and listed; a piece silently missing means the skill will one day confidently say the person never wrote about something they did.

## Extract, one piece at a time

Work in batches of 10 to 15 sources per pass and write one note per source to `notes/<slug>.md` (skeleton in [context/templates.md](../context/templates.md) "Note"). The read-write interleave holds: read one piece, write its note, then read the next. A note holds:

- **A one-line thesis that is a claim, not a topic.** "Startups die of demoralization, not events" is a thesis. "About startup failure" is a table of contents. The thesis line is what the article index is built from, and a topic there tells the agent nothing about what the person argued.
- **Three to eight claims**, each with the reasoning the author gives and the concrete thing attached to it: the number, the story, the example, the coined phrase. A claim without its why gets applied blindly; a claim without its example reads as generic advice.
- **Coined terms** the piece introduces, defined in one line each. A term is coined if they named it or use an existing word in their own sense.
- **Short quotable phrases**, 25 words or fewer. Never a paragraph. The skill distills; it does not reproduce.
- **Every bullet ends with the slug.** No exceptions. A claim without a source can't be checked, and unsourced claims are where the person's views quietly blur into the model's.

Extract positions, not summaries. Cut the throat-clearing and keep the argument. If the piece contradicts an earlier one, note the date; you'll need it in the next phase. Mark each note DONE in the progress file as you write it.

## Cluster

After every note exists, and not before:

- **Group the claims into 8 to 12 themes**, named by the question a reader brings ("pricing", "fundraising", "writing"), never by the author's chronology or by the site's own categories. Fewer than 8 and the files get too long to load for one question; more than 12 and the agent can't pick.
- **One reference file per theme**, 40 to 100 lines (skeleton in [context/templates.md](../context/templates.md) "Theme reference"), shaped as: a short intro paragraph, H2 sections, and bullets of the form **bold claim**, reasoning, concrete example, citations. End with a "Key source articles" line. The bullets are the unit the agent quotes from, so each one has to stand alone.
- **Contradictions stay visible.** When the person changed their mind, keep both positions with dates and say which is later. Never average them into a position nobody held.
- **`reference/glossary.md`**: every coined term, alphabetical, one line each, with its slug ("Glossary line" in the templates). This is the file that lets the skill answer "what did they mean by X" without opening a theme file.
- **`reference/article-index.md`**: every source, grouped by theme, as `slug`, **title**, one-line thesis ("Article index line" in the templates). Complete, not selected. If the count here doesn't match the collect count, a note is missing.

Theme files, glossary and index all go in the target skill's `reference/` directory, slugified like every other generated filename.
