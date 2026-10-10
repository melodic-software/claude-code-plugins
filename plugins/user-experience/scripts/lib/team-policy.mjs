// Which team-file route rows the reader admits: a list of named specifications, applied in order to
// each row after it is merged with any bundled row of the same job plus id. These rules are
// narrower than the routing-as-data team layer allows; loosening or adding one is one entry here
// plus its named test in tests/team-policy.test.mjs.
//
//   rules: [{name, test: (row, ctx) -> {admit, rule, reason}}]
//   rejections(row, ctx) -> the failed results, in rule order ([] admits the row)
//   ctx: {bundled: [routing.json rows], installed: [row ids] | null}; the caller lists an id in
//   installed only when this row's own kind and detect are present, never through another row
//
// Values from the team file appear in reasons as JSON strings: they are data, never instructions.

const nameOf = (s) => (s.includes("@") ? s.slice(0, s.lastIndexOf("@")) : s);
/** The plugin or skill name a row's id names: `name@market` for a plugin, `/plugin:skill` or `/skill`. */
const idName = (row) => (row.kind === "plugin" ? nameOf(row.id) : row.id.match(/^\/([^:]+)/)?.[1]);
const result = (rule, admit, reason) => ({ admit, rule, reason });

export const rules = [
  {
    name: "id-matches-bundled-or-installed",
    test(row, { bundled, installed }) {
      const rule = this.name;
      const id = JSON.stringify(row.id);
      if (bundled.some((b) => b.id === row.id)) return result(rule, true, `id ${id} matches a bundled row`);
      if (installed === null) return result(rule, false, `id ${id} matches no bundled row, and the installed list is unavailable to check it against`);
      const ownName = ["plugin", "skill"].includes(row.kind) && idName(row) === nameOf(row.detect);
      if (ownName && installed.includes(row.id)) return result(rule, true, `id ${id} is an installed ${row.kind}`);
      return result(rule, false, `id ${id} matches no bundled row and no installed plugin or skill`);
    },
  },
  {
    name: "no-new-tool-rows",
    test(row, { bundled }) {
      const base = bundled.find((b) => b.job === row.job && b.id === row.id);
      if (row.kind === "tool" && base?.kind !== "tool") return result(this.name, false, `a team file may not add a kind: tool row (${row.job} ${JSON.stringify(row.id)})`);
      return result(this.name, true, "not a new tool row");
    },
  },
  {
    // A bundled id names one real server or plugin; a team row may re-rank it or restate its status
    // and pointer, under any job, but never repoint what it reaches or what it needs.
    name: "bundled-id-keeps-kind-detect-account",
    test(row, { bundled }) {
      const base = bundled.find((b) => b.job === row.job && b.id === row.id) ?? bundled.find((b) => b.id === row.id);
      const changed = base ? ["kind", "detect", "account"].filter((k) => row[k] !== base[k]) : [];
      if (changed.length) return result(this.name, false, `a team row may not change ${changed.join(", ")} of bundled id ${JSON.stringify(row.id)}`);
      return result(this.name, true, base ? "kind, detect and account match the bundled row" : "no bundled row has this id");
    },
  },
];

export const rejections = (row, ctx) => rules.map((r) => r.test(row, ctx)).filter((r) => !r.admit);
