import assert from "node:assert/strict";
import test from "node:test";

import { resolveProviderLogos } from "../lib/provider-logos.js";

test("provider logos use bundled files without downloading fallbacks", async () => {
  const logos = {
    anthropic: "assets/logo-anthropic.svg",
    absent: "assets/not-bundled.svg",
    textOnly: null,
  };

  const result = await resolveProviderLogos(logos);

  assert.deepEqual(result.available, ["anthropic → assets/logo-anthropic.svg"]);
  assert.deepEqual(result.missing, ["absent (assets/not-bundled.svg)"]);
  assert.deepEqual(result.skipped, ["textOnly (intentionally null)"]);
  assert.equal(logos.absent, null);
});
