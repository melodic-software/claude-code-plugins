---
schema_version: "1.1"
name: audit-diff-copy-button
description: "Happy path: a diff that adds an icon-only copy button gets an accessibility review that leads with a Blocked verdict, grades the missing accessible name Blocking and the silent copied state as a finding, in a Before, After, Why table"
tags: [web, audit, diff, accessibility, happy-path]
runs: 5
max_turns: 20
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The review opens with a one-line verdict, Blocked, before any finding; reports the icon-only copy button with no accessible name as Blocking with an action name such as aria-label=\"Copy code\" as the fix; and reports that the copied confirmation (the icon swap to a check) reaches no screen reader, with a polite live region or status role present before the message as the fix"
---

Review this diff for accessibility before I merge it. It adds a copy button to the code blocks in
our React docs site.

```diff
--- a/src/components/CodeBlock.tsx
+++ b/src/components/CodeBlock.tsx
@@ -1,9 +1,24 @@
+import { useState } from "react";
+import { CheckIcon, CopyIcon } from "./icons";
+
 export function CodeBlock({ code }: { code: string }) {
+  const [copied, setCopied] = useState(false);
+
+  function copy() {
+    navigator.clipboard.writeText(code);
+    setCopied(true);
+    setTimeout(() => setCopied(false), 2000);
+  }
+
   return (
-    <pre className="rounded-lg border px-4 py-3 font-mono text-sm">{code}</pre>
+    <div className="relative">
+      <pre className="rounded-lg border px-4 py-3 font-mono text-sm">{code}</pre>
+      <button className="absolute right-2 top-2 size-11" onClick={copy}>
+        {copied ? <CheckIcon /> : <CopyIcon />}
+      </button>
+    </div>
   );
 }
```

This run cannot write files, so put the review in your reply.
