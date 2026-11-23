import { readFileSync } from "node:fs";

export const TRUSTED_ACTORS_PATH = ".github/standards/trusted-actors/trusted-actors.json";
export const trustedActorsPath = (base) => `${base || ".base"}/${TRUSTED_ACTORS_PATH}`;
export const SAME_TREE_LIST = new URL("../../standards/trusted-actors/trusted-actors.json", import.meta.url);

const ACTOR_KEYS = ["id", "kind", "login"];
const KINDS = new Set(["human", "bot"]);
const isPlainObject = (value) => typeof value === "object" && value !== null && !Array.isArray(value);

export const readRawTrustedActors = (path) => JSON.parse(readFileSync(path, "utf8"));

export function loadTrustedList(listPath) {
  const list = readRawTrustedActors(listPath);
  if (
    !isPlainObject(list) ||
    Object.keys(list).sort().join() !== "actors,version" ||
    list.version !== 1 ||
    !Array.isArray(list.actors)
  ) {
    throw new Error("trusted-actor list does not match its schema");
  }
  const ids = new Set();
  const humans = new Set();
  const logins = new Map();
  for (const actor of list.actors) {
    if (
      !isPlainObject(actor) ||
      Object.keys(actor).sort().join() !== ACTOR_KEYS.join() ||
      !Number.isInteger(actor.id) ||
      actor.id < 1 ||
      typeof actor.login !== "string" ||
      !KINDS.has(actor.kind)
    ) {
      throw new Error("trusted-actor entry does not match its schema");
    }
    ids.add(actor.id);
    if (actor.kind === "human") {
      humans.add(actor.id);
    }
    logins.set(actor.login.toLowerCase(), actor.id);
  }
  return { ids, humans, logins };
}
