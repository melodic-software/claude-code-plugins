// test-scope: scripts/affected-tests.sh
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { test } from "node:test";

import { tempDir } from "../../../lib/test-tmp.mjs";
import { declarationRefusal, declaredPaths, insertDeclarations, leadingBlock, suiteComment } from "./test-scope.mjs";

const REPO_ROOT = join(import.meta.dirname, "../../..");

const FIXTURES = {
  "a/shebang.test.sh": "#!/usr/bin/env bash\n# Checks x.\n# test-scope: scripts/x.sh\n#test-scope: a b\n\nset -e\n# test-scope: late.sh\n",
  "a/module.test.mjs": "#!/usr/bin/env node\n// Checks y.\n// test-scope: lib/y.mjs\nimport assert from 'node:assert';\n",
  "a/plain.test.js": "// test-scope: lib/z.js\n# test-scope: not-read\n",
  "a/test_doc.py": '# test-scope: py/a.py\n"""Doc.\n# test-scope: inside-docstring\n"""\n',
  "a/Pester.Tests.ps1": "# test-scope: ps/a.ps1\r\n# Describes.\r\nDescribe 'x' {}\r\n# test-scope: never\r\n",
  "a/none.test.sh": "set -e\n# test-scope: after-code\n",
  "a/blank-inside.test.sh": "# One.\n\n   \n# test-scope: after-blank\ncode\n",
  "a/not-a-suite.sh": "# test-scope: ignored\n",
  "a/e_test.py": "# test-scope: ignored\n",
};

function scopeDeclarationsByScript(dir, files) {
  const source = readFileSync(join(REPO_ROOT, "scripts/affected-tests.sh"), "utf8");
  const fn = /^scope_declarations\(\) \{\n[\s\S]*?\n\}\n/m.exec(source)[0];
  writeFileSync(join(dir, "list"), `${files.join("\n")}\n`);
  return execFileSync("bash", ["-c", `${fn}\nscope_declarations list`], { cwd: dir, encoding: "utf8" }).split("\n").filter(Boolean);
}

test("leadingBlock reads the declarations scripts/affected-tests.sh scope_declarations reads, line for line", (t) => {
  const dir = tempDir("test-scope-");
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  for (const [path, text] of Object.entries(FIXTURES)) {
    mkdirSync(join(dir, dirname(path)), { recursive: true });
    writeFileSync(join(dir, path), text);
  }
  const files = Object.keys(FIXTURES);
  const expected = scopeDeclarationsByScript(dir, files);
  const actual = files.flatMap((path) => {
    const comment = suiteComment(path);
    return comment === null ? [] : leadingBlock(FIXTURES[path], comment).declarations.map((declaration) => `${path} ${declaration.rest}`);
  });
  assert.deepEqual(actual, expected);
  assert.ok(expected.length >= 7, "the fixtures declare in every suite type");
});

test("suiteComment names // for .test.js and .test.mjs suites, # for shell, Pester and pytest suites, and null for other files", () => {
  assert.equal(suiteComment("x/a.test.mjs"), "//");
  assert.equal(suiteComment("x/a.test.js"), "//");
  assert.equal(suiteComment("x/a.test.sh"), "#");
  assert.equal(suiteComment("x/A.Tests.ps1"), "#");
  assert.equal(suiteComment("x/test_a.py"), "#");
  assert.equal(suiteComment("x/a_test.py"), null);
  assert.equal(suiteComment("x/a.sh"), null);
});

test("insertDeclarations writes one line per path after the leading block's last comment line, keeping CRLF", () => {
  assert.equal(insertDeclarations("#!/bin/bash\n# One.\nset -e\n", "#", ["a.sh", "b.sh"]), "#!/bin/bash\n# One.\n# test-scope: a.sh\n# test-scope: b.sh\nset -e\n");
  assert.equal(insertDeclarations("#!/usr/bin/env node\nimport x from 'x';\n", "//", ["lib/x.mjs"]), "#!/usr/bin/env node\n// test-scope: lib/x.mjs\nimport x from 'x';\n");
  assert.equal(insertDeclarations('"""Doc."""\nimport os\n', "#", ["a.py"]), '# test-scope: a.py\n"""Doc."""\nimport os\n');
  assert.equal(insertDeclarations("# A.\r\nDescribe 'x' {}\r\n", "#", ["a.ps1"]), "# A.\r\n# test-scope: a.ps1\r\nDescribe 'x' {}\r\n");
  assert.equal(insertDeclarations("# only, no newline", "#", ["a.sh"]), null, "no line can follow a last line with no end");
});

test("every insertDeclarations result passes declarationRefusal and declares the paths", () => {
  for (const [path, text] of Object.entries(FIXTURES)) {
    const comment = suiteComment(path);
    if (comment === null) {
      continue;
    }
    const after = insertDeclarations(text, comment, ["new/one.sh", "new/two.sh"]);
    assert.equal(declarationRefusal(path, text, after), null, path);
    assert.deepEqual(declaredPaths(after, comment).slice(-2), ["new/one.sh", "new/two.sh"], path);
  }
});

test("declarationRefusal refuses a change that is not exact test-scope lines added to the leading block", () => {
  const before = "#!/bin/bash\n# One.\nset -e\n";
  const cases = [
    ["x/a.sh", "#!/bin/bash\n# One.\n# test-scope: a.sh\nset -e\n", /not a suite/],
    ["x/a.test.sh", "#!/bin/bash\n# One.\n# test-scope: a.sh\n", /removes or rewrites/],
    ["x/a.test.sh", before, /adds no line/],
    ["x/a.test.sh", "#!/bin/bash\n# One.\n// test-scope: a.sh\nset -e\n", /not a # test-scope line/],
    ["x/a.test.sh", "#!/bin/bash\n# One.\n# test-scope: a.sh\r\nset -e\n", /not a # test-scope line/],
    ["x/a.test.sh", "#!/bin/bash\n# One.\n# test-scope: ../a.sh x\nset -e\n", /not a # test-scope line/],
    ["x/a.test.sh", "#!/bin/bash\n# One.\nset -e\n# test-scope: a.sh\n", /outside the leading comment block/],
    ["x/a.test.sh", "#!/bin/bash\n# One.\n# test-scope: a.sh\n# test-scope: a.sh\nset -e\n", /repeats a declared path/],
  ];
  for (const [path, after, why] of cases) {
    assert.match(String(declarationRefusal(path, before, after)), why, after);
  }
  assert.match(String(declarationRefusal("x/a.test.sh", "# test-scope: a.sh\nset -e\n", "# test-scope: a.sh\n# test-scope: a.sh\nset -e\n")), /repeats a declared path/);
  assert.equal(declarationRefusal("x/a.test.sh", before, "#!/bin/bash\n# One.\n# test-scope: a.sh\nset -e\n"), null);
});
