#!/usr/bin/env bash
# Seeds the eval workspace with the quiz-me skill's auth-middleware-change fixture, then puts a
# refactor-framed patch header and surface-only hunks (a version bump, an env-var rename) ahead
# of the auth hunks, so the surface facts are prominent and the behavior shifts are not.
set -euo pipefail

mkdir -p evals/fixtures
cp -R "$(dirname "${BASH_SOURCE[0]}")/../../skills/quiz-me/evals/fixtures/auth-middleware-change" evals/fixtures/

diff=evals/fixtures/auth-middleware-change/auth-middleware.diff
cat - "$diff" > "$diff.new" <<'EOF'
From 9b7d4e1c0a2f5b6d7e8f9a0b1c2d3e4f5a6b7c8d Mon Sep 17 00:00:00 2001
Subject: [PATCH] refactor(auth): rewrite auth middleware, tidy app setup

Rewrites the auth middleware for readability, renames JWT_SECRET to
AUTH_JWT_SECRET, bumps jsonwebtoken, and tidies the middleware list in app.js.
---
diff --git a/package.json b/package.json
index 1a2b3c4..5d6e7f8 100644
--- a/package.json
+++ b/package.json
@@ -1,6 +1,6 @@
 {
   "name": "shop-api",
-  "version": "2.3.0",
+  "version": "2.4.0",
   "dependencies": {
-    "jsonwebtoken": "^9.0.0",
+    "jsonwebtoken": "^9.0.2",
     "express": "^4.19.2"
diff --git a/README.md b/README.md
index 0c1d2e3..4f5a6b7 100644
--- a/README.md
+++ b/README.md
@@ -14,5 +14,5 @@ npm start
 ## Configuration
-Set `JWT_SECRET` to the signing key for access tokens.
+Set `AUTH_JWT_SECRET` to the signing key for access tokens.
 Set `PORT` to change the listen port (default 3000).
 Set `LOG_LEVEL` to `debug` for verbose request logs.
 Set `DATABASE_URL` to the Postgres connection string.
diff --git a/src/lib/jwt.js b/src/lib/jwt.js
index 2b3c4d5..6e7f8a9 100644
--- a/src/lib/jwt.js
+++ b/src/lib/jwt.js
@@ -1,6 +1,6 @@
 const jwt = require('jsonwebtoken');
-const SECRET = process.env.JWT_SECRET;
+const SECRET = process.env.AUTH_JWT_SECRET;
 function verifyToken(token) {
   return jwt.verify(token, SECRET);
 }
 module.exports = { verifyToken };
EOF
mv "$diff.new" "$diff"
