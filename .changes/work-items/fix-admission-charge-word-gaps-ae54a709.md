---
bump: patch
---

### Fixed

- The charge words now hold a paid tier with words between (`paid Cloudflare plan`, `paid key`), a named GitHub, Copilot, Cloudflare, Pulumi or Enterprise plan, a resource on another billing account (`AWS account`, `OpenAI API`, `Vertex AI`), and a stated keep period (`artifacts for 400 days`). Before, each one reached admission with no owner hold.
