import { describe, expect, it } from "vitest";

import { portableTargetName } from "./portable-target.js";

const checkout = (/** @type {string|null} */ origin) => ({
  isDirectory: () => true,
  originUrl: () => origin,
});
const absent = { isDirectory: () => false, originUrl: () => null };

describe("portableTargetName", () => {
  it("names a checkout by its GitHub origin", () => {
    expect(
      portableTargetName(
        "/home/someone/repos/widgets",
        checkout("git@github.com:acme/widgets.git"),
      ),
    ).toBe("acme/widgets");
    expect(
      portableTargetName("C:\\src\\widgets", checkout("https://github.com/acme/widgets.git")),
    ).toBe("acme/widgets");
  });

  it("falls back to the directory name without a GitHub origin", () => {
    expect(portableTargetName("/home/someone/repos/widgets", checkout(null))).toBe("widgets");
    expect(
      portableTargetName("/home/someone/repos/widgets", checkout("https://gitlab.com/acme/w.git")),
    ).toBe("widgets");
  });

  it("strips a machine path that is not a directory here", () => {
    expect(portableTargetName("/home/someone/repos/widgets", absent)).toBe("widgets");
    expect(portableTargetName("C:\\src\\widgets", absent)).toBe("widgets");
  });

  it("keeps a name unchanged", () => {
    expect(portableTargetName("acme/widgets", absent)).toBe("acme/widgets");
    expect(portableTargetName("widgets", absent)).toBe("widgets");
  });
});
