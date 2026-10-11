#!/usr/bin/env bash
# Seeds a greenfield recipe app: a PRD and the routes for sign-up through the first recipe.
set -euo pipefail

mkdir -p docs app/signup app/verify-email app/onboarding/pantry app/recipes/new
cat > package.json <<'JSON'
{ "name": "larder", "private": true, "dependencies": { "next": "^15.0.0", "react": "^19.0.0" } }
JSON
cat > docs/PRD.md <<'MD'
# Larder: product requirements

Larder lets home cooks save recipes and plan meals from what is already in their pantry.

## First success
A new user has succeeded once they save their first recipe.

## Sign-up
- Email and password, or continue with Google.
- The email must be verified before anything can be saved; unverified users can browse.

## Onboarding
- Pantry setup: pick staples from a list. Optional, and can be skipped.
- Then the empty recipe box with "Add your first recipe": paste a URL or type it in.

## Open questions
- Should pantry setup come before or after the first recipe?
MD
cat > app/signup/page.tsx <<'TSX'
export default function SignupPage() {
  return <form>{/* email, password, continue with Google */}</form>;
}
TSX
cat > app/verify-email/page.tsx <<'TSX'
export default function VerifyEmailPage() {
  return <p>{/* check your inbox; resend link */}</p>;
}
TSX
cat > app/onboarding/pantry/page.tsx <<'TSX'
export default function PantrySetupPage() {
  return <section>{/* staple checklist; skip for now */}</section>;
}
TSX
cat > app/recipes/new/page.tsx <<'TSX'
export default function NewRecipePage() {
  return <form>{/* paste a URL or type the recipe; save */}</form>;
}
TSX
