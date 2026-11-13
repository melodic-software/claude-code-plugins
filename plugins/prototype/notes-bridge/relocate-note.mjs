// GENERATED from lib/ui-feedback/relocate-note.mjs by scripts/sync-shared-copies.sh. Do not edit this copy:
// edit the canonical source, then rerun the script.
// Re-locate one note in a fresh page (docs/contracts/ui-feedback, "Re-locating a note").
//
//   node relocate-note.mjs --dir <run dir> --seq <n> --url <host url>
//
// Reads note <n> from <run dir>/actions.json, the notes bridge's log, checks it against
// note.schema.json with note-model.mjs, and writes <run dir>/relocate-<n>.js: a playwright-cli
// run-code script whose only input is one JSON literal. It prints {"script", "shot"}; run the
// script with `playwright-cli run-code --filename <script>`. The script opens the host page at
// <url> in a new page, restores the note's variant, screen state and content set through the
// switcher's vs:show event, runs the anchor ladder inside the sandboxed frame, and saves
// <run dir>/shots/<n>.png: the element, or the note's stored box when no rung finds it. File
// names come from the integer seq only. It returns which rung matched and each rung's candidate
// count, never page text.

import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { problems } from "./note-model.mjs";

/** The rung that found the note's element: the first that hit. It is confirmed only when no
 *  stronger rung the note carries came back broken (its anchor finds nothing), since a weaker
 *  rung matching where a stronger one broke is a guess. */
export function decide(rungs) {
  let broken = false;
  for (const r of rungs) {
    if (r.hit) return { matched: r.rung, confirmed: !broken };
    broken = broken || r.broken;
  }
  return { matched: null, confirmed: false };
}

/** The run-code body. Self-contained: script() inlines its source, so it may use nothing from
 *  this module but the `decide` it is handed. Selectors take only schema-checked keys and paths;
 *  every value reaches the frame as an evaluate() argument, never as code. */
export async function relocate(page, input, decide) {
  const { note, url, shot } = input;
  const a = note.anchor;
  const out = { seq: input.seq, restored: {}, rungs: [], matched: null, confirmed: false, positionOnly: false, shot: null };
  const p = await page.context().newPage();
  try {
    await p.goto(url);
    await p.waitForFunction(() => !document.getElementById("pick").disabled, null, { timeout: 15000 });
    const frame = p.frames().find((f) => f !== p.mainFrame());
    const fl = p.frameLocator("#page");
    await frame.evaluate((d) => document.dispatchEvent(new CustomEvent("vs:show", { detail: d })),
      { variant: note.variant?.key, state: note.state?.key, content: note.content });

    // The scope, as the pin helper takes it: the screen state inside the variant, else the variant, else the page.
    let scope = fl.locator(":root"), scoped = true;
    for (const [part, attr] of [["variant", "data-variant"], ["state", "data-screen-state"]]) {
      if (!note[part]) continue;
      const s = scope.locator(`[${attr}="${note[part].key}"]`);
      const n = await s.count();
      out.restored[part] = n === 1 && await s.isVisible();
      scoped = scoped && n === 1;
      scope = s;
    }
    if (note.content) out.restored.content = (await fl.locator(`:root[data-vs-content="${note.content}"]`).count()) === 1;

    const count = async (l) => (scoped ? l.count() : 0);
    const path = a.cssPath === "" ? scope : scope.locator(`:scope > ${a.cssPath}`);
    const pathCount = await count(path);
    const found = {};

    if (a.testid !== undefined) {
      // The pin helper counts the scope itself first, then the elements with the id inside it.
      const self = (await count(scope.and(fl.getByTestId(a.testid)))) === 1;
      const inner = scope.getByTestId(a.testid);
      const total = (await count(inner)) + (self ? 1 : 0);
      const i = a.testidIndex ?? (total === 1 ? 0 : -1);
      let t = null;
      if (i >= 0 && i < total) t = self ? (i === 0 ? scope : inner.nth(i - 1)) : inner.nth(i);
      if (t && (await t.and(fl.locator(a.tag)).count()) !== 1) {
        // The id sits on an ancestor of the noted element: the path finds it inside, else the ancestor stands in.
        if (pathCount === 1 && (await path.and(t.locator("*")).count()) === 1) t = path;
        else out.container = true;
      }
      found.testid = t;
      out.rungs.push({ rung: "testid", candidates: total, hit: !!t, broken: !t });
    }
    if (a.role !== undefined) {
      const r = scope.locator(`${a.tag}[role="${a.role}"]`);
      const n = await count(r);
      found.role = n === 1 ? r : null;
      out.rungs.push({ rung: "role", candidates: n, hit: n === 1, broken: n === 0 });
    }
    found.cssPath = pathCount === 1 ? path : null;
    out.rungs.push({ rung: "cssPath", candidates: pathCount, hit: pathCount === 1, broken: pathCount === 0 });
    Object.assign(out, decide(out.rungs));
    // An ancestor standing in for an element the ladder never found is a guess, never a confirmed match.
    if (out.matched === "testid" && out.container) out.confirmed = false;

    let target = out.matched ? found[out.matched] : null;
    if (!target && note.rect) {
      // A transparent box at the stored position, so the shot scrolls the frame there as it does for an element.
      await frame.evaluate((r) => {
        const root = document.documentElement, w = Math.max(root.scrollWidth, 1), h = Math.max(root.scrollHeight, 1);
        const m = document.createElement("div");
        m.setAttribute("data-relocate-position", "");
        Object.assign(m.style, { position: "absolute", left: `${(r.x / 100) * w}px`, top: `${(r.y / 100) * h}px`,
          width: `${Math.max((r.w / 100) * w, 1)}px`, height: `${Math.max((r.h / 100) * h, 1)}px`, pointerEvents: "none" });
        root.append(m);
      }, note.rect);
      target = fl.locator("[data-relocate-position]");
      out.positionOnly = true;
    }
    if (target && !(await target.isVisible())) { out.hidden = true; target = null; }
    if (target) {
      await target.scrollIntoViewIfNeeded();
      // The clip stays inside the frame's box, so no pixel of the host page's own chrome is in the shot.
      const f = await p.locator("#page").boundingBox(), b = await target.boundingBox();
      const x = Math.max(b.x, f.x), y = Math.max(b.y, f.y);
      const clip = { x, y, width: Math.min(b.x + b.width, f.x + f.width) - x, height: Math.min(b.y + b.height, f.y + f.height) - y };
      if (clip.width >= 1 && clip.height >= 1) {
        await p.screenshot({ path: shot, clip, style: ".vs { visibility: hidden !important; }", animations: "disabled" });
        Object.assign(out, { shot, clip, frame: f });
      }
    }
  } finally {
    await p.close();
  }
  return JSON.stringify(out);
}

/** The run-code script for one input: the input enters as a single JSON literal. One expression,
 *  no trailing semicolon: run-code evaluates the file as a function expression. */
export const script = (input) => `async page => (${relocate})(page, ${JSON.stringify(input)}, ${decide})\n`;

const fail = (msg) => { console.error(`relocate-note: ${msg}`); process.exit(2); };

export function main(argv) {
  const args = {};
  for (let i = 0; i < argv.length; i += 2) {
    if (!/^--(dir|seq|url)$/.test(argv[i]) || argv[i + 1] === undefined) fail(`usage: --dir <run dir> --seq <n> --url <host url>`);
    args[argv[i].slice(2)] = argv[i + 1];
  }
  if (!args.dir || !args.seq || !args.url) fail("usage: --dir <run dir> --seq <n> --url <host url>");
  if (!/^[1-9][0-9]{0,8}$/.test(args.seq)) fail("--seq is the note's integer seq");
  if (!/^http:\/\/127\.0\.0\.1:[0-9]{1,5}\/$/.test(args.url)) fail("--url is the host url ensure-running printed");
  const dir = resolve(args.dir), seq = Number(args.seq);
  const schema = JSON.parse(readFileSync(new URL("./note.schema.json", import.meta.url), "utf8"));
  const event = (JSON.parse(readFileSync(join(dir, "actions.json"), "utf8")).events || []).find((e) => e.seq === seq);
  if (!event) fail(`no note ${seq} in ${join(dir, "actions.json")}`);
  const { seq: _s, at: _a, deliveredAt: _d, ...note } = event;
  const found = problems(note, schema);
  if (found.length) fail(`note ${seq} is outside the note contract: ${found[0]}`);
  mkdirSync(join(dir, "shots"), { recursive: true, mode: 0o700 });
  const out = { script: join(dir, `relocate-${seq}.js`), shot: join(dir, "shots", `${seq}.png`) };
  writeFileSync(out.script, script({ seq, url: args.url, note, shot: out.shot }), { mode: 0o600 });
  console.log(JSON.stringify(out));
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) main(process.argv.slice(2));
