// Negative fixture (JS/TS): genuinely discriminating tests. The detector must
// produce ZERO findings here — the false-positive guard that decides whether
// anyone keeps the detector on. Each case names the heuristic it guards.
const { add, mailAndRecord, renderGreeting } = require('./subject');

describe('add', () => {
  // plain value assertion
  test('adds two numbers', () => {
    expect(add(2, 3)).toBe(5);
  });

  // template literal with braces — brace masking must not truncate the block
  test('renders a template greeting', () => {
    const html = renderGreeting('Ada');
    expect(html).toContain(`<p>Hello, ${'Ada'}!</p>`);
  });

  // custom helper carrying an assertion token — generous matching must accept it
  test('uses a helper assertion', () => {
    const result = add(1, 1);
    assertValidSum(result);
  });

  // skipped test — not judged (the dropped skip rule belongs to the incumbent gate)
  test.skip('not implemented yet', () => {
    add(0, 0);
  });

  // mock interaction PLUS a real value assertion — must not fire mock-only-oracle
  test('mails and records', () => {
    const mailer = { send: jest.fn() };
    const receipt = mailAndRecord(mailer);
    expect(mailer.send).toHaveBeenCalledTimes(1);
    expect(receipt.total).toBe(42);
  });

  // matcher on the next line — a chain the line-scoped tautology rule must not misread
  test('multi-line chain', () => {
    expect(add(20, 22))
      .toBe(42);
  });

  // same callee, different arguments — a comparator degraded to function names
  // alone would wrongly call this recomputed
  test('fibonacci recurrence', () => {
    expect(fib(10)).toBe(fib(9) + fib(8));
  });

  // regex literals: braces and slashes inside a regex are data, not code —
  // neither may corrupt brace counting or read as a line comment
  test('strips braces via regex', () => {
    const cleaned = 'a}b}'.replace(/}/g, '');
    expect(cleaned).toBe('ab');
    expect('a/b/c'.split(/\//)).toEqual(['a', 'b', 'c']);
  });
});

// a skipped SUITE — nothing inside runs, so nothing inside is judged
describe.skip('unfinished suite', () => {
  test('pending work', () => {
    add(0, 0);
  });
});
