// For the workflow tests that hold a lane's credential chain on
// ci-workflows' select-model-credential: the action's own rules, fetched at
// the pin the workflows name (no copy lives here), the launcher's own
// handoffReason at that pin, and an expression evaluator with GitHub's value
// semantics, so a job's `if:` and an input's `${{ }}` evaluate as GitHub
// evaluates them.
import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, writeFileSync } from "node:fs";
import { createRequire } from "node:module";
import { tmpdir } from "node:os";
import { dirname, join, posix } from "node:path";

// The one pin every select-model-credential step in the given workflows names.
export function selectPin(...workflowTexts) {
  const pins = new Set(workflowTexts.flatMap((text) => [...text.matchAll(/uses: melodic-software\/ci-workflows\/\.github\/actions\/select-model-credential@([0-9a-f]{40})/g)].map((m) => m[1])));
  assert.equal(pins.size, 1, `one select-model-credential pin, found ${[...pins].join(", ")}`);
  return [...pins][0];
}

// Fetches `entry` and every relative file it requires, at `pin`, into a
// fresh directory, and requires it from there.
async function fetchModule(pin, entry) {
  const root = mkdtempSync(join(tmpdir(), "ci-workflows-"));
  const seen = new Set();
  const queue = [entry];
  while (queue.length) {
    const path = queue.shift();
    if (seen.has(path)) continue;
    seen.add(path);
    const url = `https://raw.githubusercontent.com/melodic-software/ci-workflows/${pin}/${path}`;
    const response = await fetch(url, { signal: AbortSignal.timeout(15000) });
    assert.ok(response.ok, `${url} answered ${response.status}`);
    const text = await response.text();
    mkdirSync(join(root, dirname(path)), { recursive: true });
    writeFileSync(join(root, path), text);
    for (const [, spec] of text.matchAll(/require\(\s*"(\.{1,2}\/[^"]+)"\s*\)/g)) {
      queue.push(posix.normalize(posix.join(posix.dirname(path), spec)));
    }
  }
  return createRequire(join(root, "package.json"))(`./${entry}`);
}

// The action's start/leg/next and the launcher's handoffReason, at `pin`.
export async function loadSelect(pin) {
  const select = await fetchModule(pin, ".github/actions/select-model-credential/select.cjs");
  const { handoffReason } = await fetchModule(pin, ".github/actions/run-claude-cli/lane.cjs");
  assert.equal(typeof handoffReason, "function", "lane.cjs exports handoffReason at the pin");
  return { ...select, handoffReason };
}

// One expression, `${{ }}` or bare, over `context` (a flat map of
// `needs.x.outputs.y`-style names to strings; a missing name reads as '').
// `&&` and `||` return an operand, as GitHub's do; `==` and `!=` compare
// strings; `always()` is true, and `cancelled()` is true only when the
// context sets `cancelled()` (a job that hit its own timeout, or a cancelled
// run), so a state can model a step that runs after a job timed out.
const TOKENS = new Map();
function tokenize(expression) {
  if (!TOKENS.has(expression)) {
    const text = expression.trim().replace(/^\$\{\{([\s\S]*)\}\}$/, "$1").trim();
    const tokens = text.match(/\|\||&&|==|!=|!|\(|\)|'[^']*'|cancelled\(\)|always\(\)|[A-Za-z_][\w.-]*/g) ?? [];
    assert.equal(tokens.join(""), text.replace(/\s+/g, ""), `only known tokens in ${text}`);
    TOKENS.set(expression, { text, tokens });
  }
  return TOKENS.get(expression);
}

export function evaluate(expression, context) {
  const { text, tokens } = tokenize(expression);
  let at = 0;
  const peek = () => tokens[at];
  const take = (expected) => {
    assert.ok(expected === undefined || tokens[at] === expected, `${expected} at ${at} in ${text}`);
    return tokens[at++];
  };
  const truthy = (v) => v !== "" && v !== false;
  const operand = () => {
    if (peek() === "(") {
      take("(");
      const inner = or();
      take(")");
      return inner;
    }
    if (peek() === "!") {
      take("!");
      return !truthy(operand());
    }
    const token = take();
    if (token === "cancelled()") return context["cancelled()"] === true;
    if (token === "always()") return true;
    if (/^'.*'$/.test(token)) return token.slice(1, -1);
    assert.ok(/^(?:needs|steps|github|vars|inputs|secrets)\./.test(token), `a context name: ${token} in ${text}`);
    return context[token] ?? "";
  };
  const comparison = () => {
    const left = operand();
    if (peek() !== "==" && peek() !== "!=") return left;
    const op = take();
    const right = operand();
    return op === "==" ? String(left) === String(right) : String(left) !== String(right);
  };
  const and = () => {
    let result = comparison();
    while (peek() === "&&") {
      take("&&");
      const right = comparison();
      result = truthy(result) ? right : result;
    }
    return result;
  };
  const or = () => {
    let result = and();
    while (peek() === "||") {
      take("||");
      const right = and();
      result = truthy(result) ? result : right;
    }
    return result;
  };
  const result = or();
  assert.equal(at, tokens.length, `the whole expression parsed: ${text}`);
  return result;
}

// A job condition: GitHub coerces the result to a boolean.
export const runs = (condition, context) => {
  const v = evaluate(condition, context);
  return v !== "" && v !== false;
};

// An input value, as the string the step receives: a literal as written,
// a `${{ }}` expression evaluated.
export const value = (input, context) => {
  if (!/^\s*\$\{\{[\s\S]*\}\}\s*$/.test(input)) return input.trim().replace(/^"(.*)"$/, "$1");
  const v = evaluate(input, context);
  return typeof v === "boolean" ? String(v) : v;
};

// Every launcher outcome run-claude-cli can produce on `leg` (api-key,
// subscription or fallback), as { handoff, reason }: its own handoffReason
// over every failure class and API status, with and without a limit or
// credit stop.
export function launcherOutcomes(handoffReason, leg, fallbackReady) {
  const seen = new Map();
  for (const failureClass of ["", "credit-stop", "auth", "rate-limit", "other", "timeout"]) {
    for (const status of [undefined, 401, 402, 403, 429, 500]) {
      for (const limitStop of [false, true]) {
        for (const creditStop of [false, true]) {
          const reason = handoffReason({ leg }, failureClass, status, { fallbackReady, limitStop, creditStop });
          seen.set(reason, { handoff: String(reason !== ""), reason });
        }
      }
    }
  }
  return [...seen.values()];
}

