# Spindle documentation: add-ons for administrators

Synthetic source page for the attribution golden set. Spindle is a fictional editor platform
invented for these fixtures. Nothing on this page describes a real product or reproduces text
from a real page.

Canonical location for the purposes of this case: `https://example.invalid/spindle/docs/addons/admin`.

## What happens by default

The built-in guard `safe-baseline` loads only on machines with managed settings or for users
signed in with a Business plan. Where it loads, a user's add-on can't approve a call that a
`block` rule refuses, unless an administrator sets `allowAddonsToOverrideBlockRules`.

## Which controls still apply

Where the guard doesn't load, any installed add-on's `call.review` hook can approve a call a
`block` rule refuses.
