// A job-level `if:` gate evaluated on one run's context, for the workflow
// tests: `a == b` and `a != b` terms, `!cancelled()`, `&&`, `||` and
// parentheses, a missing value reading as '' as GitHub's null does. Any other
// shape fails the calling test.
import assert from "node:assert/strict";

export const admits = (gate, context, { cancelled = false } = {}) => {
  const tokens = gate.match(/\|\||&&|==|!=|!|\(|\)|'[^']*'|cancelled\(\)|[A-Za-z_][\w.-]*/g) ?? [];
  assert.equal(tokens.join(""), gate.replace(/\s+/g, ""), "the gate holds only known tokens");
  let at = 0;
  const peek = () => tokens[at];
  const take = (expected) => {
    assert.ok(expected === undefined || tokens[at] === expected, `${expected} at ${at} in ${gate}`);
    return tokens[at++];
  };
  const value = (term) => (/^'.*'$/.test(term) ? term.slice(1, -1) : (term.split(".").reduce((node, key) => node?.[key], context) ?? ""));
  const primary = () => {
    if (peek() === "(") {
      take("(");
      const inner = or();
      take(")");
      return inner;
    }
    const left = take();
    if (left === "cancelled()") return cancelled;
    const op = take();
    assert.ok(op === "==" || op === "!=", `a comparison after ${left} in ${gate}`);
    const right = take();
    return op === "==" ? value(left) === value(right) : value(left) !== value(right);
  };
  const unary = () => (peek() === "!" ? (take("!"), !unary()) : primary());
  const and = () => {
    let result = unary();
    while (peek() === "&&") result = take("&&") && unary() && result;
    return result;
  };
  const or = () => {
    let result = and();
    while (peek() === "||") result = take("||") && (and() || result);
    return result;
  };
  const result = or();
  assert.equal(at, tokens.length, `the whole gate parsed: ${gate}`);
  return result;
};
