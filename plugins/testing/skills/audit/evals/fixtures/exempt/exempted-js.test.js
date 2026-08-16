// Exempt fixture: an annotated deliberate case — zero findings, one counted
// exemption.
// cant-fail-ok: smoke test — intentionally asserts nothing, exercises startup only
test('boots the app', () => {
  bootApp();
});
