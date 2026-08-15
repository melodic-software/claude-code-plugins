// Mock-only fixture: fires ONLY testing/audit/rule-mock-only-oracle — used to
// prove the rule is advisory in --check by default and gating under --strict.
test('publishes to the bus', () => {
  const bus = { publish: jest.fn() };
  publishEvent(bus);
  expect(bus.publish).toHaveBeenCalledWith('event');
});
