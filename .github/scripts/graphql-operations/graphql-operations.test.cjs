"use strict";

// GraphQL operations committed under .github/ and plugins/ validate against
// GitHub's public schema. GitHub rejects an invalid operation only at run
// time, after the lane that sends it has already started, so a spread of a
// type that cannot occur at that position (a User-typed field spread
// `... on Bot`) breaks every run until someone notices. The extraction rules
// are melodic-software/ci-workflows' .github/scripts/graphql-operations.test.cjs,
// widened for what this tree assembles:
// - every string literal that opens with `query`, `mutation` or
//   `subscription` (after an optional `query=`) and then `(` or `{` (an
//   operation name between them is allowed) parses and validates, over
//   tracked JS, shell and workflow files (test files excluded). Python
//   sources are not scanned: their operations join adjacent literals and
//   f-strings, which `read` does not follow (unextractable.txt records it);
// - in JS, a `+` chain continues the literal, and `${NAME}` or `+ NAME` takes
//   the value of a same-file `const NAME =` built only from literals;
// - any other interpolation (JS `${...}`, workflow `${{ }}`, shell `$NAME`,
//   `${...}` and `$(...)` outside single quotes) takes a placeholder of its
//   position: text inside a GraphQL string, `"interpolated"` in an argument
//   value (a type error on it alone is dropped), `__typename` in a selection
//   set, and nothing elsewhere. One followed by arguments or a selection names
//   a field, which no placeholder can stand for. Once a placeholder stands in,
//   an unused variable or fragment is not an error: the interpolated text may
//   use it;
// - a literal that opens with `{` and reads as a shorthand query, and
//   `query=@file`, cannot be checked here;
// - a file with more request sites (`github.graphql(`,
//   `github.graphql.paginate(`, `request("POST /graphql"`, or a `gh api` /
//   `gh_api` command whose path is `graphql`, continuation lines joined, and
//   not a `function graphql(` wrapper) than extracted operations has sites it
//   cannot see.
// An operation that does not parse after that or names a field by
// interpolation, a shorthand or `query=@file`, and each unseen request site
// count against their file. unextractable.txt
// lists each such file with its count and a reason, and the paths whose
// operations go to another GraphQL API; the test fails when the counts differ
// from that list, either way.
//
// The schema is GitHub's published SDL, at
// schemas/github/schema.docs.graphql.gz here and in ci-workflows (outside
// .github/, so the review lanes can skip the blob); refresh both with
// `gzip -9 -n` over
// https://docs.github.com/public/fpt/schema.docs.graphql when an operation
// needs a newer field.

const assert = require("node:assert/strict");
const { execFileSync } = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const { gunzipSync } = require("node:zlib");

const { buildSchema, Kind, parse, validate } = require("graphql");

const ROOT = path.resolve(__dirname, "..", "..", "..");
const SCHEMA = path.join(ROOT, "schemas", "github", "schema.docs.graphql.gz");
const ALLOWLIST = path.join(__dirname, "unextractable.txt");
const SOURCE = /\.(?:c?js|mjs|sh|bash|ya?ml)$/;
const OPENING =
  /[`'"]\s*(?:query=)?(?:query|mutation|subscription)\b\s*(?:[A-Za-z_]\w*\s*)?[({]/g;
const SHORTHAND = /[`'"]\s*\{/g;
const CALL_SITE =
  /\bgraphql(?:\.paginate)?\(|\brequest\(\s*[`'"](?:POST\s+)?\/graphql\b|\bgh(?:_api|\s+api)\b.*\sgraphql\b/;
const WRAPPER = /\bfunction\s+graphql\(/;
const QUERY_FILE = /\bquery=@/;
const COMMENT = /^\s*(?:#|\/\/|\*)/;
const CONSTANT = /\b(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=\s*/g;
const IDENTIFIER = /^[A-Za-z_$][\w$]*$/;
const PLACEHOLDER = "interpolated";
const SELECTION = "__typename";

function trackedSources(excluded) {
  return execFileSync(
    "git",
    ["-C", ROOT, "ls-files", "-z", "--", ".github", "plugins"],
    { encoding: "utf8", maxBuffer: 64 * 1024 * 1024 },
  )
    .split("\0")
    .filter(
      (file) =>
        SOURCE.test(file) &&
        !/\.test\.[^/]+$/.test(file) &&
        !excluded.some((prefix) => file.startsWith(prefix)),
    );
}

// unextractable.txt: `exclude <path prefix> <reason>` or
// `<file> <count> <reason>`, `#` comments.
function readAllowlist(text) {
  const excluded = new Map();
  const counts = new Map();
  for (const raw of text.split("\n")) {
    const line = raw.replace(/#.*/, "").trim();
    if (!line) continue;
    const [key, value, ...reason] = line.split(/\s+/);
    assert.ok(reason.length > 0, `unextractable.txt: no reason on "${line}"`);
    if (key === "exclude") excluded.set(value, reason.join(" "));
    else counts.set(key, Number(value));
  }
  return { excluded, counts };
}

// Whether the literal at `index` follows shell quoting: always in a shell
// script; in a workflow only inside a `run:` value, while a github-script
// `script:` body and everything else follow JS rules.
function shellAt(file, text, index) {
  if (/\.(?:sh|bash)$/.test(file)) return true;
  if (!/\.ya?ml$/.test(file)) return false;
  const lines = text.slice(0, index).split("\n");
  const own = lines[lines.length - 1];
  const inline = own.match(/^\s*(?:-\s+)?([\w-]+):/);
  if (inline) return inline[1] === "run";
  const indent = own.match(/^\s*/)[0].length;
  for (let n = lines.length - 2; n >= 0; n -= 1) {
    const key = lines[n].match(/^(\s*)(?:-\s+)?([\w-]+):/);
    if (key && key[1].length < indent) return key[2] === "run";
  }
  return false;
}

// The length of the balanced `open`...`close` group starting at `i`.
function groupLength(text, i, open, close) {
  let depth = 0;
  for (let j = i; j < text.length; j += 1) {
    if (text[j] === open) depth += 1;
    else if (text[j] === close && --depth === 0) return j + 1 - i;
  }
  return text.length - i;
}

// The length of the substitution starting with the `$` at `i`, or 0: a
// workflow `${{ }}` in every quoting, `${...}` in a JS template or outside
// shell single quotes, and shell `$NAME`, `$(...)` and `$1`-style parameters.
function substitutionLength(text, i, shell, quote) {
  const next = text[i + 1];
  if (text.startsWith("{{", i + 1)) return 1 + groupLength(text, i + 1, "{", "}");
  if (shell && quote === "'") return 0;
  if (next === "{" && (shell || quote === "`")) {
    return 1 + groupLength(text, i + 1, "{", "}");
  }
  if (!shell) return 0;
  if (next === "(") return 1 + groupLength(text, i + 1, "(", ")");
  const name = /^[A-Za-z_]\w*|^[0-9@#?*!$-]/.exec(text.slice(i + 1, i + 65));
  return name ? 1 + name[0].length : 0;
}

// What an unresolved substitution becomes at the end of `out`, given the
// source text after it. One that names a field (arguments or a selection
// follow it) has no placeholder and leaves the operation opaque.
function placeholder(out, scope, after = "") {
  if ((out.match(/(?<!\\)"/g) ?? []).length % 2 === 1) return PLACEHOLDER;
  const code = out.replace(/"(?:[^"\\]|\\.)*"/g, '""');
  let parens = 0;
  let braces = 0;
  for (const c of code) {
    if (c === "(") parens += 1;
    else if (c === ")") parens -= 1;
    else if (c === "{") braces += 1;
    else if (c === "}") braces -= 1;
  }
  scope.complete = false;
  if (parens > 0) return /[:[=]\s*$/.test(code) ? ` "${PLACEHOLDER}" ` : " ";
  if (braces > 0) {
    if (/^\s*[({]/.test(after)) scope.opaque = true;
    return ` ${SELECTION} `;
  }
  return " ";
}

// The value of a same-file constant built only from literals, or null.
function resolve(scope, name) {
  if (!scope.constants?.has(name) || scope.resolving.has(name)) return null;
  if (scope.values.has(name)) return scope.values.get(name);
  scope.resolving.add(name);
  const at = scope.constants.get(name);
  const inner = { ...scope, complete: true, opaque: false };
  let value = null;
  const number = /^-?\d+(?:\.\d+)?/.exec(scope.text.slice(at, at + 32));
  if (number) {
    if (/^[ \t]*(?:[;,\n]|$)/.test(scope.text.slice(at + number[0].length))) {
      value = number[0];
    }
  } else if (/[`'"]/.test(scope.text[at])) {
    const chain = readChain(scope.text, at, inner);
    if (
      chain &&
      inner.complete &&
      /^\s*(?:[;,)}]|$)/.test(scope.text.slice(chain.end))
    ) {
      value = chain.body;
    }
  }
  scope.resolving.delete(name);
  scope.values.set(name, value);
  return value;
}

function substitute(out, expression, scope, after) {
  const inner = /^\$\{([^{].*)\}$/s.exec(expression)?.[1].trim();
  if (!scope.shell && inner && IDENTIFIER.test(inner)) {
    const value = resolve(scope, inner);
    if (value !== null) return value;
  }
  return placeholder(out, scope, after);
}

// The body of the literal opening at `start`, substitutions replaced, and
// where it ends, or null when it never closes. Shell single quotes have no
// escapes, except the `'\''` idiom that closes, escapes and reopens one.
function readLiteral(text, start, scope, prefix = "") {
  const quote = text[start];
  const raw = quote === "'" && scope.shell;
  let out = prefix;
  let i = start + 1;
  while (i < text.length) {
    const c = text[i];
    const length = c === "$" ? substitutionLength(text, i, scope.shell, quote) : 0;
    if (length > 0) {
      out += substitute(
        out,
        text.slice(i, i + length),
        scope,
        text.slice(i + length, i + length + 64),
      );
      i += length;
    } else if (raw && c === "'") {
      if (!text.startsWith("'\\''", i)) {
        return { body: out.slice(prefix.length), end: i + 1 };
      }
      out += "'";
      i += 4;
    } else if (!raw && c === "\\") {
      out += text[i + 1] === "n" ? "\n" : text[i + 1];
      i += 2;
    } else if (!raw && c === quote) {
      return { body: out.slice(prefix.length), end: i + 1 };
    } else {
      out += c;
      i += 1;
    }
  }
  return null;
}

// The length of the JS expression at `i`, up to a `+`, `;`, `,` or closing
// bracket at its own depth.
function expressionLength(text, i) {
  let depth = 0;
  let j = i;
  while (j < text.length) {
    const c = text[j];
    if (/[`'"]/.test(c)) {
      const literal = readLiteral(text, j, { shell: false, values: new Map() });
      if (!literal) return text.length - i;
      j = literal.end;
      continue;
    }
    if ("([{".includes(c)) depth += 1;
    else if (")]}".includes(c)) {
      if (depth === 0) break;
      depth -= 1;
    } else if (depth === 0 && /[+;,]/.test(c)) break;
    j += 1;
  }
  return j - i;
}

// The literal at `start` and, in JS, every `+` operand after it.
function readChain(text, start, scope) {
  const first = readLiteral(text, start, scope);
  if (!first || scope.shell) return first;
  let body = first.body;
  let i = first.end;
  for (;;) {
    const plus = /^\s*\+(?![+=])\s*/.exec(text.slice(i, i + 256));
    if (!plus) return { body, end: i };
    const j = i + plus[0].length;
    if (/[`'"]/.test(text[j])) {
      const next = readLiteral(text, j, scope, body);
      if (!next) return { body, end: i };
      body += next.body;
      i = next.end;
      continue;
    }
    const length = expressionLength(text, j);
    const expression = text.slice(j, j + length).trim();
    const value = IDENTIFIER.test(expression) ? resolve(scope, expression) : null;
    const after = text
      .slice(j + length, j + length + 64)
      .replace(/^\s*\+\s*[`'"]?/, "");
    body += value ?? placeholder(body, scope, after);
    i = j + length;
  }
}

function lineOf(text, index) {
  return text.slice(0, index).split("\n").length;
}

// A literal opening with `{` is a shorthand operation when it parses as one
// anonymous query whose root fields all exist on Query; jq filters and JSON
// fail one of those checks.
function isShorthand(schema, source) {
  let document;
  try {
    document = parse(source);
  } catch {
    return false;
  }
  const [definition, ...rest] = document.definitions;
  if (rest.length > 0 || definition.kind !== Kind.OPERATION_DEFINITION) {
    return false;
  }
  if (definition.name || definition.loc.startToken.kind !== "{") return false;
  const fields = schema.getQueryType().getFields();
  return definition.selectionSet.selections.every(
    (selection) =>
      selection.kind === Kind.FIELD && selection.name.value in fields,
  );
}

function extract(schema, file, text) {
  const operations = [];
  const unsupported = [];
  const js = /\.(?:c?js|mjs)$/.test(file);
  const constants = new Map();
  if (js) {
    for (const match of text.matchAll(CONSTANT)) {
      if (!constants.has(match[1])) {
        constants.set(match[1], match.index + match[0].length);
      }
    }
  }
  const values = new Map();
  const read = (index) => {
    const scope = {
      text,
      shell: shellAt(file, text, index),
      constants,
      values,
      resolving: new Set(),
      complete: true,
      opaque: false,
    };
    const chain = js
      ? readChain(text, index, scope)
      : readLiteral(text, index, scope);
    return (
      chain && {
        source: chain.body.replace(/^\s*query=/, ""),
        partial: !scope.complete,
        opaque: scope.opaque,
      }
    );
  };
  for (const match of text.matchAll(OPENING)) {
    const literal = read(match.index);
    if (literal !== null) {
      operations.push({ file, line: lineOf(text, match.index), ...literal });
    }
  }
  for (const match of text.matchAll(SHORTHAND)) {
    const literal = read(match.index);
    if (literal !== null && isShorthand(schema, literal.source)) {
      unsupported.push(
        `${file}:${lineOf(text, match.index)}: shorthand operation; open it with \`query\``,
      );
    }
  }
  const lines = text.split("\n");
  lines.forEach((line, n) => {
    if (QUERY_FILE.test(line) && !COMMENT.test(line)) {
      unsupported.push(`${file}:${n + 1}: query=@file is not checked`);
    }
  });
  const callSites = text
    .replace(/\\\r?\n/g, " ")
    .split("\n")
    .filter(
      (line) =>
        CALL_SITE.test(line) && !COMMENT.test(line) && !WRAPPER.test(line),
    ).length;
  return { operations, unsupported, callSites };
}

const placeholderValue = (node) =>
  node.kind === Kind.STRING && node.value === PLACEHOLDER;

// `syntax` when the operation cannot be checked, else its validation errors
// less the ones its placeholders cause: a type error on a placeholder value,
// and, once any placeholder stands in, a variable or fragment the
// interpolated text may have used.
function problems(schema, operation) {
  if (operation.opaque) {
    return { syntax: "an interpolation names a field", errors: [] };
  }
  let document;
  try {
    document = parse(operation.source);
  } catch (error) {
    return { syntax: error.message, errors: [] };
  }
  const errors = validate(schema, document)
    .filter(
      (error) =>
        !error.nodes?.length || !error.nodes.every(placeholderValue),
    )
    .filter(
      (error) =>
        !operation.partial ||
        !/^(?:Variable|Fragment) ".+" is never used/.test(error.message),
    )
    .map((error) => error.message);
  return { syntax: null, errors };
}

// assumeValid skips the type-system rules, which GitHub's own schema breaks
// (an implementation field deprecated where its interface field is not);
// operations are still validated against every type and field it defines.
const schema = buildSchema(
  gunzipSync(fs.readFileSync(SCHEMA)).toString("utf8"),
  { assumeValid: true },
);
const allowlist = readAllowlist(fs.readFileSync(ALLOWLIST, "utf8"));
const files = trackedSources([...allowlist.excluded.keys()]).map((file) => {
  const entry = extract(
    schema,
    file,
    fs.readFileSync(path.join(ROOT, file), "utf8"),
  );
  const checked = entry.operations.map((operation) => ({
    ...operation,
    ...problems(schema, operation),
  }));
  const unparsed = checked
    .filter((operation) => operation.syntax)
    .map((operation) => `${file}:${operation.line}: ${operation.syntax}`);
  const gap = Math.max(0, entry.callSites - entry.operations.length);
  const unseen = gap
    ? [`${file}: ${entry.callSites} request sites, ${entry.operations.length} operations`]
    : [];
  return {
    file,
    checked,
    unextractable: [...unparsed, ...entry.unsupported, ...unseen],
    count: unparsed.length + entry.unsupported.length + gap,
  };
});

test("the schema rejects a fragment spread its position cannot hold", () => {
  const source = `query($owner: String!, $name: String!, $number: Int!) {
    repository(owner: $owner, name: $name) { pullRequest(number: $number) {
      reviewThreads(first: 1) { nodes { resolvedBy { ... on Bot { login } } } }
    } }
  }`;
  const { errors } = problems(schema, { source });
  assert.ok(
    errors.some((message) => /cannot be spread/.test(message)),
    errors.join("\n") || "validated without errors",
  );
});

test("the extractor reports the shapes it cannot check", () => {
  const sample = [
    "await github.graphql.paginate(`{ viewer { login } }`);",
    "await github.request('POST /graphql', { query: q });",
    "gh api \\",
    "  graphql -f query=@op.graphql",
    "jq '{ number }'",
    "// 'query value, to the second' is prose",
    "async function graphql(query, variables) {}",
  ].join("\n");
  const { operations, unsupported, callSites } = extract(
    schema,
    "sample.cjs",
    sample,
  );
  assert.equal(operations.length, 0);
  assert.equal(callSites, 3);
  assert.deepEqual(unsupported, [
    "sample.cjs:1: shorthand operation; open it with `query`",
    "sample.cjs:4: query=@file is not checked",
  ]);
});

test("workflow expressions and shell parameters are replaced", () => {
  const expression = `$\{{ github.repository_owner }}`;
  const yaml = [
    "      - run: |",
    `          gh api graphql -f query='query { repository(owner: "${expression}", name: "x") { id } }'`,
    `          gh api graphql -f query="query { viewer { $fields pullRequests(first: $(count)) { totalCount } } }"`,
    "          gh api graphql -f 'query=query{viewer{login}}'",
  ].join("\n");
  const operations = extract(schema, "w.yml", yaml).operations;
  assert.equal(operations.length, 3);
  for (const operation of operations) {
    assert.deepEqual(problems(schema, operation), { syntax: null, errors: [] });
  }
});

test("JS constants resolve and other interpolations take their position's placeholder", () => {
  const sample = [
    'const ACTOR = "{ ... on User { databaseId } ... on Bot { databaseId } }";',
    "const PAGE = 100;",
    "const FIELDS = `login author ${ACTOR}`;",
    "const q = `query($o: String!) { repository(owner: $o, name: ${name}) {",
    "  pullRequests(first: ${PAGE}) { nodes { ${extra} author ${ACTOR} } }",
    '} }`;',
    'const bad = "query { viewer { " + FIELDS + " } }";',
    'const joined = "query { viewer { " +',
    "  list.map((x) => `a${x}: login`).join(\" \") +",
    '  " } }";',
    "const named = `query { viewer { ${connection}(first: 1) { totalCount } } }`;",
  ].join("\n");
  const operations = extract(schema, "sample.mjs", sample).operations;
  assert.deepEqual(
    operations.map((operation) => problems(schema, operation)),
    [
      { syntax: null, errors: [] },
      {
        syntax: null,
        errors: ['Cannot query field "author" on type "User".'],
      },
      { syntax: null, errors: [] },
      { syntax: "an interpolation names a field", errors: [] },
    ],
  );
});

test("unextractable.txt lists every site the extractor cannot check", (t) => {
  for (const [prefix, reason] of allowlist.excluded) {
    assert.ok(
      trackedSources([]).some((file) => file.startsWith(prefix)),
      `unextractable.txt excludes ${prefix} (${reason}), which matches no tracked source`,
    );
  }
  const found = files
    .filter((entry) => entry.count > 0)
    .map((entry) => `${entry.file} ${entry.count}`);
  const listed = [...allowlist.counts].map(([file, count]) => `${file} ${count}`);
  for (const entry of files) {
    for (const line of entry.unextractable) t.diagnostic(line);
  }
  assert.deepEqual(found.sort(), listed.sort());
});

test("every committed GraphQL operation validates against GitHub's schema", (t) => {
  const operations = files.flatMap((entry) => entry.checked);
  const failures = operations.flatMap((operation) =>
    operation.errors.map(
      (message) => `${operation.file}:${operation.line}: ${message}`,
    ),
  );
  const validated = operations.filter((operation) => !operation.syntax).length;
  t.diagnostic(
    `${validated} operations validated, ${operations.length - validated} unparsed, across ${files.filter((entry) => entry.checked.length > 0).length} files`,
  );
  assert.deepEqual(failures, []);
});
