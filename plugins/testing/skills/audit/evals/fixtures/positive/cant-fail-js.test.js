// Positive fixture (JS/TS): one planted defect per rule, plus a pipe-carrying
// case that exercises the findings-table cell escaping.
const { add, double, formatUser, isSet, notify } = require('./subject');

test('labels the expectation', () => {
  // the string cannot shadow the real call site — the tautology still fires
  const label = 'expect';
  expect(double(2)).toBe(double(2));
});

test('adds numbers', () => {
  add(2, 3);
});

test('formats the user the same way the formatter does', () => {
  expect(formatUser({ id: 1 })).toEqual(formatUser({ id: 1 }));
});

test('flags either flag', () => {
  expect(isSet(left || right)).toBe(isSet(left || right));
});

test('notifies the mailer', () => {
  const mailer = { send: jest.fn() };
  notify(mailer);
  expect(mailer.send).toHaveBeenCalled();
});
