#!/usr/bin/env node

import { existsSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import { realpathSync } from "node:fs";
import { fileURLToPath } from "node:url";

export const BOARD_TAG = "event-storming/1";

export const KINDS = {
  event: "Domain event: something that happened, past tense",
  command: "Command: an intention, imperative",
  policy: "Policy: whenever X, do Y",
  person: "Person or actor",
  "read-model": "Read model: what someone needs to decide",
  "external-system": "External system: whatever we can put the blame on",
  "hot-spot": "Hot spot: a problem, question or disagreement",
  opportunity: "Opportunity",
  "value-created": "Value created",
  "value-destroyed": "Value destroyed",
  aggregate: "Aggregate: a business rule holder",
  term: "Ubiquitous language term",
  pivotal: "Pivotal event: a phase boundary",
  milestone: "Temporal milestone",
  vote: "Arrow vote",
  phase: "Phase name: not an event, decompose it",
  custom: "Custom: a domain-specific building block",
};

const SECTIONS = {
  "big-picture": [
    "Timeline",
    "People and systems",
    "Problems",
    "Opportunities",
    "Votes",
    "Ubiquitous language",
    "Bounded contexts",
    "Exploration map",
    "Legend",
  ],
  "process-modeling": [
    "Flow",
    "People and systems",
    "Problems",
    "Opportunities",
    "Votes",
    "Ubiquitous language",
    "Legend",
  ],
  "design-level": ["Flow", "People and systems", "Problems", "Ubiquitous language", "Aggregates", "Legend"],
};
export const FORMATS = Object.keys(SECTIONS);
const ZONE_SECTIONS = new Set(["timeline"]);
const GROUP_SECTIONS = new Set(["bounded-contexts", "aggregates"]);
const MAP_SECTION = "exploration-map";
const LEGEND_SECTION = "legend";
const META_ORDER = ["board", "format", "title", "domain", "version", "session", "phase", "updated", "personas"];
const ATTR_KEYS = ["by", "phase", "row", "on"];
const ID = /^[a-z][a-z0-9-]*$/;
const UNSCANNED_KINDS = new Set(["term", "custom"]);
const BLANK_KINDS = new Set(["aggregate"]);
const TYPE_PREFIX = /^(?:command|event|policy|actor|person|read ?model|hot ?spot|aggregate|system)\s*:/i;
const EMOJI = /\p{Extended_Pictographic}/u;
const ESCAPED = /[\\`*_{}[\]<>|#]/g;

export class BoardError extends Error {}

export const slug = (title) =>
  title
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-|-$/g, "");

export function cleanText(value, what = "text", allowEmpty = false) {
  if (typeof value !== "string") throw new BoardError(`${what} must be a string`);
  const text = value
    .replace(/[\p{Cc}\p{Zl}\p{Zp}]/gu, " ")
    .replace(/\s+/g, " ")
    .trim();
  if (!text && !allowEmpty) throw new BoardError(`${what} is empty`);
  return text;
}

const stickyText = (value, kind) => cleanText(value, "text", BLANK_KINDS.has(kind));

export const escapeText = (text) => text.replace(ESCAPED, (ch) => `\\${ch}`);
const unescapeText = (text) => text.replace(/\\([!-/:-@[-`{-~])/g, "$1");

function splitAttrs(rest) {
  for (let i = 0; i < rest.length; i += 1) {
    if (rest[i] === "\\") {
      i += 1;
    } else if (rest[i] === "{" && i > 0 && rest[i - 1] === " " && rest.endsWith("}")) {
      return [rest.slice(0, i - 1), rest.slice(i + 1, -1)];
    }
  }
  return [rest, null];
}

function parseAttrs(raw) {
  const match = /^#([^\s]+)((?:\s+[a-z]+=(?:"(?:[^"\\]|\\.)*"|[^\s"]+))*)\s*$/.exec(raw);
  if (!match) return null;
  const attrs = { id: match[1] };
  const pair = /([a-z]+)=("(?:[^"\\]|\\.)*"|[^\s"]+)/g;
  for (const [, key, value] of match[2].matchAll(pair)) {
    attrs[key] = value.startsWith('"') ? JSON.parse(value) : value;
  }
  return attrs;
}

function renderAttrs(attrs) {
  const parts = [`#${attrs.id}`];
  const keys = [...ATTR_KEYS, ...Object.keys(attrs).filter((k) => k !== "id" && !ATTR_KEYS.includes(k)).sort()];
  for (const key of keys) {
    const value = attrs[key];
    if (value === undefined || value === null || value === "") continue;
    parts.push(`${key}=${/^[A-Za-z0-9._:-]+$/.test(value) ? value : JSON.stringify(value)}`);
  }
  return ` {${parts.join(" ")}}`;
}

const STICKY = /^( {2})?- \[([a-z-]+)\] (.*)$/;
const MEMBER = /^- #([a-z][a-z0-9-]*)$/;

function parseSticky(line) {
  const match = STICKY.exec(line);
  if (!match) return null;
  const [text, rawAttrs] = splitAttrs(match[3]);
  const attrs = rawAttrs === null ? null : parseAttrs(rawAttrs);
  const sticky = {
    type: "sticky",
    nested: Boolean(match[1]),
    kind: match[2],
    text: unescapeText(attrs ? text : match[3]).trim(),
    attrs: attrs ?? {},
    children: [],
  };
  return sticky;
}

function parseHeading3(line) {
  const [text, rawAttrs] = splitAttrs(line.slice(4));
  const attrs = rawAttrs === null ? null : parseAttrs(rawAttrs);
  return { title: unescapeText(attrs ? text : line.slice(4)).trim(), id: attrs?.id };
}

function parseFrontmatter(lines) {
  if (lines[0] !== "---") throw new BoardError("missing frontmatter");
  const end = lines.indexOf("---", 1);
  if (end < 0) throw new BoardError("unterminated frontmatter");
  const meta = {};
  let listKey = null;
  for (const line of lines.slice(1, end)) {
    const item = /^ {2}- (.*)$/.exec(line);
    if (item && listKey) {
      meta[listKey].push(readScalar(item[1]));
      continue;
    }
    const pair = /^([a-z_]+):(?: (.*))?$/.exec(line);
    if (!pair) throw new BoardError(`frontmatter line not understood: ${line.slice(0, 60)}`);
    listKey = null;
    if (pair[2] === undefined || pair[2] === "") {
      meta[pair[1]] = [];
      listKey = pair[1];
    } else {
      meta[pair[1]] = readScalar(pair[2]);
    }
  }
  return { meta, rest: lines.slice(end + 1) };
}

function readScalar(raw) {
  if (raw.startsWith('"')) {
    try {
      return JSON.parse(raw);
    } catch {
      throw new BoardError(`bad quoted value: ${raw.slice(0, 60)}`);
    }
  }
  return raw;
}

const renderScalar = (value) =>
  /^[A-Za-z0-9][A-Za-z0-9 ._/-]*$/.test(String(value)) && !/\s$/.test(String(value))
    ? String(value)
    : JSON.stringify(String(value));

function renderFrontmatter(meta) {
  const keys = [...META_ORDER.filter((k) => k in meta), ...Object.keys(meta).filter((k) => !META_ORDER.includes(k))];
  const out = ["---"];
  for (const key of keys) {
    const value = meta[key];
    if (Array.isArray(value)) {
      out.push(`${key}:`);
      for (const item of value) out.push(`  - ${renderScalar(item)}`);
    } else {
      out.push(`${key}: ${renderScalar(value)}`);
    }
  }
  out.push("---");
  return out;
}

function parseNodes(lines, sectionKey, problems) {
  const nodes = [];
  let container = nodes;
  let lastSticky = null;
  let para = null;
  const flush = () => {
    para = null;
  };
  for (const line of lines) {
    if (line.trim() === "") {
      flush();
      continue;
    }
    if (line.startsWith("### ")) {
      flush();
      const head = parseHeading3(line);
      const type = GROUP_SECTIONS.has(sectionKey) ? "group" : "zone";
      const node = { type, title: head.title, id: head.id, nodes: [] };
      nodes.push(node);
      container = node.nodes;
      lastSticky = null;
      continue;
    }
    const sticky = parseSticky(line);
    if (sticky) {
      flush();
      if (sticky.nested) {
        if (!lastSticky) {
          problems.push({ level: "error", message: `nested sticky with no parent: ${line.slice(0, 60)}` });
          sticky.nested = false;
          container.push(sticky);
          lastSticky = sticky;
        } else {
          lastSticky.children.push(sticky);
        }
      } else {
        container.push(sticky);
        lastSticky = sticky;
      }
      continue;
    }
    const member = MEMBER.exec(line);
    if (member && GROUP_SECTIONS.has(sectionKey)) {
      flush();
      container.push({ type: "member", id: member[1] });
      continue;
    }
    if (/^ {0,2}- /.test(line)) {
      flush();
      container.push({ type: "item", line });
      if (!(sectionKey === MAP_SECTION)) {
        problems.push({ level: "warn", message: `list line is not a sticky: ${line.slice(0, 60)}` });
      }
      continue;
    }
    if (para) {
      para.lines.push(line);
    } else {
      para = { type: "para", lines: [line] };
      container.push(para);
    }
    lastSticky = null;
  }
  return nodes;
}

const LISTISH = new Set(["sticky", "member", "item"]);

function renderNodes(nodes) {
  const out = [];
  let prev = null;
  for (const node of nodes) {
    if (node.type === "zone" || node.type === "group") {
      if (out.length) out.push("");
      out.push(`### ${escapeText(node.title)}${node.id ? ` {#${node.id}}` : ""}`);
      const inner = renderNodes(node.nodes);
      if (inner.length) out.push("", ...inner);
      prev = node;
      continue;
    }
    if (out.length && !(LISTISH.has(node.type) && prev && LISTISH.has(prev.type))) out.push("");
    if (node.type === "sticky") {
      out.push(renderSticky(node, ""));
      for (const child of node.children) out.push(renderSticky(child, "  "));
    } else if (node.type === "member") {
      out.push(`- #${node.id}`);
    } else if (node.type === "item") {
      out.push(node.line);
    } else {
      out.push(...node.lines);
    }
    prev = node;
  }
  return out;
}

const renderSticky = (sticky, indent) =>
  `${indent}- [${sticky.kind}] ${escapeText(sticky.text)}${sticky.attrs.id ? renderAttrs(sticky.attrs) : ""}`;

export function parseBoard(source) {
  const problems = [];
  const lines = source.replace(/\r\n/g, "\n").replace(/\n+$/, "").split("\n");
  const { meta, rest } = parseFrontmatter(lines);
  const head = [];
  const sections = [];
  let current = null;
  for (const line of rest) {
    if (line.startsWith("## ")) {
      const title = line.slice(3).trim();
      current = { title, key: slug(title), lines: [] };
      sections.push(current);
    } else if (current) {
      current.lines.push(line);
    } else {
      head.push(line);
    }
  }
  const known = new Set((SECTIONS[meta.format] ?? []).map(slug));
  for (const section of sections) {
    section.known = known.has(section.key);
    if (section.key === LEGEND_SECTION) {
      section.nodes = [];
    } else if (section.known) {
      section.nodes = parseNodes(section.lines, section.key, problems);
    } else {
      problems.push({ level: "warn", message: `unknown section kept verbatim: ${section.title}` });
    }
  }
  while (head.length && head[0] === "") head.shift();
  while (head.length && head[head.length - 1] === "") head.pop();
  return { meta, head, sections, problems };
}

function legendLines(board) {
  const present = new Set(allStickies(board).map((s) => s.kind));
  const kinds = Object.keys(KINDS).filter((k) => present.has(k));
  if (!kinds.length) return ["No stickies yet."];
  return ["| Kind | Meaning |", "|---|---|", ...kinds.map((k) => `| \`${k}\` | ${KINDS[k]} |`)];
}

export function renderBoard(board) {
  const out = [...renderFrontmatter(board.meta)];
  if (board.head.length) out.push("", ...board.head);
  for (const section of board.sections) {
    out.push("", `## ${section.title}`);
    let body;
    if (section.key === LEGEND_SECTION) {
      body = legendLines(board);
    } else if (section.known) {
      body = renderNodes(section.nodes);
    } else {
      body = [...section.lines];
      while (body.length && body[0] === "") body.shift();
      while (body.length && body[body.length - 1] === "") body.pop();
    }
    if (body.length) out.push("", ...body);
  }
  return `${out.join("\n")}\n`;
}

function walk(board, visit) {
  for (const section of board.sections) {
    if (!section.nodes) continue;
    const visitNodes = (nodes, zone, group) => {
      for (const node of nodes) {
        if (node.type === "zone") visitNodes(node.nodes, node, null);
        else if (node.type === "group") {
          visit({ group: node, section });
          visitNodes(node.nodes, null, node);
        } else if (node.type === "sticky") {
          visit({ sticky: node, section, zone, parent: null, list: nodes });
          for (const child of node.children) visit({ sticky: child, section, zone, parent: node, list: node.children });
        } else if (node.type === "member") visit({ member: node, section, owner: group });
      }
    };
    visitNodes(section.nodes, null, null);
  }
}

const allStickies = (board) => {
  const out = [];
  walk(board, (at) => at.sticky && out.push(at.sticky));
  return out;
};

export function boardToJson(board) {
  const stickies = [];
  const groups = [];
  const zones = [];
  walk(board, (at) => {
    if (at.sticky) {
      stickies.push({
        id: at.sticky.attrs.id ?? null,
        kind: at.sticky.kind,
        text: at.sticky.text,
        section: at.section.key,
        zone: at.zone ? at.zone.title : null,
        parent: at.parent ? at.parent.attrs.id ?? null : null,
        ...Object.fromEntries(Object.entries(at.sticky.attrs).filter(([k]) => k !== "id")),
      });
    } else if (at.group) {
      groups.push({ id: at.group.id ?? null, name: at.group.title, section: at.section.key, members: [] });
    } else if (at.member) {
      groups.at(-1)?.members.push(at.member.id);
    }
  });
  for (const section of board.sections) {
    for (const node of section.nodes ?? []) if (node.type === "zone") zones.push({ id: node.id ?? null, name: node.title });
  }
  const map = board.sections.find((s) => s.key === MAP_SECTION);
  const explorationMap = (map?.nodes ?? []).flatMap((n) => (n.type === "item" ? [n.line.replace(/^- /, "")] : []));
  return { meta: board.meta, zones, stickies, groups, explorationMap };
}

export function checkBoard(board) {
  const findings = [...board.problems];
  const err = (message) => findings.push({ level: "error", message });
  const warn = (message) => findings.push({ level: "warn", message });
  if (board.meta.board !== BOARD_TAG) err(`frontmatter board must be ${BOARD_TAG}`);
  if (!FORMATS.includes(board.meta.format)) err(`frontmatter format must be one of ${FORMATS.join(", ")}`);
  if (typeof board.meta.title !== "string" || !board.meta.title.trim()) err("frontmatter title is missing");
  const keys = board.sections.map((s) => s.key);
  for (const title of SECTIONS[board.meta.format] ?? []) {
    if (!keys.includes(slug(title))) err(`missing section: ${title}`);
  }
  const ids = new Map();
  const note = (id, what) => {
    if (!ID.test(id)) err(`bad id: ${id}`);
    if (ids.has(id)) err(`duplicate id: ${id}`);
    ids.set(id, what);
  };
  const memberOf = new Map();
  const refs = [];
  walk(board, (at) => {
    if (at.group) {
      if (at.group.id) note(at.group.id, "group");
      else warn(`group without an id: ${at.group.title}`);
    } else if (at.member) {
      refs.push([at.member.id, `member of ${at.owner?.title ?? "no group"}`]);
      const key = `${at.section.key}:${at.member.id}`;
      if (memberOf.has(key)) err(`${at.member.id} is in two groups of ${at.section.title}`);
      memberOf.set(key, true);
    } else if (at.sticky) {
      const { sticky } = at;
      const label = sticky.attrs.id ?? sticky.text.slice(0, 40);
      if (!(sticky.kind in KINDS)) err(`unknown kind [${sticky.kind}]: ${label}`);
      if (sticky.attrs.id) note(sticky.attrs.id, "sticky");
      else warn(`sticky without an id: ${label}`);
      if (sticky.attrs.on) refs.push([sticky.attrs.on, `vote ${label}`]);
      if (!UNSCANNED_KINDS.has(sticky.kind) && sticky.text.split(/\s+/).length > 5) warn(`over 5 words: ${label}`);
      if (EMOJI.test(sticky.text)) warn(`emoji: ${label}`);
      if (TYPE_PREFIX.test(sticky.text)) warn(`type prefix: ${label}`);
    }
  });
  for (const [id, where] of refs) {
    if (!ids.has(id)) err(`${where} points at missing ${id}`);
    else if (ids.get(id) !== "sticky") err(`${where} points at group ${id}`);
  }
  for (const section of board.sections) {
    if (section.known === false) continue;
    for (const node of section.nodes ?? []) {
      if (node.type === "zone" && node.id) note(node.id, "zone");
    }
  }
  return findings;
}

function nextId(board, prefix) {
  let max = 0;
  const bump = (id) => {
    const match = id && new RegExp(`^${prefix}(\\d+)$`).exec(id);
    if (match) max = Math.max(max, Number(match[1]));
  };
  walk(board, (at) => {
    if (at.sticky) bump(at.sticky.attrs.id);
    if (at.group) bump(at.group.id);
  });
  for (const section of board.sections) for (const node of section.nodes ?? []) if (node.type === "zone") bump(node.id);
  return `${prefix}${max + 1}`;
}

function sectionFor(board, name) {
  const key = slug(cleanText(name, "section"));
  const section = board.sections.find((s) => s.key === key && s.known);
  if (!section || key === LEGEND_SECTION) throw new BoardError(`no writable section ${key} on a ${board.meta.format} board`);
  return section;
}

function findSticky(board, id) {
  let found = null;
  walk(board, (at) => {
    if (at.sticky && at.sticky.attrs.id === id) found = at;
  });
  if (!found) throw new BoardError(`no sticky ${id}`);
  return found;
}

function findZone(section, ref) {
  if (!ZONE_SECTIONS.has(section.key)) throw new BoardError(`${section.title} has no zones`);
  const zone = section.nodes.find((n) => n.type === "zone" && (n.id === ref || n.title === ref));
  if (!zone) throw new BoardError(`no zone ${ref}`);
  return zone;
}

function attrsFrom(op, base = {}) {
  const attrs = { ...base };
  for (const key of ATTR_KEYS) {
    if (op[key] === null) delete attrs[key];
    else if (op[key] !== undefined) attrs[key] = cleanText(op[key], key);
  }
  return attrs;
}

function targetList(board, op, sectionName) {
  if (op.parent) {
    const parent = findSticky(board, op.parent);
    if (parent.parent) throw new BoardError("stickies nest one level only");
    return { list: parent.sticky.children, nested: true };
  }
  const section = sectionFor(board, sectionName);
  if (GROUP_SECTIONS.has(section.key)) throw new BoardError(`${section.title} holds groups, not stickies`);
  if (section.key === MAP_SECTION) throw new BoardError("the exploration map holds entries, not stickies");
  const list = op.zone ? findZone(section, op.zone).nodes : section.nodes;
  return { list, nested: false };
}

function insertTopLevel(list, node) {
  const firstZone = list.findIndex((n) => n.type === "zone");
  if (firstZone < 0) list.push(node);
  else list.splice(firstZone, 0, node);
}

const OPS = {
  add(board, op) {
    if (!(op.kind in KINDS)) throw new BoardError(`unknown kind ${op.kind}`);
    const { list, nested } = targetList(board, op, op.section);
    if (op.on) findSticky(board, op.on);
    const id = nextId(board, "s");
    const sticky = { type: "sticky", nested, kind: op.kind, text: stickyText(op.text, op.kind), attrs: attrsFrom(op, { id }), children: [] };
    if (nested || op.zone) list.push(sticky);
    else insertTopLevel(list, sticky);
    return id;
  },
  update(board, op) {
    const at = findSticky(board, op.id);
    if (op.kind !== undefined) {
      if (!(op.kind in KINDS)) throw new BoardError(`unknown kind ${op.kind}`);
      at.sticky.kind = op.kind;
    }
    if (op.text !== undefined) at.sticky.text = stickyText(op.text, at.sticky.kind);
    else if (op.kind !== undefined) stickyText(at.sticky.text, at.sticky.kind);
    if (op.on) findSticky(board, op.on);
    at.sticky.attrs = attrsFrom(op, at.sticky.attrs);
    return op.id;
  },
  move(board, op) {
    const at = findSticky(board, op.id);
    if (op.parent === op.id) throw new BoardError("a sticky cannot nest under itself");
    if (op.parent && at.sticky.children.length) throw new BoardError("a sticky with children cannot nest");
    const { list, nested } = targetList(board, op, op.section ?? at.section.title);
    at.list.splice(at.list.indexOf(at.sticky), 1);
    at.sticky.nested = nested;
    if (nested || op.zone) list.push(at.sticky);
    else insertTopLevel(list, at.sticky);
    if (op.row !== undefined) at.sticky.attrs = attrsFrom({ row: op.row }, at.sticky.attrs);
    return op.id;
  },
  zones(board, op) {
    const section = sectionFor(board, op.section ?? "Timeline");
    if (!ZONE_SECTIONS.has(section.key)) throw new BoardError(`${section.title} has no zones`);
    if (!Array.isArray(op.names) || !op.names.length) throw new BoardError("zones needs names");
    return op.names.map((raw) => {
      const name = cleanText(raw, "zone name");
      const existing = section.nodes.find((n) => n.type === "zone" && n.title === name);
      if (existing) return existing.id ?? null;
      const id = nextId(board, "z");
      section.nodes.push({ type: "zone", title: name, id, nodes: [] });
      return id;
    });
  },
  group(board, op) {
    const section = sectionFor(board, op.section);
    if (!GROUP_SECTIONS.has(section.key)) throw new BoardError(`${section.title} holds no groups`);
    const name = cleanText(op.name, "group name");
    const members = op.members ?? [];
    if (!Array.isArray(members)) throw new BoardError("members must be a list");
    for (const id of members) findSticky(board, id);
    let group = section.nodes.find((n) => n.type === "group" && (op.id ? n.id === op.id : n.title === name));
    if (op.id && !group) throw new BoardError(`no group ${op.id}`);
    if (!group) {
      group = { type: "group", title: name, id: nextId(board, "g"), nodes: [] };
      section.nodes.push(group);
    }
    group.title = name;
    for (const other of section.nodes) {
      if (other.type === "group" && other !== group) {
        other.nodes = other.nodes.filter((n) => !(n.type === "member" && members.includes(n.id)));
      }
    }
    const rest = group.nodes.filter((n) => n.type !== "member");
    group.nodes = [...members.map((id) => ({ type: "member", id })), ...rest];
    return group.id;
  },
  "exploration-map"(board, op) {
    const section = sectionFor(board, "Exploration map");
    if (!Array.isArray(op.entries)) throw new BoardError("exploration-map needs entries");
    section.nodes = op.entries.map((entry) => ({
      type: "item",
      line: `- ${escapeText(cleanText(entry.label, "label"))}: ${escapeText(cleanText(entry.value, "value"))}`,
    }));
    return null;
  },
  meta(board, op) {
    for (const key of ["phase", "domain", "title", "session"]) {
      if (op[key] !== undefined) board.meta[key] = cleanText(op[key], key);
    }
    if (op.version !== undefined) {
      if (!Number.isInteger(op.version) || op.version < 1) throw new BoardError("version must be a positive integer");
      board.meta.version = String(op.version);
    }
    if (op.personas !== undefined) {
      if (!Array.isArray(op.personas)) throw new BoardError("personas must be a list");
      board.meta.personas = op.personas.map((p) => cleanText(p, "persona"));
    }
    return null;
  },
};

export function applyOps(board, ops, now) {
  if (!Array.isArray(ops)) throw new BoardError("ops must be a list");
  const results = ops.map((op, index) => {
    if (!op || typeof op !== "object" || !(op.op in OPS)) throw new BoardError(`op ${index}: unknown op`);
    try {
      return OPS[op.op](board, op);
    } catch (error) {
      if (error instanceof BoardError) throw new BoardError(`op ${index} (${op.op}): ${error.message}`);
      throw error;
    }
  });
  if (ops.length) board.meta.updated = now;
  return results;
}

export function newBoard(metaInput, now) {
  const format = metaInput?.format;
  if (!FORMATS.includes(format)) throw new BoardError(`format must be one of ${FORMATS.join(", ")}`);
  const title = cleanText(metaInput.title, "title");
  const meta = { board: BOARD_TAG, format, title };
  for (const key of ["domain", "session", "phase"]) {
    if (metaInput[key] !== undefined) meta[key] = cleanText(metaInput[key], key);
  }
  if (metaInput.version !== undefined) {
    if (!Number.isInteger(metaInput.version) || metaInput.version < 1) throw new BoardError("version must be a positive integer");
    meta.version = String(metaInput.version);
  }
  meta.updated = now;
  if (metaInput.personas !== undefined) {
    if (!Array.isArray(metaInput.personas)) throw new BoardError("personas must be a list");
    meta.personas = metaInput.personas.map((p) => cleanText(p, "persona"));
  }
  const sections = SECTIONS[format].map((t) => ({ title: t, key: slug(t), known: true, nodes: [], lines: [] }));
  return { meta, head: [`# ${escapeText(title)}`], sections, problems: [] };
}

function fail(message, code) {
  process.stderr.write(`board-md: ${message}\n`);
  process.exit(code);
}

function readText(path) {
  try {
    return readFileSync(path, "utf8");
  } catch (error) {
    return fail(`cannot read ${path}: ${error.code ?? error.message}`, 2);
  }
}

function readJson(path) {
  try {
    return JSON.parse(readText(path));
  } catch (error) {
    return fail(`invalid JSON in ${path}: ${error.message}`, 2);
  }
}

function loadBoard(path) {
  try {
    return parseBoard(readText(path));
  } catch (error) {
    if (error instanceof BoardError) return fail(`${path}: ${error.message}`, 1);
    throw error;
  }
}

function writeAtomic(path, text) {
  const tmp = `${path}.tmp-${process.pid}`;
  writeFileSync(tmp, text, { flag: "wx" });
  renameSync(tmp, path);
}

const USAGE = "usage: board-md.mjs parse|check <board.md> | new <board.md> <meta.json> | apply [--now <iso>] <board.md> <ops.json>";

function main(argv) {
  const args = [...argv];
  let now = new Date().toISOString().replace(/\.\d+Z$/, "Z");
  const nowAt = args.indexOf("--now");
  if (nowAt >= 0) {
    now = args[nowAt + 1];
    if (!now || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/.test(now)) fail("--now takes an ISO time like 2026-01-02T03:04:05Z", 2);
    args.splice(nowAt, 2);
  }
  const [command, path, input] = args;
  if (!path) fail(USAGE, 2);
  if (command === "parse" && args.length === 2) {
    const board = loadBoard(path);
    process.stdout.write(`${JSON.stringify(boardToJson(board), null, 2)}\n`);
    return;
  }
  if (command === "check" && args.length === 2) {
    const findings = checkBoard(loadBoard(path));
    for (const f of findings) process.stdout.write(`${f.level}: ${f.message}\n`);
    process.exit(findings.some((f) => f.level === "error") ? 1 : 0);
  }
  if (command === "new" && args.length === 3) {
    if (existsSync(path)) fail(`${path} already exists`, 1);
    try {
      writeAtomic(path, renderBoard(newBoard(readJson(input), now)));
    } catch (error) {
      if (error instanceof BoardError) fail(error.message, 1);
      fail(`cannot write ${path}: ${error.code ?? error.message}`, 2);
    }
    process.stdout.write(`${JSON.stringify({ ok: true, path })}\n`);
    return;
  }
  if (command === "apply" && args.length === 3) {
    const board = loadBoard(path);
    const errors = checkBoard(board).filter((f) => f.level === "error");
    if (errors.length) fail(`${path}: fix before applying: ${errors.map((e) => e.message).join("; ")}`, 1);
    const payload = readJson(input);
    const ops = Array.isArray(payload) ? payload : payload?.ops;
    let ids;
    try {
      for (const at of allStickies(board)) if (!at.attrs.id) at.attrs.id = nextId(board, "s");
      ids = applyOps(board, ops, now);
    } catch (error) {
      if (error instanceof BoardError) fail(error.message, 1);
      throw error;
    }
    const after = checkBoard(parseBoard(renderBoard(board))).filter((f) => f.level === "error");
    if (after.length) fail(`refused: the result would not check: ${after.map((e) => e.message).join("; ")}`, 1);
    try {
      writeAtomic(path, renderBoard(board));
    } catch (error) {
      fail(`cannot write ${path}: ${error.code ?? error.message}`, 2);
    }
    process.stdout.write(`${JSON.stringify({ ok: true, ids })}\n`);
    return;
  }
  fail(USAGE, 2);
}

function invokedDirectly() {
  const arg = process.argv[1];
  if (!arg) return false;
  try {
    return realpathSync(arg) === realpathSync(fileURLToPath(import.meta.url));
  } catch {
    return false;
  }
}

if (invokedDirectly()) main(process.argv.slice(2));
