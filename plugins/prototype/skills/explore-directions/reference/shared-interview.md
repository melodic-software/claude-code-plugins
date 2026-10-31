# For a shared interview

When `/planning:interview`'s shared session asks for the variants, it hands over its data dir, the
prototype tiers the session offers (`screenshot`, `snapshot`, `live`) and the variant keys. Build
the variants as [SKILL.md](../SKILL.md) says, then emit each offered tier and nothing the session does not offer:

| Tier | Emit per variant | Rules |
|---|---|---|
| Screenshots | One to four PNG files, in viewing order | Captured at 2x with `/playwright:playwright` when it is among the available skills, after using the variant's main control once; without it, emit no screenshots and say so |
| HTML snapshot | One self-contained HTML file, with no switcher unless it prototypes the interview page itself (below) or the plan lists states, since the interview's prototype page tabs between variants; for states, the bundled switcher steps through them | Starts with `<!doctype html>`, at most 10 MB, every style, script, image and font inline; the interview serves it with no network access, so a fetch fails |
| Live | One static build folder for all variants: `index.html` plus its files, picking the variant from `?variant=<key>` and, when the plan lists states, the state from `?state=<key>` | Every script, style, image and font in its own file in the folder: the live server allows same-origin files only, so inline `<script>`, inline `<style>`, `data:` URLs and the mockup's CSP meta tag are blocked. Synthetic fixtures in a JSON file, every write stubbed in memory, relative or root-absolute URLs, no remote origin, no service worker, no secret or `.env` content. Regular files only (no hidden name, symlink or hard link), at most 2,000 files and 50 MB |

A live prototype on the real stack is a server the owner runs: build one only when the owner asks
for it and gives its port, seeded with sample data, its writes stubbed and no credentials in its
environment.

- **Placement.** Write everything under `<data_dir>/staging/<run>/`, `<run>` with no leading
  dot, never a `mktemp` or system temp directory: the interview copies files only from inside its
  data dir. Keep the folder: the owner's Approve copies the live build from it, and a change made
  after Approve is not served. SKILL.md step 5's deletion does not apply to it.
- **Manifest.** Write `<data_dir>/staging/<run>/manifest.json`, which the interview reads to add
  each file. Paths are relative to the data dir:

  ```json
  {"lookAt": "Open the chat with the round button at bottom right, then switch variants",
   "variants": [{"key": "A", "label": "Dense table", "lookAt": "optional, when it differs",
     "shots": ["staging/r1/A-1.png"], "snapshot": "staging/r1/A.html",
     "live": {"folder": "staging/r1/live", "path": "/?variant=A"}}]}
  ```

  `live` names a `port` in place of `folder` for an owner-run server.
- **Where to look, always.** Every manifest carries a top-level `lookAt`, one line of at most 200
  characters naming the area the variants change and the step that shows it; the interview refuses
  a prototype question without one. Add a variant's own `lookAt` when where to look differs for it.
- **A prototype of the interview page itself.** Keep the in-page switcher in each view, show the
  `lookAt` line on it, and when a variant is picked, open the area that changes (the chat, a
  dialog) or scroll to it and outline it.
- **A prototype of any other app** shows its snapshot on the interview's prototype page; its live
  build is never framed there, and the page opens it in a new tab.
- **Handover.** Hand over the manifest path in place of a `file://` path or route URL, plus the
  tradeoffs table. People answer through the interview's question, so the reply template and the
  copy-out terminator are not needed; step 5 reads the test ids from each snapshot's markup.
