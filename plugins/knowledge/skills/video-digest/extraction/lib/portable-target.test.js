import { execFileSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { describe, expect, it } from "vitest";

import { portableTargetName } from "./portable-target.js";

const checkout = (/** @type {string|null} */ origin) => ({
  checkoutOrigin: () => ({ origin }),
});
const absent = { checkoutOrigin: () => null };

describe("portableTargetName", () => {
  it("names a checkout by its GitHub origin", () => {
    expect(
      portableTargetName(
        "/srv/repos/widgets",
        checkout("git@github.com:acme/widgets.git"),
      ),
    ).toBe("acme/widgets");
    expect(
      portableTargetName("C:\\src\\widgets", checkout("https://github.com/acme/widgets.git")),
    ).toBe("acme/widgets");
  });

  it("reads the ssh:// and credentialed https forms of a GitHub origin", () => {
    expect(
      portableTargetName("/r/w", checkout("ssh://git@github.com/acme/widgets.git")),
    ).toBe("acme/widgets");
    expect(
      portableTargetName("/r/w", checkout("https://x-access-token:abc@github.com/acme/widgets.git")),
    ).toBe("acme/widgets");
  });

  it("falls back to the directory name without a GitHub origin", () => {
    expect(portableTargetName("/srv/repos/widgets", checkout(null))).toBe("widgets");
    expect(
      portableTargetName("/srv/repos/widgets", checkout("https://gitlab.com/acme/w.git")),
    ).toBe("widgets");
  });

  it("strips a machine path that is not a checkout here", () => {
    expect(portableTargetName("/srv/repos/widgets", absent)).toBe("widgets");
    expect(portableTargetName("C:\\src\\widgets", absent)).toBe("widgets");
    expect(portableTargetName("../widgets", absent)).toBe("widgets");
    expect(portableTargetName("~/repos/widgets", absent)).toBe("widgets");
  });

  it("keeps a name unchanged", () => {
    expect(portableTargetName("acme/widgets", absent)).toBe("acme/widgets");
    expect(portableTargetName("widgets", absent)).toBe("widgets");
  });

  it("refuses a path with no name in it", () => {
    expect(() => portableTargetName("/", absent)).toThrow(/no name/);
  });

  it("never names a subdirectory of a checkout after the enclosing repository", () => {
    const repo = fs.mkdtempSync(path.join(os.tmpdir(), "portable-target-"));
    try {
      execFileSync("git", ["init", "-q", repo]);
      execFileSync("git", ["-C", repo, "remote", "add", "origin", "git@github.com:acme/widgets.git"]);
      fs.mkdirSync(path.join(repo, "docs"));

      expect(portableTargetName(repo)).toBe("acme/widgets");
      expect(portableTargetName(path.join(repo, "docs"))).toBe("docs");
      expect(portableTargetName("docs", { cwd: repo })).toBe("docs");
    } finally {
      fs.rmSync(repo, { recursive: true, force: true });
    }
  });
});
