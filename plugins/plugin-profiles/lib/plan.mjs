// The profile planner: what applying one profile at one target writes, and what it reports.
// Pure: every input arrives as an argument and nothing here reads or writes a file.
//
//   plan({catalog, profile, inventory, layers, current, target}) -> Plan, or throws PlanError
//
// catalog    ProfileCatalog from profile-files.mjs: {alwaysOn, profiles: Map<name, profile>}, each
//            profile {name, description, plugins, optional, exclude, hideSkills} as Sets.
// inventory  Map<id, {id, dependsOn: [id], ships: {hooks, mod, mcp, lsp}}> of installed plugins.
// layers     {managed, session, local, project, user}, each {enabledPlugins, skillOverrides} as
//            plain objects; a missing level is empty. The target's own level holds what the file
//            would hold with this tool's earlier entries put back (record.mjs baseline).
// current    the same levels as the files hold now, which enabled and disabled are measured
//            against; defaults to layers.
// target     "session" (a --settings file), "folder" (.claude/settings.local.json) or "initial"
//            (user settings.json).
//
// Plan: {target, profile, writes: {id: boolean}, skillWrites: {name: "off"}, enabled, disabled,
//        pinned: [{id, by: "managed" | "folder" | "repository", value}], missing: [{id, optional,
//        install}], untouched, mcpOrLspOn, hookPluginsOff, ignored, repositoryOn, repositorySkills};
//        the last three name what the profiles' repository files were refused and what only they add

import { profileNamed, sourcesOf } from "./profile-files.mjs";

/** @typedef {"session" | "folder" | "initial"} Target */

export class PlanError extends Error {}

export const TARGET_LEVEL = { session: "session", folder: "local", initial: "user" };
const PRECEDENCE = ["managed", "session", "local", "project", "user"];

const marketplaceOf = (id) => id.slice(id.lastIndexOf("@") + 1);
const entriesOf = (layers, level) => layers[level]?.enabledPlugins ?? {};

/** Close over dependencies before applying explicit exclusions. */
export function profileMembers(wanted, inventory, exclude) {
  const out = new Set(wanted);
  const queue = [...out];
  while (queue.length) {
    for (const dep of inventory.get(queue.pop())?.dependsOn ?? []) {
      if (!out.has(dep)) {
        out.add(dep);
        queue.push(dep);
      }
    }
  }
  for (const id of exclude) out.delete(id);
  return out;
}

/** The levels above the target whose entries the target must leave alone, each with its report name. */
function pinsFor(target, layers) {
  const pins = new Map();
  const take = (level, by) => {
    for (const [id, value] of Object.entries(entriesOf(layers, level))) if (!pins.has(id)) pins.set(id, { id, by, value });
  };
  take("managed", "managed");
  if (target === "initial") {
    take("local", "folder");
    take("project", "folder");
  } else {
    for (const [id, value] of Object.entries(entriesOf(layers, "project"))) {
      if (value === false && !pins.has(id)) pins.set(id, { id, by: "repository", value });
    }
  }
  return pins;
}

/** The always-on members a profile that keeps always-on excludes; AC24 rejects any. */
export const excludedAlwaysOn = (catalog, profile) =>
  profile.keepsAlwaysOn ? [...profile.exclude].filter((id) => catalog.alwaysOn.plugins.has(id) || catalog.alwaysOn.optional.has(id)) : [];

export const effective = (layers, id) => PRECEDENCE.map((level) => entriesOf(layers, level)[id]).find((v) => v !== undefined);

export function plan({ catalog, profile: name, inventory, layers, current = layers, target }) {
  if (!(target in TARGET_LEVEL)) throw new PlanError(`unknown target ${JSON.stringify(target)}: use session, folder or initial`);
  const chosen = profileNamed(catalog, name);
  if (!chosen) throw new PlanError(`no profile named ${JSON.stringify(name)}`);
  const always = catalog.alwaysOn;
  const blocked = excludedAlwaysOn(catalog, chosen);
  if (blocked.length) throw new PlanError(`profile ${name} excludes always-on members: ${blocked.join(", ")}`);

  const sources = sourcesOf(catalog, chosen);
  const leftOut = sources.includes(always) ? [] : [...always.plugins, ...always.optional];
  const all = (field) => sources.flatMap((p) => [...p[field]]);
  const members = new Set(all("plugins"));
  const optional = new Set(all("optional").filter((id) => !members.has(id)));
  const exclude = new Set(all("exclude"));
  const repository = entriesOf(layers, "project");
  const repoEnabled = Object.keys(repository).filter((id) => repository[id] === true);
  const pins = pinsFor(target, layers);

  const wanted = [...members, ...[...optional].filter((id) => inventory.has(id)), ...repoEnabled];
  const desired = profileMembers(wanted, inventory, exclude);
  const governed = new Set([...members, ...optional, ...exclude, ...leftOut].map(marketplaceOf));

  const writes = {};
  const pinned = [];
  const untouched = [];
  for (const id of inventory.keys()) {
    if (!governed.has(marketplaceOf(id))) untouched.push(id);
    else if (pins.has(id)) pinned.push(pins.get(id));
    else if (!(repository[id] === true && !exclude.has(id))) writes[id] = desired.has(id);
  }

  const install = (id) => `claude plugin install ${id}`;
  const missing = [
    ...[...desired].filter((id) => !inventory.has(id) && !optional.has(id)).map((id) => ({ id, optional: false, install: install(id) })),
    ...[...optional].filter((id) => !inventory.has(id)).map((id) => ({ id, optional: true, install: install(id) })),
  ];

  const enabled = Object.keys(writes).filter((id) => writes[id] && effective(current, id) !== true);
  const disabled = Object.keys(writes).filter((id) => !writes[id] && effective(current, id) === true);
  const ships = (id) => inventory.get(id).ships;
  const managedSkills = layers.managed?.skillOverrides ?? {};
  const skillWrites = Object.fromEntries(
    all("hideSkills").filter((skill) => !(skill in managedSkills)).map((skill) => [skill, "off"]),
  );

  const onlyRepository = (field, id) =>
    sources.some((p) => p.fromRepository?.[field].has(id)) &&
    !sources.some((p) => !p.fromRepository?.[field].has(id) && (field === "plugins" ? p.plugins.has(id) || p.optional.has(id) : p.hideSkills.has(id)));

  return {
    target,
    profile: name,
    writes,
    skillWrites,
    enabled,
    disabled,
    ignored: sources.flatMap((p) => p.ignored ?? []),
    repositoryOn: enabled.filter((id) => onlyRepository("plugins", id)),
    repositorySkills: Object.keys(skillWrites).filter((skill) => onlyRepository("hideSkills", skill)),
    pinned,
    missing,
    untouched,
    mcpOrLspOn: enabled.filter((id) => ships(id).mcp || ships(id).lsp),
    hookPluginsOff: disabled.filter((id) => ships(id).hooks || ships(id).mod),
    alwaysOnOff: leftOut.filter((id) => writes[id] === false),
    alwaysOnKept: leftOut.filter((id) => inventory.has(id)).flatMap((id) => {
      if (writes[id] === true) return [{ id, by: "profile" }];
      if (pins.get(id)?.value === true) return [{ id, by: pins.get(id).by }];
      return !(id in writes) && !pins.has(id) && repository[id] === true ? [{ id, by: "repository" }] : [];
    }),
  };
}
