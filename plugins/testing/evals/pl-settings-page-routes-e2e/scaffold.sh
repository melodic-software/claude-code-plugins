#!/usr/bin/env bash
# A React web app on a feature branch that adds a settings page and its route; only the existing
# home page has a test.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/git-workspace.sh"
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
ws_init main web .remote.git
mkdir -p web/src/pages
cat >web/package.json <<'EOF'
{
  "name": "account-web",
  "private": true,
  "scripts": { "test": "vitest run", "e2e": "playwright test" },
  "devDependencies": { "@playwright/test": "1.63.0", "@testing-library/react": "16.3.0", "vitest": "4.0.6" }
}
EOF
cat >web/src/pages/Home.tsx <<'EOF'
export function Home() {
  return <h1>Welcome back</h1>;
}
EOF
cat >web/src/pages/Home.test.tsx <<'EOF'
import { render, screen } from "@testing-library/react";
import { expect, test } from "vitest";
import { Home } from "./Home";

test("greets the user", () => {
  render(<Home />);
  expect(screen.getByRole("heading").textContent).toBe("Welcome back");
});
EOF
cat >web/src/routes.tsx <<'EOF'
import { Home } from "./pages/Home";

export const routes = [{ path: "/", element: <Home /> }];
EOF
g add -A
g commit -q -m "account web"
ws_origin
g switch -q -c feature/settings-page
cat >web/src/pages/Settings.tsx <<'EOF'
import { useState } from "react";

export function Settings({ onSave }: { onSave: (email: string) => Promise<void> }) {
  const [email, setEmail] = useState("");
  const [error, setError] = useState<string | null>(null);
  return (
    <form
      onSubmit={async (event) => {
        event.preventDefault();
        if (!email.includes("@")) {
          setError("Enter a valid email address");
          return;
        }
        await onSave(email);
      }}
    >
      <label>
        Email <input value={email} onChange={(event) => setEmail(event.target.value)} />
      </label>
      {error && <p role="alert">{error}</p>}
      <button type="submit">Save</button>
    </form>
  );
}
EOF
cat >web/src/routes.tsx <<'EOF'
import { Home } from "./pages/Home";
import { Settings } from "./pages/Settings";
import { saveEmail } from "./api";

export const routes = [
  { path: "/", element: <Home /> },
  { path: "/settings", element: <Settings onSave={saveEmail} /> },
];
EOF
cat >web/src/api.ts <<'EOF'
export async function saveEmail(email: string): Promise<void> {
  await fetch("/api/account/email", { method: "PUT", body: JSON.stringify({ email }) });
}
EOF
g add -A
g commit -q -m "settings page"
