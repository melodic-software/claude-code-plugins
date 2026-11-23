// GitHub Actions expressions, `${{ }}` or bare, evaluated for the workflow
// tests by the rules of
// https://docs.github.com/en/actions/reference/workflows-and-actions/expressions:
// literals, context paths, `!`, `==`, `!=`, `&&` and `||` (each returning an
// operand), parentheses, the status functions, contains(), startsWith(),
// format() and fromJSON(). Strings compare case-insensitively and mismatched
// types compare as numbers. A context path no context sets reads as ''. Any
// other shape fails the calling test.
import assert from "node:assert/strict";

const TOKEN = /\s*('(?:[^']|'')*'|==|!=|&&|\|\||[!(),]|\d+(?:\.\d+)?|[A-Za-z_][\w.-]*)/y;
const CONTEXT = /^(?:github|env|vars|job|steps|runner|secrets|needs|inputs)\./;
const STATUS = /\b(?:always|success|failure|cancelled)\(\s*\)/;
const LITERALS = { true: true, false: false, null: null };

const unwrap = (expression) => expression.trim().replace(/^\$\{\{([\s\S]*)\}\}$/, "$1").trim();

const TOKENS = new Map();
function tokenize(expression) {
  if (!TOKENS.has(expression)) {
    const text = unwrap(expression);
    const tokens = [];
    for (TOKEN.lastIndex = 0; TOKEN.lastIndex < text.length; ) {
      const at = TOKEN.lastIndex;
      const match = TOKEN.exec(text);
      assert.ok(match, `a known token at ${at} in ${text}`);
      tokens.push(match[1]);
    }
    TOKENS.set(expression, { text, tokens });
  }
  return TOKENS.get(expression);
}

export const truthy = (v) => !(v === false || v === 0 || v === "" || v === null || v === undefined || Number.isNaN(v));
const string = (v) => (v === null || v === undefined ? "" : String(v));
const number = (v) => (v === null || v === undefined ? 0 : typeof v === "object" ? NaN : Number(v));
const equal = (a, b) => {
  if (typeof a === "string" && typeof b === "string") return a.toLowerCase() === b.toLowerCase();
  if (typeof a === "object" && typeof b === "object") return a === b;
  return number(a) === number(b);
};
const FUNCTIONS = {
  contains: (search, item) => (Array.isArray(search) ? search.some((x) => equal(x, item)) : string(search).toLowerCase().includes(string(item).toLowerCase())),
  startsWith: (text, prefix) => string(text).toLowerCase().startsWith(string(prefix).toLowerCase()),
  format: (template, ...args) => string(template).replace(/\{(\d+)\}/g, (_, i) => string(args[Number(i)])),
  fromJSON: (text) => JSON.parse(text),
};

export function evaluate(expression, context = {}, { status = "success" } = {}) {
  const { text, tokens } = tokenize(expression);
  const lookup = typeof context === "function" ? context : (path) => (Object.hasOwn(context, path) ? context[path] : path.split(".").reduce((node, key) => node?.[key], context));
  const statusFunctions = { always: () => true, success: () => status === "success", failure: () => status === "failure", cancelled: () => status === "cancelled" };
  let at = 0;
  const peek = () => tokens[at];
  const take = (expected) => {
    assert.ok(expected === undefined ? at < tokens.length : tokens[at] === expected, `${expected ?? "an operand"} at token ${at} in ${text}`);
    return tokens[at++];
  };
  const primary = () => {
    const token = take();
    if (token === "!") return !truthy(primary());
    if (token === "(") {
      const inner = or();
      take(")");
      return inner;
    }
    if (token.startsWith("'")) return token.slice(1, -1).replaceAll("''", "'");
    if (/^\d/.test(token)) return Number(token);
    if (Object.hasOwn(LITERALS, token)) return LITERALS[token];
    if (peek() === "(") {
      const fn = FUNCTIONS[token] ?? statusFunctions[token];
      assert.ok(fn, `a known function: ${token} in ${text}`);
      take("(");
      const args = [];
      while (peek() !== ")") {
        args.push(or());
        if (peek() !== ")") take(",");
      }
      take(")");
      return fn(...args);
    }
    assert.match(token, CONTEXT, `a context path: ${token} in ${text}`);
    return lookup(token) ?? "";
  };
  const comparison = () => {
    let left = primary();
    while (peek() === "==" || peek() === "!=") {
      const op = take();
      const right = primary();
      left = op === "==" ? equal(left, right) : !equal(left, right);
    }
    return left;
  };
  const and = () => {
    let left = comparison();
    while (peek() === "&&") {
      take("&&");
      const right = comparison();
      left = truthy(left) ? right : left;
    }
    return left;
  };
  const or = () => {
    let left = and();
    while (peek() === "||") {
      take("||");
      const right = and();
      left = truthy(left) ? left : right;
    }
    return left;
  };
  const result = or();
  assert.equal(at, tokens.length, `the whole expression parsed: ${text}`);
  return result;
}

export const admits = (condition, context, { status = "success" } = {}) =>
  (STATUS.test(condition) || status === "success") && (unwrap(condition) === "" || truthy(evaluate(condition, context, { status })));
