// Negative fixture (AVA/node-tap style): assertions live on the test-context
// object (t.<method>), not expect/assert — the vocabulary must accept them.
const test = require('ava');
const { add } = require('./subject');

test('adds', (t) => {
  t.is(add(2, 3), 5);
});

test('deep equals', (t) => {
  t.deepEqual([add(1, 1)], [2]);
});
