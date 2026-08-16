// Sanity fixture: exactly ONE assertion-free test. The issue's settlement
// check runs the detector here and expects exactly one
// testing/audit/rule-zero-assertion finding, then feeds the findings file to
// the review fix pass.
test('records the payment', () => {
  const gateway = createGateway();
  gateway.charge(100);
});
