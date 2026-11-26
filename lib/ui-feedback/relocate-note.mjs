import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { problems, use } from "./note-model.mjs";

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
  const UNMARKED = -1, unmarked = [];
  const p = await page.context().newPage();
  try {
    const vp = note.viewport;
    if (vp) {
      await p.emulateMedia({ colorScheme: vp.colorScheme, reducedMotion: vp.reducedMotion ? "reduce" : "no-preference" });
      await p.setViewportSize({ width: vp.w, height: vp.h });
    }
    await p.goto(url);
    await p.waitForFunction(() => !document.getElementById("pick").disabled, null, { timeout: 15000 });
    if (vp) {
      await p.evaluate(() => { for (const id of ["bar", "panel"]) document.getElementById(id).hidden = true; });
      out.restored.viewport = true;
    }
    const frame = p.frames().find((f) => f !== p.mainFrame());
    const fl = p.frameLocator("#page");
    const show = (d) => frame.evaluate((x) => document.dispatchEvent(new CustomEvent("vs:show", { detail: x })), d);
    const log = note.data?.log, flips = !!log?.some((s) => s.op === "content");
    await show({ variant: note.variant?.key, state: note.state?.key, content: flips ? undefined : note.content });
    if (log) {
      const missed = await frame.evaluate((l) => (window.uiFeedbackRelocate ? window.uiFeedbackRelocate.replay(l) : null), log);
      if (missed === UNMARKED) unmarked.push("data");
      else out.restored.data = missed === 0;
      if (flips) await show({ content: note.content });
    }
    if (note.controls) {
      const missed = await frame.evaluate((v) => (window.uiFeedbackRelocate ? window.uiFeedbackRelocate.setControls(v) : null), note.controls);
      if (missed === UNMARKED) unmarked.push("controls");
      else out.restored.controls = missed === 0;
    }
    if (unmarked.length) out.unmarked = unmarked;
    if (vp) {
      out.restored.scroll = await frame.evaluate((s) => {
        window.scrollTo(s.scrollX, s.scrollY);
        return Math.abs(window.scrollX - s.scrollX) < 1 && Math.abs(window.scrollY - s.scrollY) < 1;
      }, { scrollX: vp.scrollX, scrollY: vp.scrollY }) === true;
    }

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
    const ladder = async (a) => {
      const rungs = [], found = {};
      let container = false;
      const path = a.cssPath === "" ? scope : scope.locator(`:scope > ${a.cssPath}`);
      const pathCount = await count(path);
      if (a.testid !== undefined) {
        const self = (await count(scope.and(fl.getByTestId(a.testid)))) === 1;
        const inner = scope.getByTestId(a.testid);
        const total = (await count(inner)) + (self ? 1 : 0);
        const i = a.testidIndex ?? (total === 1 ? 0 : -1);
        let t = null;
        if (i >= 0 && i < total) t = self ? (i === 0 ? scope : inner.nth(i - 1)) : inner.nth(i);
        if (t && pathCount === 1 && (await path.and(t.locator("*")).count()) === 1) t = path;
        else if (t && (await t.and(fl.locator(a.tag)).count()) !== 1) container = true;
        found.testid = t;
        rungs.push({ rung: "testid", candidates: total, hit: !!t, broken: !t });
      }
      if (a.role !== undefined) {
        const r = scope.locator(`${a.tag}[role~="${a.role}"]`);
        const n = await count(r);
        found.role = n === 1 ? r : null;
        rungs.push({ rung: "role", candidates: n, hit: n === 1, broken: n === 0 });
      }
      found.cssPath = pathCount === 1 ? path : null;
      rungs.push({ rung: "cssPath", candidates: pathCount, hit: pathCount === 1, broken: pathCount === 0 });
      if (a.textQuote !== undefined) {
        const q = { variant: note.variant?.key, state: note.state?.key, quote: a.textQuote };
        const n = scoped ? await frame.evaluate((x) => (window.uiFeedbackRelocate ? window.uiFeedbackRelocate.findQuote(x) : 0), q) : 0;
        found.textQuote = n === 1 ? fl.locator("[data-relocate-quote]") : null;
        rungs.push({ rung: "textQuote", candidates: n, hit: n === 1, broken: n === 0 });
      }
      const result = { rungs, found, ...decide(rungs) };
      if (result.matched === "testid" && container) Object.assign(result, { container, confirmed: false });
      return result;
    };
    const { found, ...source } = await ladder(a);
    Object.assign(out, source);
    if (note.kind === "move") {
      const { found: _f, ...to } = note.to?.anchor ? await ladder(note.to.anchor) : { rungs: [], matched: null, confirmed: false };
      out.to = { ...to, positionOnly: !to.matched };
    }
    if (note.kind === "text" && out.rungs.at(-1).rung === "textQuote" && out.rungs.at(-1).broken) {
      out.quoteMissing = true;
      out.confirmed = false;
    }
    const quoted = found.textQuote, chosen = out.matched && out.matched !== "textQuote" ? found[out.matched] : null;
    if (note.kind === "text" && quoted && chosen
      && (await chosen.and(quoted).count()) + (await chosen.locator("[data-relocate-quote]").count()) === 0) {
      out.quoteElsewhere = true;
      out.confirmed = false;
    }

    let target = out.matched ? found[out.matched] : null;
    if (note.kind === "region" && note.rect) target = null;
    if (!target && note.rect) {
      await frame.evaluate((r) => {
        const root = document.documentElement, w = Math.max(root.scrollWidth, 1), h = Math.max(root.scrollHeight, 1);
        const m = document.createElement("div");
        m.setAttribute("data-relocate-position", "");
        Object.assign(m.style, { position: "absolute", left: `${(r.x / 100) * w}px`, top: `${(r.y / 100) * h}px`,
          width: `${Math.max((r.w / 100) * w, 1)}px`, height: `${Math.max((r.h / 100) * h, 1)}px`, pointerEvents: "none" });
        root.append(m);
      }, note.rect);
      target = fl.locator("[data-relocate-position]");
      out.positionOnly = !(note.kind === "region" && out.matched);
      if (note.kind === "region") out.region = true;
    }
    if (target && !(await target.isVisible())) { out.hidden = true; target = null; }
    if (target) {
      await target.scrollIntoViewIfNeeded();
      const f = await p.locator("#page").boundingBox(), b = await target.boundingBox();
      const x = Math.max(b.x, f.x), y = Math.max(b.y, f.y);
      const clip = { x, y, width: Math.min(b.x + b.width, f.x + f.width) - x, height: Math.min(b.y + b.height, f.y + f.height) - y };
      if (clip.width >= 1 && clip.height >= 1) {
        const style = ".vs { visibility: hidden !important; } [data-ui-feedback-layer] { visibility: hidden !important; }";
        await p.screenshot({ path: shot, clip, style, animations: "disabled" });
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
  const read = (name) => JSON.parse(readFileSync(new URL(name, import.meta.url), "utf8"));
  const schema = read("./note.schema.json");
  use(read("./controls.schema.json"));
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
