import { readFileSync } from "node:fs";

const ROLES = Object.freeze({ "actions-bot": "github-actions[bot]" });
const VOID = new Set(["throw", "skip"]);
const MATCH = new Set(["first-line"]);
const HISTORY = new Set(["replace", "sections-by-run"]);

export class MessageVoided extends Error {
  name = "MessageVoided";
}
export class MessageReadError extends Error {
  name = "MessageReadError";
}
export class MessageWriteError extends Error {
  name = "MessageWriteError";
}

export const restLogin = (actor) =>
  typeof actor?.login === "string" && actor.login !== "" ? (actor.__typename === "Bot" ? `${actor.login}[bot]` : actor.login) : null;

const PLACEHOLDER = /\{([a-z]+)\}/g;
const escapeRegExp = (text) => text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");

function template(text, fields, what) {
  const names = [...text.matchAll(PLACEHOLDER)].map((m) => m[1]);
  const declared = Object.keys(fields ?? {});
  if (names.length !== declared.length || !declared.every((n) => names.includes(n))) {
    throw new Error(`${what} must name each of its fields once: ${declared.join(", ")}`);
  }
  const patterns = Object.fromEntries(declared.map((n) => [n, new RegExp(fields[n])]));
  const valid = (values) =>
    values !== null &&
    typeof values === "object" &&
    Object.keys(values).length === declared.length &&
    declared.every((n) => typeof values[n] === "string" && /^\S+$/.test(values[n]) && patterns[n].test(values[n]));
  const line = new RegExp(`^${text.split(PLACEHOLDER).map((part, i) => (i % 2 ? "(\\S+)" : escapeRegExp(part))).join("")}$`);
  return {
    prefix: text.slice(0, text.indexOf("{")),
    parse(candidate) {
      const m = line.exec(candidate);
      if (!m) return null;
      const values = Object.fromEntries(names.map((n, i) => [n, m[i + 1]]));
      return valid(values) ? values : null;
    },
    render: (values) => (valid(values) ? text.replace(PLACEHOLDER, (_, n) => values[n]) : null),
  };
}

function role(name, kind) {
  if (!Object.hasOwn(ROLES, name)) throw new Error(`kind ${kind}: unknown role ${name}`);
  return ROLES[name];
}

function compile(raw) {
  const kinds = new Map();
  for (const [name, k] of Object.entries(raw)) {
    if (!VOID.has(k.void)) throw new Error(`kind ${name}: void must be one of ${[...VOID].join(", ")}`);
    if (!MATCH.has(k.match)) throw new Error(`kind ${name}: match must be one of ${[...MATCH].join(", ")}`);
    if (!HISTORY.has(k.history)) throw new Error(`kind ${name}: history must be one of ${[...HISTORY].join(", ")}`);
    if (!Array.isArray(k.key) || k.key.length === 0 || !k.key.every((f) => Object.hasOwn(k.fields ?? {}, f))) {
      throw new Error(`kind ${name}: key must name marker fields`);
    }
    kinds.set(name, {
      name,
      key: k.key,
      marker: template(k.marker, k.fields, `kind ${name}: marker`),
      section: k.section ? template(k.section.heading, k.section.fields, `kind ${name}: section heading`) : null,
      writer: role(k.writer, name),
      trusted: new Set((k.trusted ?? []).map((r) => role(r, name))),
      void: k.void,
    });
  }
  return kinds;
}

const KINDS = compile(JSON.parse(readFileSync(new URL("./message-kinds.json", import.meta.url), "utf8")));

function kindOf(kinds, name, Failure) {
  const kind = kinds.get(name);
  if (!kind) throw new Failure(`no message kind ${name}`);
  return kind;
}

const sameNames = (values, names) =>
  values !== null && typeof values === "object" && Object.keys(values).length === names.length && names.every((n) => Object.hasOwn(values, n));

export function sectionHeading(kind, fields) {
  const line = kindOf(KINDS, kind, MessageWriteError).section?.render(fields) ?? null;
  if (line === null) throw new MessageWriteError(`the section fields are not of kind ${kind}'s shape`);
  return line;
}

const voided = (c) => c.isMinimized === true || (c.lastEditedAt != null && c.editor !== c.author);

export function prMessages({ store, repo, number, kinds }) {
  const known = kinds === undefined ? KINDS : compile(kinds);
  let listed;

  async function comments() {
    if (listed === undefined) {
      let got;
      try {
        got = await store.list({ repo, number });
      } catch (error) {
        throw new MessageReadError(`could not list the comments on #${number}: ${error?.message ?? error}`, { cause: error });
      }
      if (!Array.isArray(got)) throw new MessageReadError(`the comment list for #${number} is not a list`);
      listed = got;
    }
    return listed;
  }

  function matches(k, key, c) {
    if (!k.trusted.has(c?.author) || typeof c.body !== "string") return false;
    const fields = k.marker.parse(c.body.split("\n", 1)[0]);
    return fields !== null && k.key.every((n) => fields[n] === key[n]);
  }

  async function current(k, key) {
    const all = (await comments()).filter((c) => matches(k, key, c));
    const live = all.filter((c) => !voided(c));
    if (k.void === "throw" && live.length !== all.length) {
      throw new MessageVoided(`a ${k.name} comment on #${number} was edited by someone else or minimized`);
    }
    return live.at(-1) ?? null;
  }

  function view(k, c) {
    const [head, ...rest] = c.body.split("\n");
    const out = { id: c.id, fields: k.marker.parse(head) };
    if (!k.section) return out;
    const sections = [];
    for (const line of rest) {
      if (!line.startsWith(k.section.prefix)) {
        sections.at(-1)?.lines.push(line);
        continue;
      }
      const fields = k.section.parse(line);
      if (fields === null) throw new MessageReadError(`comment ${c.id} on #${number} carries a malformed ${k.name} section marker`);
      sections.push({ fields, lines: [] });
    }
    out.sections = sections.map((s) => ({ fields: s.fields, text: s.lines.join("\n") }));
    return out;
  }

  return {
    async read(kind, key) {
      const k = kindOf(known, kind, MessageReadError);
      if (!sameNames(key, k.key) || k.key.some((n) => typeof key[n] !== "string" || /\s/.test(key[n]))) {
        throw new MessageReadError(`the key is not of kind ${kind}'s shape`);
      }
      const own = await current(k, key);
      return own ? view(k, own) : null;
    },

    async write(kind, key, fields, body) {
      const k = kindOf(known, kind, MessageWriteError);
      if (!k.trusted.has(k.writer)) throw new MessageWriteError(`kind ${kind} does not trust its own writer ${k.writer}`);
      if (!sameNames(key, k.key) || fields === null || typeof fields !== "object" || k.key.some((n) => Object.hasOwn(fields, n))) {
        throw new MessageWriteError(`the key or fields are not of kind ${kind}'s shape`);
      }
      const marker = k.marker.render({ ...fields, ...key });
      if (marker === null) throw new MessageWriteError(`the key or fields are not of kind ${kind}'s shape`);
      if (typeof body !== "string") throw new MessageWriteError("the body is not text");
      if (k.section && body.split("\n").some((line) => line.startsWith(k.section.prefix) && k.section.parse(line) === null)) {
        throw new MessageWriteError(`the body carries a malformed ${kind} section marker`);
      }
      const text = `${marker}\n${body}`;
      const own = await current(k, key);
      if (own?.body === text) return "unchanged";
      try {
        if (!own) {
          const { id } = await store.create({ repo, number, body: text });
          listed.push({ id, author: k.writer, body: text, lastEditedAt: null, editor: null, isMinimized: false });
          return "posted";
        }
        await store.update({ repo, number, id: own.id, body: text });
      } catch (error) {
        throw new MessageWriteError(`could not write the ${kind} comment on #${number}: ${error?.message ?? error}`, { cause: error });
      }
      Object.assign(own, { body: text, lastEditedAt: new Date().toISOString(), editor: k.writer });
      return "edited";
    },
  };
}
