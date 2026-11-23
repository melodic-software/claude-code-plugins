import assert from "node:assert/strict";
import { test } from "node:test";
import { AddError, resolveAdded } from "./added.mjs";

const installed = (...entries) => new Map(entries.map(([id, skills = []]) => [id, { id, dependsOn: [], skills }]));
const INV = installed(["songwriting@m", ["lyrics", "audit"]], ["review@m", ["audit"]], ["widget@vendor", ["gadget"]]);
const refusal = (fn) => {
  try {
    fn();
  } catch (error) {
    assert.ok(error instanceof AddError, error.message);
    return error.message;
  }
  assert.fail("expected an AddError");
};

test("#18314: a plugin id, a plugin name, plugin:skill and a skill one plugin carries each resolve to that plugin's id", () => {
  for (const token of ["songwriting@m", "songwriting", "songwriting:lyrics", "lyrics"]) assert.deepEqual(resolveAdded([token], INV), ["songwriting@m"], token);
  assert.deepEqual(resolveAdded(["gadget", "widget", "review"], INV), ["widget@vendor", "review@m"], "one id per plugin, in the order given");
});

test("#18314: a token two installed plugins match is refused with every candidate", () => {
  const twoNames = installed(["songwriting@m"], ["songwriting@vendor"]);
  assert.match(refusal(() => resolveAdded(["songwriting"], twoNames)), /songwriting matches more than one installed plugin; give one of: songwriting@m, songwriting@vendor/);
  assert.match(refusal(() => resolveAdded(["audit"], INV)), /audit matches more than one installed plugin; give one of: review@m, songwriting@m/);
  assert.deepEqual(resolveAdded(["songwriting@vendor"], twoNames), ["songwriting@vendor"], "the full id settles it");
});

test("#18314: a plugin that is not installed is refused with its claude plugin install line", () => {
  assert.match(refusal(() => resolveAdded(["debugging@m"], INV)), /debugging@m is not installed\. Install it with: claude plugin install debugging@m$/);
  const known = () => ["debugging@m", "writing@m"];
  assert.match(refusal(() => resolveAdded(["debugging"], INV, known)), /debugging is not installed\. Install it with: claude plugin install debugging@m$/);
  assert.match(refusal(() => resolveAdded(["debugging:debug"], INV, known)), /claude plugin install debugging@m$/);
  assert.match(refusal(() => resolveAdded(["nosuch"], INV, known)), /no installed plugin or skill is named nosuch, and no profile or known marketplace names a plugin nosuch/);
});

test("#18314: settings text, a path or an empty word is refused, so --profile-add never carries settings", () => {
  for (const token of ['{"enabledPlugins":{"x@m":true}}', "./extra.json", "/tmp/s.json", "", "a b", "x@m@n"]) {
    assert.match(refusal(() => resolveAdded([token], INV)), /takes a plugin id, a plugin name, plugin:skill or a skill name/, token);
  }
});
