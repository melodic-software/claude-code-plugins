import { existsSync, readdirSync, statSync } from "node:fs";
import { isAbsolute, join, relative, resolve, sep } from "node:path";
import { validate } from "./routing-validate.mjs";

const fileError = (root, path) => {
  const full = resolve(root, path);
  const rel = relative(root, full);
  if (rel.startsWith(`..${sep}`) || rel === ".." || isAbsolute(rel)) return `${path} leaves the plugin root`;
  return existsSync(full) && statSync(full).isFile() ? null : `no file ${path}`;
};

/** Errors for the concern table; empty when it fits. */
export function checkConcerns(table, { pluginRoot, schema, routing }) {
  const errors = validate(schema, table);
  if (errors.length) return errors;
  const types = new Set(readdirSync(join(pluginRoot, "reference/types")).filter((f) => f.endsWith(".md")).map((f) => f.slice(0, -3)));
  const routed = new Set(routing.rows.map((r) => r.concern));
  const seen = new Set();
  const orders = new Map();
  const file = (at, path) => {
    const error = fileError(pluginRoot, path);
    if (error) errors.push(`${at}: ${error}`);
  };
  table.concerns.forEach((c, i) => {
    const at = `$.concerns[${i}]`;
    if (seen.has(c.id)) errors.push(`${at}.id: duplicate id ${c.id}`);
    else if (orders.has(c.audit.order)) errors.push(`${at}.audit.order: duplicate order ${c.audit.order}, also ${orders.get(c.audit.order)}`);
    seen.add(c.id);
    if (!orders.has(c.audit.order)) orders.set(c.audit.order, c.id);
    c.types.forEach((t, j) => types.has(t) || errors.push(`${at}.types[${j}]: no type file reference/types/${t}.md`));
    c.spokes.forEach((s, j) => file(`${at}.spokes[${j}].path`, s.path));
    c.recipes.forEach((p, j) => file(`${at}.recipes[${j}]`, p));
    c.routing_concerns.forEach((r, j) => routed.has(r) || errors.push(`${at}.routing_concerns[${j}]: no routing.json concern ${r}`));
    const { procedure } = c.audit;
    if (procedure !== null && typeof procedure !== "string") errors.push(`${at}.audit.procedure: must be null or a path`);
    else if (procedure !== null) file(`${at}.audit.procedure`, procedure);
  });
  return errors;
}
