#!/usr/bin/env bash
# Seeds the eval workspace with a small app: semantic tokens over primitives, a Button whose
# variant union is closed, an IconButton, and call sites where secondary is the usual variant.
set -euo pipefail

mkdir -p src/components src/screens
cat > package.json <<'JSON'
{ "name": "ledgerline", "private": true, "dependencies": { "react": "^19.0.0" } }
JSON
cat > src/tokens.css <<'CSS'
:root {
  --gray-100: oklch(0.99 0 none);
  --gray-300: oklch(0.94 0 none);
  --gray-1200: oklch(0.24 0 none);
  --red-1100: oklch(0.55 0.2 25);
}

:root {
  --bg-surface: var(--gray-100);
  --border-subtle: var(--gray-300);
  --text-primary: var(--gray-1200);
  --text-danger: var(--red-1100);
  --accent: var(--gray-1200);
}
CSS
cat > src/components/Button.tsx <<'TSX'
import * as React from "react";

type ButtonProps = {
  variant?: "primary" | "secondary" | "danger";
} & React.ComponentProps<"button">;

export function Button({ variant = "secondary", ...props }: ButtonProps) {
  return <button type="button" className={"button button-" + variant} {...props} />;
}
TSX
cat > src/components/IconButton.tsx <<'TSX'
import * as React from "react";

type IconButtonProps = { label: string; icon: React.ReactNode } & React.ComponentProps<"button">;

export function IconButton({ label, icon, ...props }: IconButtonProps) {
  return <button type="button" aria-label={label} className="icon-button" {...props}>{icon}</button>;
}
TSX
cat > src/screens/Invoice.tsx <<'TSX'
import { Button } from "../components/Button";
import { IconButton } from "../components/IconButton";

export function Invoice() {
  return (
    <footer>
      <IconButton label="More actions" icon="..." />
      <Button>Cancel</Button>
      <Button variant="danger">Void invoice</Button>
      <Button variant="primary">Send invoice</Button>
    </footer>
  );
}
TSX
cat > src/screens/Settings.tsx <<'TSX'
import { Button } from "../components/Button";

export function Settings() {
  return (
    <div>
      <Button>Export</Button>
      <Button>Reset filters</Button>
      <Button variant="primary">Save</Button>
    </div>
  );
}
TSX
