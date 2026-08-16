import { defineConfig } from "vitest/config";

// Self-contained plugin config — no reach-out to a repo-root base under cache isolation.
export default defineConfig({
  test: {},
});
