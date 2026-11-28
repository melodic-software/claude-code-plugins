const { add, mailAndRecord, renderGreeting } = require('./subject');

describe('add', () => {
  // plain value assertion
  test('adds two numbers', () => {
    expect(add(2, 3)).toBe(5);
  });

  // template literal containing braces
  test('renders a template greeting', () => {
    const html = renderGreeting('Ada');
    expect(html).toContain(`<p>Hello, ${'Ada'}!</p>`);
  });

  // assertion through a custom helper
  test('uses a helper assertion', () => {
    const result = add(1, 1);
    assertValidSum(result);
  });

  // skipped test
  test.skip('not implemented yet', () => {
    add(0, 0);
  });

  // mock interaction and a value assertion
  test('mails and records', () => {
    const mailer = { send: jest.fn() };
    const receipt = mailAndRecord(mailer);
    expect(mailer.send).toHaveBeenCalledTimes(1);
    expect(receipt.total).toBe(42);
  });

  // matcher on the next line
  test('multi-line chain', () => {
    expect(add(20, 22))
      .toBe(42);
  });

  // expectation built from the same callee with different arguments
  test('fibonacci recurrence', () => {
    expect(fib(10)).toBe(fib(9) + fib(8));
  });

  // regex literals containing braces and slashes
  test('strips braces via regex', () => {
    const cleaned = 'a}b}'.replace(/}/g, '');
    expect(cleaned).toBe('ab');
    expect('a/b/c'.split(/\//)).toEqual(['a', 'b', 'c']);
  });
});

// skipped suite
describe.skip('unfinished suite', () => {
  test('pending work', () => {
    add(0, 0);
  });
});
