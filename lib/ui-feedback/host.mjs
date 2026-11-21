import { draftStore, problems, readerName, use } from "/note-model.mjs";
import { awaitReady, chosenFrom, frameTarget, fromFrame, namesFrom, READY_MS, viewFrom } from "/frame-channel.mjs";

const $ = (id) => document.getElementById(id);
const frame = $("page"), composer = $("composer"), text = $("text");
const devOrigin = frame.dataset.devOrigin || null;
const target = frameTarget(devOrigin, frame.dataset.mockupTarget || null);
let heard = () => {};
const buttons = { element: $("pick"), region: $("region"), move: $("move") };
const say = (t) => { $("status").textContent = t; $("said").textContent = $("panel").hidden ? t : ""; };
let schema = null, cschema = null, token = null, ready = false, loads = 0, picking = null, wantText = false, draft = null, noSession = false;
let editing = null, opener = null, ids = 0, sending = false;
let reshaping = null;
const mine = [];
const shown = new Map();
let last = { listening: "idle", notes: [] };
let chosen = null;
let view = { variants: [], variant: null, states: [], state: null }, filter = "all";

const fits = (value, node) => value !== undefined && problems(value, schema, node).length === 0;
const toFrame = (m) => { if (target && ready && loads < 2) frame.contentWindow.postMessage(m, target); };
const live = () => ready && loads < 2;
const QUOTE = () => schema.$defs.anchor.properties.textQuote;

const C = window.uiFeedbackControls;
let controls = [], values = {}, builtins = [], steps = [], content = null;
function takeControls(m) {
  const P = schema.properties;
  const found = m.controls == null || m.controls === false ? [] : problems(m.controls, cschema, cschema, "manifest");
  const list = m.controls && !found.length ? m.controls.controls : [];
  const refused = C.refused(list);
  controls = refused ? [] : list;
  values = C.defaults(controls);
  steps = (Array.isArray(m.data) ? m.data : []).filter((st) => fits(st, schema.$defs.dataStep)).slice(0, cschema.properties.controls.maxItems)
    .map((st, i) => ({ id: `@data-${i}`, label: [st.op, st.n ?? st.name].filter((x) => x !== undefined).join(" "), group: "data", type: "action", press: st }));
  builtins = [];
  if (fits(m.content, P.content)) {
    content = m.content;
    builtins.push({ id: "@content", label: "Worst content", group: "content", type: "toggle", options: P.content.enum, default: m.content, content: true });
  }
  $("controls-status").textContent = found.length ? `The mockup's controls manifest is outside the controls contract (${found[0]}), so only its built-in controls are here.`
    : refused ? `The mockup's controls manifest is refused (${refused}), so only its built-in controls are here.`
    : m.controls === false ? "The mockup's controls manifest is not JSON, so only its built-in controls are here."
    : m.controls == null ? "The mockup has no controls manifest." : `${controls.length} control(s) from the mockup's manifest.`;
  for (const b of [$("copy-config"), $("reset-controls"), $("copy-values")]) b.disabled = !controls.length;
  $("copy-chosen").disabled = m.copyOut !== true;
  renderControls();
  renderSteps();
}
function renderControls() {
  const focused = document.activeElement?.id;
  $("controls-list").replaceChildren(C.panel(document, [...controls, ...builtins], { ...values, "@content": content }, change));
  if (focused?.startsWith("uifc-")) $(focused)?.focus();
}
function renderSteps() {
  $("data-wrap").hidden = !steps.length;
  $("data-list").replaceChildren(...steps.map((st) => {
    const b = document.createElement("button");
    b.type = "button";
    b.className = "btn";
    b.textContent = st.label;
    b.addEventListener("click", () => { change(st); closeMenus(); $("data").focus(); });
    return b;
  }));
}
const sayControls = (t) => { $("controls-said").textContent = t; };
function change(c, v) {
  if (picking) setPick(null);
  sayControls("");
  if (c.press) toFrame({ type: "press", step: c.press });
  else if (c.content) toFrame({ type: "press", step: { op: "content", name: v } });
  else { values[c.id] = v; toFrame({ type: "set", values: { [c.id]: v } }); }
}
function copyConfig() {
  $("config").value = C.config(controls, values);
  $("config-out").hidden = false;
  $("config").select();
  const done = () => sayControls("Copied the config. Paste it to Claude.");
  if (navigator.clipboard) navigator.clipboard.writeText($("config").value).then(done, () => sayControls("Select the config below and copy it."));
  else sayControls("Select the config below and copy it.");
}
function resetControls() {
  values = C.defaults(controls);
  toFrame({ type: "set", values });
  renderControls();
  sayControls("The controls are back at their defaults; the data is unchanged.");
}

const tabs = [$("tab-notes"), $("tab-controls")];
/** Show one tab's panel, as the WAI-ARIA tabs pattern does: only the selected tab is in the tab order. */
function selectTab(tab, focus = true) {
  for (const t of tabs) {
    t.setAttribute("aria-selected", String(t === tab));
    t.tabIndex = t === tab ? 0 : -1;
    $(t.getAttribute("aria-controls")).hidden = t !== tab;
  }
  $("filters").hidden = tab !== tabs[0];
  if (tab !== tabs[0] && picking) setPick(null);
  if (focus) tab.focus();
}

/** The bar's menus, each a disclosure: its button and the group it shows. */
const MENUS = [[$("view"), $("view-menu")], [$("data"), $("data-menu")], [$("copy-button"), $("copy-menu")]];
const openMenu = () => MENUS.find(([, m]) => !m.hidden);
function closeMenus() {
  for (const [b, m] of MENUS) { m.hidden = true; b.setAttribute("aria-expanded", "false"); }
}
function toggleMenu(button) {
  const was = openMenu()?.[0];
  closeMenus();
  if (was === button) return;
  const menu = MENUS.find(([b]) => b === button)[1];
  menu.hidden = false;
  button.setAttribute("aria-expanded", "true");
  menu.querySelector("button:not(:disabled)")?.focus();
}

/** The bar's view: the shown variant's key, name and screen state, and a menu of the page's variants and states. */
const labelOf = (list, key) => list.find((x) => x.key === key)?.label || "";
function renderView() {
  const has = view.variants.length > 0;
  $("view-wrap").hidden = $("view-sep").hidden = !has;
  if (!has) return;
  const name = labelOf(view.variants, view.variant), state = labelOf(view.states, view.state) || view.state || "";
  $("view-key").textContent = view.variant ? `${view.variant} ` : "";
  $("view-name").textContent = state ? `${name}, ` : name;
  $("view-state").textContent = state.toLowerCase();
  $("view").setAttribute("aria-label", `View: ${[view.variant, name, state].filter(Boolean).join(" ")}`);
  for (const b of [$("vprev"), $("vnext")]) b.disabled = view.variants.length < 2 || !live();
  const item = (key, label, current, show) => {
    const b = document.createElement("button");
    b.type = "button";
    b.className = "btn";
    b.textContent = label ? `${key} ${label}` : key;
    b.setAttribute("aria-current", String(current));
    b.addEventListener("click", () => { toFrame({ type: "view", ...show }); closeMenus(); $("view").focus(); });
    return b;
  };
  const title = (t) => Object.assign(document.createElement("p"), { className: "group-title", textContent: t });
  const parts = [title("Variant"), ...view.variants.map((v) => item(v.key, v.label, v.key === view.variant, { variant: v.key }))];
  if (view.states.length) {
    parts.push(Object.assign(document.createElement("div"), { className: "hsep" }), title("Screen state"),
      ...view.states.map((s) => item(s.label || s.key, "", s.key === view.state, { state: s.key })));
  }
  $("view-menu").replaceChildren(...parts);
}
function stepVariant(d) {
  const i = view.variants.findIndex((v) => v.key === view.variant), n = view.variants.length;
  if (n > 1) toFrame({ type: "view", variant: view.variants[(i + d + n) % n].key });
}

/** Turn pick mode on for one kind ("element", "region" or "move"), or off; a region starts at `rect` when given. */
function setPick(kind, rect = null) {
  picking = kind && live() ? kind : null;
  reshaping = null;
  if (picking && chosen) unchoose(false);
  if (picking) selectTab(tabs[0], false);
  closeMenus();
  for (const [k, b] of Object.entries(buttons)) b.setAttribute("aria-pressed", String(picking === k));
  toFrame({ type: "mode", on: !!picking, kind: picking || "element", max: schema?.$defs.elements.maxItems, hold: true, ...(rect ? { rect } : {}) });
  say(picking === "element" ? "Click an element in the mockup to pin a note to it. Esc cancels."
    : picking === "region" ? "Drag a box over the mockup (near its top or bottom edge to scroll), drag the box to move it or its edges to resize it, or use the arrow keys (Shift+arrows resize) and press Enter. Esc cancels."
    : picking === "move" ? "Click the element to move, then the element it should go to; Shift+click picks a point instead. Esc cancels."
    : "");
}
function askText() {
  if (!live()) return;
  setPick(null);
  wantText = true;
  const q = QUOTE().properties;
  toFrame({ type: "text", exact: q.exact.maxLength, context: q.prefix.maxLength });
}

/** An anchor's fields the contract admits; null when what is left is not an anchor. */
function anchorFrom(a) {
  if (!a || typeof a !== "object") return null;
  const A = schema.$defs.anchor.properties, out = {};
  for (const k of Object.keys(A)) if (k !== "textQuote" && fits(a[k], A[k])) out[k] = a[k];
  if (!("testid" in out)) delete out.testidIndex;
  return fits(out, schema.$defs.anchor) ? out : null;
}
/** The note a message becomes: only the fields note.schema.json admits, never the helper's label. */
function noteFrom(m, kind) {
  const anchor = anchorFrom(m.anchor);
  if (!anchor) return null;
  const P = schema.properties, s = m.snapshot && typeof m.snapshot === "object" ? m.snapshot : {};
  const note = { kind, anchor };
  for (const k of ["variant", "state"]) if (fits({ key: s[k] }, P[k])) note[k] = { key: s[k] };
  if (fits(s.content, P.content)) note.content = s.content;
  if (fits(m.rect, P.rect)) note.rect = { x: m.rect.x, y: m.rect.y, w: m.rect.w, h: m.rect.h };
  if (fits(s.data, P.data)) note.data = JSON.parse(JSON.stringify(s.data));
  if (fits(s.viewport, P.viewport)) note.viewport = { ...s.viewport };
  const kept = Object.fromEntries(controls.filter((c) => typeof s.controls?.[c.id] === "string").map((c) => [c.id, s.controls[c.id]]));
  if (Object.keys(kept).length && fits(kept, P.controls)) note.controls = kept;
  if (kind === "text") {
    if (!fits(m.quote, QUOTE())) return null;
    anchor.textQuote = { exact: m.quote.exact };
    for (const k of ["prefix", "suffix"]) if (m.quote[k] !== undefined) anchor.textQuote[k] = m.quote[k];
  }
  if (kind === "region") {
    note.elements = (Array.isArray(m.elements) ? m.elements : []).map(anchorFrom).filter(Boolean).slice(0, schema.$defs.elements.maxItems);
  }
  if (kind === "move") {
    const to = m.to && typeof m.to === "object" ? m.to : {};
    if (!fits(to.point, P.to.properties.point)) return null;
    note.to = { point: { x: to.point.x, y: to.point.y } };
    const end = anchorFrom(to.anchor);
    if (end) note.to.anchor = end;
  }
  return problems({ ...note, text: "x" }, schema).length ? null : note;
}

const nameOf = (a) => (a.testid ? `${a.testid} #${a.testidIndex + 1}` : `<${a.tag}>${a.cssPath ? ` at ${a.cssPath}` : ""}`);
function where(n) {
  const a = n.anchor, parts = [];
  if (n.variant) parts.push(`variant ${n.variant.key}`);
  if (n.state) parts.push(`state ${n.state.key}`);
  if (n.kind === "move") {
    const to = n.to.anchor ? nameOf(n.to.anchor) : `the point ${Math.round(n.to.point.x)}%, ${Math.round(n.to.point.y)}%`;
    parts.push(`move ${nameOf(a)} to ${to}`);
  } else if (n.kind === "text") {
    const q = [...(a.textQuote?.exact ?? "")];
    parts.push(`text “${q.slice(0, 60).join("")}${q.length > 60 ? "…" : ""}”`);
  } else if (n.kind === "region") {
    parts.push(`region at ${Math.round(n.rect?.x ?? 0)}%, ${Math.round(n.rect?.y ?? 0)}% over ${n.elements?.length ?? 0} element(s)`);
  } else parts.push(nameOf(a));
  return parts.join(" · ");
}
/** The view a note was made on, in the page's own variant and state names when the frame has reported them. */
function viewWords(n) {
  if (!n.variant) return "";
  const v = labelOf(view.variants, n.variant.key), s = n.state ? labelOf(view.states, n.state.key) || n.state.key : "";
  return `On ${v ? `${n.variant.key} ${v}` : `variant ${n.variant.key}`}${s ? `, ${s.toLowerCase()}` : ""}`;
}

/** A row's number, as its marker shows it: the seq once sent, D1, D2... for drafts, null for a note no marker shows. */
const numberOf = (m) => m.seq ?? (m.draft ? `D${mine.filter((x) => x.draft).indexOf(m) + 1}` : null);
/** What the frame needs to find a note's box and restore its view: contract keys, a path and a box, never its text. */
function noteTarget(m) {
  const n = m.note, t = { n: numberOf(m), kind: n.kind, cssPath: n.anchor.cssPath };
  if (n.rect) t.rect = { x: n.rect.x, y: n.rect.y, w: n.rect.w, h: n.rect.h };
  if (n.variant) t.variant = n.variant.key;
  if (n.state) t.state = n.state.key;
  if (n.content) t.content = n.content;
  return t;
}
/** Ask the frame for the visible text of each listed note's element that it has not named yet. */
function askNames() {
  const want = mine.filter((m) => !m.parts && !m.asked);
  if (!want.length || !live()) return;
  for (const m of want) m.asked = true;
  toFrame({ type: "name", targets: want.map((m) => ({ k: m.id, ...noteTarget(m), toPath: m.note.to?.anchor?.cssPath })) });
}
/** Select a row: the frame restores the note's view, scrolls to it and keeps its box drawn. */
function choose(m) {
  if (picking) setPick(null);
  chosen = m;
  toFrame({ type: "select", target: noteTarget(m) });
  markChosen();
}
function unchoose(tellFrame) {
  if (!chosen) return;
  chosen = null;
  if (tellFrame) toFrame({ type: "select", target: null });
  markChosen();
}
/** The rows stay in place: a click still bubbling from a row must find it in the list. */
function markChosen() {
  for (const li of $("notes").children) {
    if (chosen && li.dataset.key === `row-${chosen.id}`) li.setAttribute("aria-current", "true");
    else li.removeAttribute("aria-current");
  }
}

/** The run's sent notes from the bridge, so a reload lists them again. A note the contract refuses is left out. */
async function loadHistory() {
  try {
    const r = await fetch("/api/notes", { headers: { "X-Notes-Token": token } });
    if (!r.ok) throw new Error(`the notes read answered ${r.status}`);
    const { notes } = await r.json();
    for (const e of Array.isArray(notes) ? notes : []) {
      if (!e || typeof e !== "object") continue;
      const { seq, at: _at, ...note } = e;
      if (!Number.isInteger(seq) || problems(note, schema).length || mine.some((m) => m.seq === seq)) continue;
      mine.push({ id: ++ids, note, where: where(note), seq, draft: false });
    }
  } catch (err) {
    console.warn("ui-feedback: the run's earlier notes were not listed", err);
  }
}

/** This tab's drafts for this run, kept in sessionStorage under the run's token so a reload lists them again. */
let draftsKept = null;
function restoreDrafts() {
  let tab;
  try { tab = sessionStorage; } catch (err) { console.warn("ui-feedback: no tab storage, so drafts last this load only", err); return; }
  draftsKept = draftStore(tab, token, schema);
  for (const note of draftsKept.load()) mine.push({ id: ++ids, note, where: where(note), seq: null, draft: true });
}

/** Open the editor on a new note (`entry` null) or on a draft; `from` gives back the control
 *  that opened it, which gets the focus when the editor closes. */
function openComposer(note, from, entry = null) {
  draft = note;
  editing = entry;
  opener = from;
  setPick(null);
  if ($("panel").hidden) setPanel(true);
  selectTab(tabs[0], false);
  $("composer-label").textContent = entry ? `Edit draft ${numberOf(entry)}` : "New note";
  $("picked").textContent = `${{ element: "Picked", text: "Selected", region: "Marked", move: "Arrow" }[note.kind]}: ${where(note)}`;
  $("reshape").hidden = note.kind !== "region";
  composer.hidden = false;
  text.value = entry ? entry.note.text : "";
  text.focus();
}
function closeComposer() {
  if (reshaping === "draft") setPick(null);
  if (draft?.kind === "move") toFrame({ type: "clear-arrow" });
  toFrame({ type: "release" });
  draft = editing = null;
  composer.hidden = true;
  (opener?.() || buttons.element).focus();
}
const control = (key) => () => document.querySelector(`[data-key="${key}"]`);

/** The composer's note with its text, or null after saying why the contract refuses it. */
function written(verb) {
  const note = { ...draft, text: text.value.trim() };
  const found = problems(note, schema);
  if (found.length) { say(`Not ${verb}: ${found[0]}.`); return null; }
  return note;
}

/** Post one entry's note. "sent" gives it its seq; "offline" keeps it here for Copy all notes;
 *  "busy" posts nothing, because one post at a time keeps a second click from sending a copy. */
async function deliver(entry) {
  if (sending) return "busy";
  sending = true;
  let r, body;
  try {
    r = await fetch("/api/note", {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-Notes-Token": token },
      body: JSON.stringify(entry.note),
    });
    body = await r.json();
  } catch {
    entry.draft = false;
    noSession = true;
    return "offline";
  } finally {
    sending = false;
  }
  if (!r.ok) { say(`Not sent: ${body.error || r.status}.`); return "refused"; }
  entry.seq = body.seq;
  entry.draft = false;
  shown.set(body.seq, "Sent");
  return "sent";
}
const OFFLINE = "Not sent: no session is answering. The note is kept on this page; Copy all notes makes a block to paste to Claude.";

async function send() {
  if (!draft || sending) return;
  const note = written("sent");
  if (!note) return;
  const entry = editing || { id: ++ids };
  Object.assign(entry, { note, where: where(note), seq: null, parts: null, asked: null });
  const got = await deliver(entry);
  if (got === "refused" || got === "busy") return;
  if (!mine.includes(entry)) mine.push(entry);
  render();
  closeComposer();
  say(got === "sent" ? `Note ${entry.seq} sent.` : OFFLINE);
}
function save() {
  if (!draft || sending) return;
  const note = written("saved");
  if (!note) return;
  const entry = editing || { id: ++ids };
  Object.assign(entry, { note, where: where(note), seq: null, draft: true, parts: null, asked: null });
  if (!mine.includes(entry)) mine.push(entry);
  if (!editing) opener = control(`edit-${entry.id}`);
  filter = "all";
  render();
  closeComposer();
  choose(entry);
  control(`edit-${entry.id}`)()?.focus();
  say("Draft saved.");
}
async function sendDrafts(list) {
  const sent = [];
  let got;
  for (const entry of list) {
    got = await deliver(entry);
    if (got !== "sent") break;
    sent.push(entry.seq);
  }
  const refusal = got === "refused" ? ` ${$("status").textContent}` : "";
  if (editing && !editing.draft) closeComposer();
  render();
  if (noSession) say(OFFLINE);
  else if (sent.length) say((sent.length === 1 ? `Note ${sent[0]} sent.` : `Notes ${sent.join(", ")} sent.`) + refusal);
  if (!document.activeElement || document.activeElement === document.body) $("notes-title").focus();
}
function remove(entry) {
  if (sending) return;
  if (editing === entry) closeComposer();
  if (chosen === entry) unchoose(true);
  mine.splice(mine.indexOf(entry), 1);
  render();
  $("notes-title").focus();
  say("Draft deleted.");
}

/** Move or resize a region: the composer's draft ("draft") or a listed note's, in region mode from its box, once
 *  the frame shows the note's own view. */
function reshape(target) {
  const m = target === "draft" ? { note: draft } : target;
  toFrame({ type: "select", target: noteTarget(m) });
  setPick("region", m.note.rect || null);
  if (!picking) return;
  reshaping = target;
  say("Drag the box to move it, or its edges and corners to resize it; or move it with the arrow keys (Shift+arrows resize) and press Enter. Esc keeps it where it was.");
}
/** A reshaped region's anchor, rect and elements replace the note's; a sent note's change goes to the session. */
async function reshaped(note) {
  const target = reshaping;
  setPick(null);
  if (!note) { say("That region cannot carry a note: the element around it is outside the note contract. It stays where it was."); return; }
  const moved = { anchor: note.anchor, rect: note.rect, elements: note.elements };
  if (target === "draft") {
    draft = { ...draft, ...moved };
    $("picked").textContent = `Marked: ${where(draft)}`;
    text.focus();
    say("The region moved. Write your note, then send it.");
    return;
  }
  toFrame({ type: "release" });
  if (target.seq !== null && (await deliverChange(target.seq, moved)) !== "sent") return;
  target.note = { ...target.note, ...moved };
  target.where = where(target.note);
  target.parts = target.asked = null;
  render();
  choose(target);
  document.querySelector(`[data-key="reshape-${target.id}"]`)?.focus();
  say(target.seq !== null ? `Note ${target.seq}'s region moved; Claude is told.` : "The region moved.");
}
/** Post a sent region note's new anchor, rect and elements; "sent" once the session's log has the change. */
async function deliverChange(seq, moved) {
  if (sending) return "busy";
  sending = true;
  let r, body;
  try {
    r = await fetch("/api/note/change", {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-Notes-Token": token },
      body: JSON.stringify({ change: seq, ...moved }),
    });
    body = await r.json();
  } catch {
    say(`Not moved: no session is answering, so note ${seq} keeps its region.`);
    return "offline";
  } finally {
    sending = false;
  }
  if (!r.ok) { say(`Not moved: ${body.error || r.status}.`); return "refused"; }
  return "sent";
}

/** Show or hide the notes popover over the mockup; the frame keeps its size. The Notes button stays, and gets the focus back when the popover closes. */
function setPanel(open) {
  $("panel").hidden = !open;
  $("dock").setAttribute("aria-expanded", String(open));
  closeMenus();
  if (open) { placePanel(); tabs.find((t) => t.getAttribute("aria-selected") === "true").focus(); }
  else $("dock").focus();
}
/** The popover opens above the bar, at its end, or at its start when the person moves it there. */
function placePanel() {
  const r = $("bar").getBoundingClientRect(), s = document.documentElement.style;
  s.setProperty("--bar-top", `${Math.round(innerHeight - r.top + 10)}px`);
  s.setProperty("--bar-start", `${Math.round(r.left)}px`);
  s.setProperty("--bar-end", `${Math.round(innerWidth - r.right)}px`);
}
const SIDE = "ui-feedback-notes-side";
function setSide(side) {
  $("panel").dataset.side = side;
  $("side").setAttribute("aria-label", side === "start" ? "Move the notes to the right" : "Move the notes to the left");
  try { sessionStorage.setItem(SIDE, side); } catch {}
}
let side = "end";
try { side = sessionStorage.getItem(SIDE) === "start" ? "start" : "end"; } catch {}
setSide(side);
placePanel();
addEventListener("resize", placePanel);
if (window.ResizeObserver) new ResizeObserver(placePanel).observe($("bar"));

const MARKERS = "ui-feedback-markers-hidden";
let markersShown = true;
try { markersShown = sessionStorage.getItem(MARKERS) !== "1"; } catch {}
function setMarkers(on) {
  markersShown = on;
  try { sessionStorage.setItem(MARKERS, on ? "0" : "1"); } catch {}
  $("markers").setAttribute("aria-pressed", String(on));
  $("markers-label").textContent = on ? "Markers" : "Markers off";
  toFrame({ type: "markers", on, clicks: true });
}
setMarkers(markersShown);

/** One prototype-notes block holding every note written on this page; a backtick is escaped, so no
 *  note can end the fence. The session imports it with notes-bridge.sh import. */
function copyAll() {
  closeMenus();
  $("copy-button").focus();
  if ($("panel").hidden) setPanel(true);
  selectTab(tabs[0], false);
  const notes = mine.filter((m) => !m.draft);
  if (!notes.length) return say("No notes on this page yet; a draft goes in once it is sent.");
  const body = JSON.stringify({ notes: notes.map((m) => m.note) }, null, 1).replace(/`/g, "\\u0060");
  const block = "```prototype-notes\n" + body + "\n```\n";
  $("block").value = block;
  $("copyout").hidden = false;
  $("block").select();
  const done = () => say(`Copied ${notes.length} note(s). Paste the block to Claude.`);
  const manual = () => say("Select the block below and copy it, then paste it to Claude.");
  if (navigator.clipboard) navigator.clipboard.writeText(block).then(done, manual);
  else manual();
}

/** The mockup's copy-out terminator text, asked of the frame; only the one reply to an ask is copied, as text. */
let wantChosen = false;
function askChosen() {
  closeMenus();
  $("copy-button").focus();
  wantChosen = true;
  toFrame({ type: "copy-out" });
}
function copyChosen(m) {
  wantChosen = false;
  if ($("panel").hidden) setPanel(true);
  selectTab(tabs[0], false);
  const text = chosenFrom(m);
  if (text === null) return say("The mockup's chosen design is not plain text of at most 8000 characters, so nothing was copied.");
  $("block").value = text;
  $("copyout").hidden = false;
  $("block").select();
  const done = () => say("Copied the chosen design. Paste it to Claude.");
  const manual = () => say("Select the text below and copy it, then paste it to Claude.");
  if (navigator.clipboard) navigator.clipboard.writeText(text).then(done, manual);
  else manual();
}

function render() {
  const listening = noSession
    ? "No session: the notes server is not answering. Your notes stay on this page; Copy all notes makes a block to paste to Claude."
    : { listening: "Claude is listening.", reading: "Claude is reading your notes." }[last.listening]
      || "No session is listening right now; your notes wait until Claude checks them.";
  $("session").textContent = listening;
  const byseq = new Map(last.notes.map((n) => [n.seq, n]));
  const ours = new Map(mine.filter((m) => m.seq !== null).map((m) => [m.seq, m]));
  const seqs = [...new Set([...ours.keys(), ...byseq.keys()])].sort((a, b) => a - b);
  const statusOf = (st) => (st.handled ? "Handled" : st.delivered ? "Claude has it" : "Sent") + (st.reply ? ", with a reply" : "");
  const changed = [];
  for (const seq of ours.keys()) {
    const st = byseq.get(seq);
    if (!st) continue;
    const now = statusOf(st);
    if (shown.has(seq) && shown.get(seq) !== now) changed.push(`Note ${seq}: ${now}`);
    shown.set(seq, now);
  }
  if (changed.length) $("changes").textContent = `${changed.join("; ")}.`;
  const focused = document.activeElement?.dataset?.key;
  const button = (label, key, run, cls = "line") => {
    const b = document.createElement("button");
    b.type = "button";
    b.className = `btn ${cls}`;
    b.textContent = label;
    b.dataset.key = key;
    b.addEventListener("click", run);
    return b;
  };
  const el = (tag, className, textContent) => Object.assign(document.createElement(tag), { className, textContent });
  const item = (num, name, words, status, on, reply, actions = [], entry = null) => {
    const li = el("li", `note${entry?.draft ? " draft" : ""}`, "");
    if (entry) {
      li.tabIndex = 0;
      li.dataset.key = `row-${entry.id}`;
      if (chosen === entry) li.setAttribute("aria-current", "true");
      const peek = (on) => () => toFrame({ type: "show", target: on ? noteTarget(entry) : null });
      li.addEventListener("mouseenter", peek(true));
      li.addEventListener("mouseleave", peek(false));
      li.addEventListener("focus", peek(true));
      li.addEventListener("blur", peek(false));
      li.addEventListener("click", (e) => { if (!e.target.closest("button")) choose(entry); });
      li.addEventListener("keydown", (e) => {
        if (e.target === li && (e.key === "Enter" || e.key === " ")) { e.preventDefault(); choose(entry); }
      });
    }
    const head = el("div", "head", "");
    if (num !== null) head.append(el("span", "num", String(num)));
    head.append(el("span", "name", name));
    const st = el("div", "st", "");
    st.append(el("span", `state ${status[1]}`, status[0]));
    if (on) st.append(el("span", "view", on));
    li.append(head, el("p", "text", words), st);
    if (reply) li.append(el("p", "reply", reply));
    if (actions.length) {
      const row = el("div", "acts", "");
      row.append(...actions);
      li.append(row);
    }
    return li;
  };
  const reshapes = (m) => (m?.note.kind === "region" ? [button("Move or resize", `reshape-${m.id}`, () => reshape(m))] : []);
  const drafts = mine.filter((m) => m.draft);
  draftsKept?.save(drafts.map((m) => m.note));
  const pin =(m) => ({
    n: numberOf(m), selector: "", rect: { x: m.note.rect?.x ?? 0, y: m.note.rect?.y ?? 0 },
    ...(m.note.variant && { variant: m.note.variant.key }), ...(m.note.state && { state: m.note.state.key }),
  });
  toFrame({ type: "pins", pins: [...mine.filter((m) => m.seq !== null), ...drafts].map(pin) });
  askNames();
  const sentRows = seqs.map((seq) => {
    const m = ours.get(seq);
    const st = byseq.get(seq) || {};
    const status = [statusOf(st), st.handled ? "s-handled" : ""];
    return item(seq, m ? readerName(m.note, m.parts) : "Sent earlier", m ? m.note.text : "", status, m ? viewWords(m.note) : "", st.reply, reshapes(m), m);
  });
  const unsent = mine.filter((m) => m.seq === null).map((m) => (m.draft
    ? item(numberOf(m), readerName(m.note, m.parts), m.note.text, ["Draft, not sent", "s-draft"], viewWords(m.note), null, [
      button("Edit", `edit-${m.id}`, () => openComposer(m.note, control(`edit-${m.id}`), m)),
      button("Delete", `delete-${m.id}`, () => remove(m)),
      button("Send", `send-${m.id}`, () => sendDrafts([m]), "primary"),
      ...reshapes(m),
    ], m)
    : item(null, readerName(m.note, m.parts), m.note.text, ["Not sent: use Copy all notes", "s-draft"], viewWords(m.note), null, reshapes(m), m)));
  const draftRows = unsent.filter((li) => li.classList.contains("draft"));
  const counts = { all: sentRows.length + unsent.length, draft: drafts.length, sent: sentRows.length };
  for (const b of document.querySelectorAll("[data-filter]")) {
    b.setAttribute("aria-pressed", String(b.dataset.filter === filter));
    b.querySelector(".count").textContent = String(counts[b.dataset.filter]);
  }
  $("notes").replaceChildren(...(filter === "draft" ? draftRows : filter === "sent" ? sentRows : [...sentRows, ...unsent]));
  $("empty").hidden = counts.all > 0;
  $("count").textContent = String(counts.all);
  $("copy-count").textContent = String(counts.sent + unsent.length - drafts.length);
  $("dock").setAttribute("aria-label", `Notes, ${counts.all}`);
  $("drafts").textContent = drafts.length ? `${drafts.length} draft${drafts.length > 1 ? "s" : ""} not sent.` : "";
  $("sendall").hidden = !drafts.length;
  if (focused) document.querySelector(`[data-key="${focused}"]`)?.focus();
}

const FRAME_KEYS = new Set(["p", "r", "a", "m", "n"]);
addEventListener("message", (e) => {
  if (!fromFrame(e, frame.contentWindow, devOrigin) || loads > 1) return;
  const m = e.data;
  if (!m || typeof m !== "object") return;
  if (m.type === "ready") {
    if (ready) return;
    ready = true;
    heard();
    for (const b of [...Object.values(buttons), $("quote")]) b.disabled = false;
    toFrame({ type: "bar" });
    takeControls(m);
    setMarkers(markersShown);
    render();
    say("");
  } else if (m.type === "escape") setPick(null);
  else if (m.type === "view") { view = viewFrom(m, schema.$defs.key.pattern); renderView(); render(); }
  else if (m.type === "named") {
    for (const [k, parts] of namesFrom(m)) { const entry = mine.find((x) => x.id === k); if (entry) entry.parts = parts; }
    render();
  } else if (m.type === "marker") {
    const entry = mine.find((x) => (x.seq !== null || x.draft) && numberOf(x) === m.n);
    if (!entry) return;
    if ($("panel").hidden) setPanel(true);
    selectTab(tabs[0], false);
    filter = "all";
    render();
    choose(entry);
    const row = document.querySelector(`[data-key="row-${entry.id}"]`);
    row?.scrollIntoView({ block: "nearest" });
    row?.focus();
  } else if (m.type === "unselected") unchoose(false);
  else if (m.type === "shown" && m.found === false && chosen) say("That note's place is not on the mockup now, so no box is drawn.");
  else if (m.type === "content" && fits(m.name, schema.properties.content)) { content = m.name; renderControls(); }
  else if (m.type === "want-text") askText();
  else if (m.type === "chosen" && wantChosen) copyChosen(m);
  else if (m.type === "key" && FRAME_KEYS.has(m.key)) shortcut(m.key);
  else if (m.type === "pinned" && picking === "element") {
    const note = noteFrom(m, "element");
    if (note) openComposer(note, () => buttons.element);
    else { toFrame({ type: "release" }); say("That element cannot carry a note: its tag or path is outside the note contract. Pick its parent."); }
  } else if (m.type === "region" && picking === "region") {
    const note = noteFrom(m, "region");
    if (reshaping) reshaped(note);
    else if (note) openComposer(note, () => buttons.region);
    else { toFrame({ type: "release" }); say("That region cannot carry a note: the element around it is outside the note contract."); }
  } else if (m.type === "move" && picking === "move") {
    const note = noteFrom(m, "move");
    if (note) openComposer(note, () => buttons.move);
    else {
      toFrame({ type: "clear-arrow" });
      say("That arrow cannot carry a note: the element to move is outside the note contract. Pick its parent.");
    }
  } else if (m.type === "selected" && wantText) {
    wantText = false;
    const note = m.none ? null : noteFrom(m, "text");
    if (note) openComposer(note, () => $("quote"));
    else { toFrame({ type: "release" }); say("Select some text in the mockup first, then press Text (T)."); }
  }
});

buttons.element.addEventListener("click", () => setPick(picking === "element" ? null : "element"));
buttons.region.addEventListener("click", () => setPick(picking === "region" ? null : "region"));
buttons.move.addEventListener("click", () => setPick(picking === "move" ? null : "move"));
$("quote").addEventListener("click", askText);
$("send").addEventListener("click", send);
$("save").addEventListener("click", save);
$("reshape").addEventListener("click", () => reshape("draft"));
$("sendall").addEventListener("click", () => sendDrafts(mine.filter((m) => m.draft)));
$("dock").addEventListener("click", () => setPanel($("panel").hidden));
$("markers").addEventListener("click", () => setMarkers(!markersShown));
$("cancel").addEventListener("click", closeComposer);
$("copy").addEventListener("click", copyAll);
$("copy-chosen").addEventListener("click", askChosen);
$("copy-config").addEventListener("click", copyConfig);
$("copy-values").addEventListener("click", () => { closeMenus(); $("copy-button").focus(); if ($("panel").hidden) setPanel(true); selectTab(tabs[1], false); copyConfig(); });
$("side").addEventListener("click", () => setSide($("panel").dataset.side === "start" ? "end" : "start"));
$("vprev").addEventListener("click", () => stepVariant(-1));
$("vnext").addEventListener("click", () => stepVariant(1));
for (const [b] of MENUS) b.addEventListener("click", () => toggleMenu(b));
for (const b of document.querySelectorAll("[data-filter]")) b.addEventListener("click", () => { filter = b.dataset.filter; render(); });
document.addEventListener("click", (e) => {
  const at = e.target instanceof Element ? e.target : null;
  if (chosen && !at?.closest("#notes li, #panel")) unchoose(true);
  const open = openMenu();
  if (open && !open[0].parentElement.contains(at)) closeMenus();
});
$("notes").addEventListener("mouseleave", () => toFrame({ type: "show", target: null }));
$("reset-controls").addEventListener("click", resetControls);
for (const t of tabs) {
  t.addEventListener("click", () => selectTab(t));
  t.addEventListener("keydown", (e) => {
    const i = tabs.indexOf(t), to = { ArrowRight: i + 1, ArrowLeft: i - 1, Home: 0, End: tabs.length - 1 }[e.key];
    if (to === undefined || picking === "region") return;
    e.preventDefault();
    e.stopPropagation();
    selectTab(tabs[(to + tabs.length) % tabs.length]);
  });
}
const ARROWS = { ArrowLeft: [-1, 0], ArrowRight: [1, 0], ArrowUp: [0, -1], ArrowDown: [0, 1] };
function shortcut(key) {
  if (key === "n") setPanel($("panel").hidden);
  else if (key === "m") setMarkers(!markersShown);
  else if (!ready) return false;
  else if (key === "p") setPick(picking === "element" ? null : "element");
  else if (key === "r") setPick(picking === "region" ? null : "region");
  else if (key === "a") setPick(picking === "move" ? null : "move");
  else if (key === "t") askText();
  else return false;
  return true;
}
document.addEventListener("keydown", (e) => {
  if (e.key === "Escape") {
    const open = openMenu();
    if (open) { closeMenus(); open[0].focus(); return; }
    if (draft && !reshaping) closeComposer(); else if (picking || $("panel").hidden) setPick(null); else setPanel(false);
    return;
  }
  if (e.target instanceof HTMLElement && (/^(INPUT|TEXTAREA|SELECT)$/.test(e.target.tagName) || e.target.isContentEditable)) return;
  if (e.metaKey || e.ctrlKey || e.altKey) return;
  if (picking === "region" && (ARROWS[e.key] || e.key === "Enter")) {
    e.preventDefault();
    if (e.key === "Enter") toFrame({ type: "commit" });
    else toFrame({ type: "nudge", dx: ARROWS[e.key][0], dy: ARROWS[e.key][1], grow: e.shiftKey });
    return;
  }
  if (shortcut(e.key.toLowerCase())) e.preventDefault();
});

try {
  const [s, cs, t, page] = await Promise.all([
    fetch("/note.schema.json").then((r) => r.json()),
    fetch("/controls.schema.json").then((r) => r.json()),
    fetch("/api/token").then((r) => r.json()),
    devOrigin ? null : fetch("/api/page"),
  ]);
  if (page && !page.ok) throw new Error((await page.json()).error);
  schema = s;
  cschema = cs;
  use(s, cs);
  token = t.token;
  await loadHistory();
  restoreDrafts();
  render();
  frame.addEventListener("load", () => {
    loads += 1;
    if (loads > 1) {
      ready = false;
      picking = null;
      for (const b of [...Object.values(buttons), $("quote"), $("controls-fields"), $("copy-config"), $("reset-controls"), $("copy-values"), $("copy-chosen"), $("vprev"), $("vnext")]) b.disabled = true;
      for (const b of $("data-list").children) b.disabled = true;
      say("The mockup loaded another page in its frame, so this page stopped listening to it. Reload to start again.");
      $("controls-status").textContent = "The mockup loaded another page in its frame, so these controls no longer reach it. Reload to start again.";
    }
  });
  const blocked = devOrigin
    ? `The route has not said it is ready after ${READY_MS / 1000} seconds. Its dev server may refuse to be framed by this page (mount the harness fence), or the route does not load the notes helper.`
    : `The mockup has not said it is ready after ${READY_MS / 1000} seconds. Reload to try again.`;
  heard = awaitReady(() => { if (loads < 2) say(blocked); });
  if (devOrigin) frame.src = `${devOrigin}/`;
  else frame.srcdoc = await page.text();
  const events = new EventSource("/events");
  events.addEventListener("state", (e) => { last = JSON.parse(e.data); noSession = false; render(); });
  events.addEventListener("error", () => { noSession = true; render(); });
} catch (err) {
  heard();
  say(`No session is connected (${err.message || "the server is not answering"}). Use the mockup's own copy-out control instead.`);
}
