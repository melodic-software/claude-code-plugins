# Area router

Maps a user's request onto the coverage areas this plugin serves. Areas are **arguments** to the
verb skills, never skills of their own. Routing rules:

- Match the user's words to the closest area key below (an invocation may name one, several, or —
  after an explicit confirm — all areas). Unknown phrasing: pick the nearest key and say which
  mapping was made; ask only when genuinely ambiguous.
- The **doc pointer** is a stable entry hub on `docs.github.com`, not the answer: resolve the
  exact current page live from that hub (or the site's own search) and pass it through the
  method ladder's fetch-integrity check before grounding on it. Hubs verified live 2026-07-20;
  if one 404s, resolve via the live docs search instead.
- **Primary**-tier areas get the deepest treatment (dedicated method recipes ship in a later
  phase); every other area rides the generic method ladder with this row as its entry intent.

| Area key | Tier | Intent (one line) | Doc entry pointer |
|---|---|---|---|
| `rulesets` | primary | Repo/org rulesets and repo-settings drift: protection rules, bypass lists, consistency across repos | <https://docs.github.com/en/repositories> |
| `custom-properties` | standard | Org custom properties: schema, required values, repo classification | <https://docs.github.com/en/organizations> |
| `billing` | primary | Billing and licensing: monitoring, budgets, alerts, usage, cost control | <https://docs.github.com/en/billing> |
| `security-model` | standard | Organization security model: org/repo roles, member privileges, base permissions | <https://docs.github.com/en/organizations> |
| `codespaces` | standard | Codespaces: org policies, machine types, spending, access | <https://docs.github.com/en/codespaces> |
| `cloud-sandboxes` | standard | Cloud sandboxes for agents: availability, policy, spend (no stable docs hub verified 2026-07-20 — resolve live via docs search) | <https://docs.github.com/en/search> |
| `projects-and-issues` | standard | Projects, issue types, issue fields, and templates: planning-surface configuration | <https://docs.github.com/en/issues> |
| `actions` | primary | Actions policy: allowed actions/workflows, runners, runner groups, custom images, caches, OIDC | <https://docs.github.com/en/actions> |
| `webhooks` | standard | Webhooks: org/repo hooks, delivery health, secret hygiene, dead endpoints | <https://docs.github.com/en/webhooks> |
| `discussions` | standard | Discussions: enablement, categories, moderation posture | <https://docs.github.com/en/discussions> |
| `packages` | standard | Packages: registries, visibility, retention, access | <https://docs.github.com/en/packages> |
| `pages` | standard | Pages: enablement policy, custom domains, HTTPS enforcement | <https://docs.github.com/en/pages> |
| `hosted-compute-networking` | standard | Hosted compute networking: network configurations for hosted runners/compute | <https://docs.github.com/en/actions> |
| `authentication-security` | primary | Authentication security: 2FA requirements, SSO, session/credential policy | <https://docs.github.com/en/authentication> |
| `advanced-security` | primary | Advanced security: security configurations, global settings, feature enablement | <https://docs.github.com/en/code-security> |
| `code-quality` | standard | Code quality: enablement and posture (evolving surface — re-verify live) | <https://docs.github.com/en/code-security> |
| `deploy-keys` | standard | Deploy keys: inventory, read/write split, staleness | <https://docs.github.com/en/authentication> |
| `compliance` | standard | Compliance: reports and attestations access | <https://docs.github.com/en/organizations> |
| `verified-domains` | standard | Verified and approved domains: verification state, email policy coupling | <https://docs.github.com/en/organizations> |
| `secrets-and-variables` | standard | Secrets and variables across modalities (Actions, agents, Codespaces, Dependabot, private registries): inventory, scoping, staleness | <https://docs.github.com/en/actions> |
| `github-apps` | primary | GitHub Apps: installed apps, permissions creep, org app policy | <https://docs.github.com/en/apps> |
| `oauth-app-policy` | primary | OAuth app policy: access restrictions, approved apps | <https://docs.github.com/en/organizations> |
| `personal-access-tokens` | primary | Personal access tokens: org PAT settings, active tokens, pending requests | <https://docs.github.com/en/authentication> |
| `scheduled-reminders` | standard | Scheduled reminders: team/org reminder configuration | <https://docs.github.com/en/organizations> |
| `archive-logs` | standard | Archive logs: audit log and sponsorship log review/streaming posture | <https://docs.github.com/en/organizations> |
| `deleted-repositories` | standard | Deleted repositories: restorable inventory and retention window | <https://docs.github.com/en/repositories> |
| `developer-settings` | standard | Developer settings: owned OAuth Apps, GitHub Apps, publisher verification | <https://docs.github.com/en/apps> |
