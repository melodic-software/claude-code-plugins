import { readFileSync } from "node:fs";
import { excludedAlwaysOn } from "./plan.mjs";
import { ALWAYS_ON, alphabetical, ignoredLine, resolveCatalog } from "./profile-files.mjs";
import { skillLinkReports } from "./skill-links.mjs";

export class CheckError extends Error {}

const SUPERSETS = [["interface-design", "planning"]];
const ID_LISTS = ["plugins", "optional", "remove", "exclude"];
const FILE_KEYS = { plugins: "plugins", optional: "optional", remove: "remove", exclude: "exclude", hideSkills: "hide_skills" };

const nameOf = (id) => id.slice(0, id.lastIndexOf("@"));
const marketplaceOf = (id) => id.slice(id.lastIndexOf("@") + 1);
const install = (id) => `claude plugin install ${id}`;

export function readMarketplace(path) {
  let doc;
  try {
    doc = JSON.parse(readFileSync(path, "utf8"));
  } catch (error) {
    throw new CheckError(`catalog ${path} cannot be read (${error.code ?? error.message})`);
  }
  if (typeof doc?.name !== "string" || !Array.isArray(doc.plugins)) throw new CheckError(`catalog ${path} has no name and plugins list`);
  return { name: doc.name, plugins: new Set(doc.plugins.map((p) => p?.name).filter((n) => typeof n === "string")) };
}

function idProblems({ level, path, def }, catalog, installed) {
  const out = [];
  for (const list of ID_LISTS) {
    for (const id of def[list]) {
      if (marketplaceOf(id) === catalog.name) {
        if (!catalog.plugins.has(nameOf(id))) out.push(`${path}: ${list} names ${id}, which is not in the catalog ${catalog.name}`);
      } else if (level === "shipped") {
        out.push(`${path}: ${list} names ${id}, but the catalog is ${catalog.name}; write ${nameOf(id)}@${catalog.name}`);
      } else if (list === "plugins" && !installed.has(id)) {
        out.push(`${path}: ${id} is not installed. Install it with: ${install(id)}`);
      }
    }
  }
  return out;
}

function orderProblems({ path, def }) {
  return Object.entries(FILE_KEYS).flatMap(([field, key]) => {
    const sorted = alphabetical(def[field]);
    const at = def[field].findIndex((name, i) => name !== sorted[i]);
    return at < 0 ? [] : [`${path}: ${key} is not in alphabetical order: ${sorted[at]} goes before ${def[field][at]}`];
  });
}

function excludeProblems(catalog) {
  return [...catalog.profiles.values()].flatMap((p) => excludedAlwaysOn(catalog, p).map((id) => `profile ${p.name} excludes always-on member ${id}`));
}

export function checkProfiles({ files, catalog, installed, skills }) {
  const shipped = files.filter((f) => f.level === "shipped");
  const others = files.filter((f) => f.level !== "shipped");
  const shippedCatalog = resolveCatalog(shipped);
  const fullCatalog = resolveCatalog(files);

  const failures = shipped.flatMap((f) => [...idProblems(f, catalog, installed), ...orderProblems(f)]);
  for (const f of shipped) if (f.name !== ALWAYS_ON && !f.def.description) failures.push(`${f.path}: no description line saying when to pick the profile`);
  const shippedExcludes = excludeProblems(shippedCatalog);
  failures.push(...shippedExcludes);
  for (const [superset, subset] of SUPERSETS) {
    const big = shippedCatalog.profiles.get(superset);
    const small = shippedCatalog.profiles.get(subset);
    const lacking = big && small ? [...small.plugins].filter((id) => !big.plugins.has(id)) : [];
    if (lacking.length) failures.push(`profile ${superset} lacks ${subset} members: ${lacking.join(", ")}; add them to ${superset}`);
  }

  const reports = others.flatMap((f) => idProblems(f, catalog, installed));
  reports.push(...[fullCatalog.alwaysOn, ...fullCatalog.profiles.values()].flatMap((p) => p.ignored).map(ignoredLine));
  reports.push(...excludeProblems(fullCatalog).filter((line) => !shippedExcludes.includes(line)));
  const named = new Set([fullCatalog.alwaysOn, ...fullCatalog.profiles.values()].flatMap((p) => [...p.plugins, ...p.optional]));
  const governed = new Set(files.flatMap((f) => ID_LISTS.flatMap((list) => f.def[list])).map(marketplaceOf));
  for (const id of installed) {
    if (governed.has(marketplaceOf(id)) && !named.has(id)) reports.push(`Installed, and no profile names it (an apply switches it off unless the repository enables it): ${id}`);
  }
  return {
    failures,
    reports,
    ...(skills && skillLinkReports(skills, skills.tree ? shipped : files, skills.tree ? shippedCatalog : fullCatalog, catalog)),
  };
}
