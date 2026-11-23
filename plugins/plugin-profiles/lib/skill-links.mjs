import { readdirSync, readFileSync } from "node:fs";
import { join, relative } from "node:path";
import { inventory } from "./inventory.mjs";
import { profileMembers } from "./plan.mjs";
import { alphabetical, everyProfile, sourcesOf } from "./profile-files.mjs";

const nameOf = (id) => id.slice(0, id.lastIndexOf("@"));
const marketplaceOf = (id) => id.slice(id.lastIndexOf("@") + 1);
const skillToken = (path) => /[\\/]plugins[\\/]([^\\/]+)[\\/]skills[\\/]([^\\/]+)[\\/]SKILL\.md$/.exec(path)?.slice(1).join(":");

function readTargets(path) {
  try {
    return sectionTargets(readFileSync(path, "utf8"));
  } catch (error) {
    return { next: new Set(), related: new Set(), unreadable: error.code ?? error.message };
  }
}

function sectionTargets(text) {
  const targets = { next: new Set(), related: new Set() };
  let section, fence;
  for (const line of text.split(/\r?\n/)) {
    const marker = /^ {0,3}(`{3,}|~{3,})(.*)$/.exec(line);
    if (fence) {
      if (marker && marker[1][0] === fence[0] && marker[1].length >= fence.length && !marker[2].trim()) fence = undefined;
      continue;
    }
    if (marker) {
      fence = marker[1];
      continue;
    }
    const heading = /^ {0,3}##[ \t]+(.*)$/.exec(line);
    if (heading) {
      const name = heading[1].replace(/[ \t]+#+[ \t]*$/, "").trim();
      section = name === "Next" ? targets.next : name === "Related" ? targets.related : undefined;
    }
    if (heading || !section) continue;
    for (const [target] of line.matchAll(/(?<![\w./:-])\/[\w-][\w.-]*:[\w-](?:[\w.-]*[\w-])?/g)) section.add(target);
  }
  return targets;
}

/** Read skill sections from the same plugin roots and manifests used by the planner. */
export function readSkillLinks(plugins, { tree = false, changed = new Set(), root } = {}) {
  const entries = [...plugins.values()].flatMap(({ id, installPath, skills }) =>
    skills.map((skill) => {
      const path = join(installPath, "skills", skill, "SKILL.md");
      return { id, path, shown: root ? relative(root, path) : path, skill, ...readTargets(path) };
    }));
  return { plugins, entries, tree, changed };
}

export function readTreePlugins(dir, marketplace) {
  const names = readdirSync(dir, { withFileTypes: true }).filter((e) => e.isDirectory()).map((e) => e.name);
  const records = alphabetical(names).map((name) => ({ id: `${name}@${marketplace}`, installPath: join(dir, name) }));
  return inventory({ projectDir: dir, records });
}

export function skillLinkReports({ plugins, entries, tree, changed }, files, profiles, catalog) {
  const profileRows = everyProfile(profiles).map((profile) => {
    const sources = sourcesOf(profiles, profile);
    const all = (key) => sources.flatMap((p) => [...p[key]]);
    const leftOut = sources.includes(profiles.alwaysOn) ? [] : [...profiles.alwaysOn.plugins, ...profiles.alwaysOn.optional];
    return {
      name: profile.name,
      members: profileMembers([...all("plugins"), ...all("optional")], plugins, all("exclude")),
      governed: new Set([...all("plugins"), ...all("optional"), ...all("exclude"), ...leftOut].map(marketplaceOf)),
      hidden: new Set(all("hideSkills")),
      changed: files.some((file) => sources.some((p) => p.name === file.name) && changed.has(file.path)),
    };
  });
  const changedTargets = new Set([...changed].map(skillToken).filter(Boolean).map((token) => `/${token}`));
  const targets = new Map();
  for (const { id, skill } of entries) {
    const token = `/${nameOf(id)}:${skill}`;
    if (!targets.has(token)) targets.set(token, []);
    targets.get(token).push(id);
  }
  const rows = [];
  const add = (kind, line, touched = false) => rows.push({ kind, line, touched });
  for (const { id, path, shown, next, related, unreadable } of entries) {
    const active = profileRows.filter((p) => p.members.has(id));
    if (unreadable) add("unreadable", `links.unreadable: ${shown} cannot be read (${unreadable})`, changed.has(path));
    for (const [kind, tokens] of Object.entries({ next, related })) {
      for (const token of tokens) {
        const ids = targets.get(token);
        const skill = token.split(":")[1];
        const touched = changed.has(path) || changedTargets.has(token);
        if (!ids) {
          add("unresolved", `links.unresolved: ${shown} (links.${kind}) -> ${token} has no skill`, touched || active.some((p) => p.changed));
        } else {
          const own = ids.includes(id);
          for (const p of active) {
            if (!own && !ids.some((target) => p.governed.has(marketplaceOf(target)))) continue;
            if ((own || ids.some((target) => p.members.has(target))) && !p.hidden.has(skill) && !p.hidden.has(token.slice(1))) continue;
            add(kind, `links.${kind}: ${shown} -> ${token} is off in profile ${p.name}`, touched || p.changed);
          }
        }
      }
    }
  }
  if (tree) {
    const named = new Set(everyProfile(profiles).flatMap((p) => [...p.plugins, ...p.optional]));
    for (const name of alphabetical(catalog.plugins)) {
      const id = `${name}@${catalog.name}`;
      if (!named.has(id)) add("unnamed", `Catalog plugin no shipped profile names: ${id}`);
    }
  }
  const touched = rows.filter((row) => row.touched);
  const remaining = rows.filter((row) => !row.touched);
  const ordered = [...touched, ...remaining];
  const lines = (kind) => ordered.filter((row) => row.kind === kind).map((row) => row.line);
  return {
    links: { next: lines("next"), related: lines("related") },
    unnamed: lines("unnamed"),
    unresolved: lines("unresolved"),
    unreadable: lines("unreadable"),
    skillReports: { changed: touched.map((row) => row.line), remaining: remaining.map((row) => row.line) },
  };
}
